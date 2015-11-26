#    Copyright 2015 Mirantis, Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.
require 'erb'

module Astute
  class Shell < Task

    private

    SHELL_MANIFEST_DIR = '/etc/puppet/shell_manifests'
    PUPPET_MODULES_DIR = '/etc/puppet/modules'

    def process
      run_shell_without_check(
        @task['node_id'],
        "mkdir -p #{SHELL_MANIFEST_DIR}",
        timeout=2
      )
      upload_shell_manifest
      @puppet_task = Puppet.new(
        generate_puppet_hook,
        @ctx
      ).run
    end

    def calculate_status
      status = @puppet_task.status
    end

    def pre_validation
      validate_presence(@task, 'node_id')
      validate_presence(@task['parameters'], 'cmd')
    end

    def setup_default
      @task['parameters']['timeout'] ||= 300
      @task['parameters']['cwd'] ||= "/"
      @task['parameters']['retries'] ||= Astute.config.mc_retries
      @task['parameters']['interval'] ||= Astute.config.mc_retry_interval
    end

    def puppet_exec_template
      template = <<-eos
    # Puppet manifest wrapper for task: <%= task_name %>
    notice('MODULAR: <%= task_name %>')

    exec { '<%= task_name %>_shell' :
      path      => '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
      command   => '/bin/bash "<%= shell_exec_file_path %>"',
      logoutput => true,
    }
      eos
      ERB.new(template, nil, '-').result(binding)
    end

    def shell_exec_template
      command = "cd #{@task['parameters']['cwd']} &&" \
                " #{@task['parameters']['cmd']}"
      template = <<-eos
    #!/bin/bash
    # Puppet shell wrapper for task: <%= task_name %>
    # Manifest: <%= puppet_exec_file_path %>

    <%= command %>
      eos
      ERB.new(template, nil, '-').result(binding)
    end

    def shell_exec_file_path
      File.join(SHELL_MANIFEST_DIR, "#{task_name}_command.sh")
    end

    def puppet_exec_file_path
      File.join(SHELL_MANIFEST_DIR, manifest_name)
    end

    def upload_puppet_manifest
      upload_file(@task['node_id'], {
        :path => puppet_exec_file_path,
        :content => puppet_exec_template,
        :permissions => '0755'
      })
    end

    def upload_shell_file
      upload_file(@task['node_id'], {
        :path => shell_exec_file_path,
        :content => shell_exec_template,
        :permissions => '0755'
      })
    end

    def upload_shell_manifest
      upload_puppet_manifest
      upload_shell_file
    end


    def manifest_name
      "#{task_name}_manifest.pp"
    end

    def generate_puppet_hook
      {
        'node_id' => @task['node_id'],
        'id' => @task['id'] + '_puppet',
        'parameters' =>  {
          "puppet_manifest" =>  manifest_name,
          "puppet_modules" =>  PUPPET_MODULES_DIR,
          "cwd" => SHELL_MANIFEST_DIR,
          "timeout" =>  @task['parameters']['timeout'],
          "retries" => @task['parameters']['retries']
        }
      }
    end

  end
end