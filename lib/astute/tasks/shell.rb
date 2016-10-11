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

    # Accept to run shell tasks using existing puppet asynchronous
    # mechanism. It create and upload 2 files: shell script and
    # puppet manifest. Then run puppet manifest

    def initialize(task, context)
      super
      @puppet_task = nil
    end

    def summary
      @puppet_task.summary
    rescue
      {}
    end

    private

    SHELL_MANIFEST_DIR = '/etc/puppet/shell_manifests'

    def process
      run_shell_without_check(
        @task['node_id'],
        "mkdir -p #{SHELL_MANIFEST_DIR}",
        _timeout=2
      )
      upload_shell_manifest
      @puppet_task = Puppet.new(
        generate_puppet_hook,
        @ctx
      )
      @puppet_task.run
    end

    def calculate_status
      self.status = @puppet_task.status
    end

    def validation
      validate_presence(@task, 'node_id')
      validate_presence(@task['parameters'], 'cmd')
    end

    def setup_default
      @task['parameters']['timeout'] ||= Astute.config.shell_timeout
      @task['parameters']['cwd'] ||= Astute.config.shell_cwd
      @task['parameters']['retries'] ||= Astute.config.shell_retries
      @task['parameters']['interval'] ||= Astute.config.shell_interval
    end

    def puppet_exec_template
      template = <<-eos
    # Puppet manifest wrapper for task: <%= task_name %>
    notice('MODULAR: <%= task_name %>')

    exec { '<%= task_name %>_shell' :
      path      => '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
      command   => '/bin/bash "<%= shell_exec_file_path %>"',
      logoutput => true,
      timeout   => <%= timeout %>,
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
        'path' => puppet_exec_file_path,
        'content' => puppet_exec_template,
        'permissions' => '0755'
      })
    end

    def upload_shell_file
      upload_file(@task['node_id'], {
        'path' => shell_exec_file_path,
        'content' => shell_exec_template,
        'permissions' => '0755'
      })
    end

    def upload_shell_manifest
      upload_puppet_manifest
      upload_shell_file
    end

    def timeout
      @task['parameters']['timeout']
    end

    def manifest_name
      "#{task_name}_manifest.pp"
    end

    def generate_puppet_hook
      {
        'node_id' => @task['node_id'],
        'id' => @task['id'],
        'parameters' =>  {
          "puppet_manifest" =>  manifest_name,
          "cwd" => SHELL_MANIFEST_DIR,
          "timeout" =>  @task['parameters']['timeout'],
          "retries" => @task['parameters']['retries']
        }
      }
    end

  end
end
