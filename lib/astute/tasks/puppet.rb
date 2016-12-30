#    Copyright 2014 Mirantis, Inc.
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

module Astute
  class Puppet < Task

    def summary
      puppet_task.summary
    rescue
      {}
    end

    private

    def process
      Astute.logger.debug "Puppet task options: "\
        "#{@task['parameters'].pretty_inspect}"
      puppet_task.run
    end

    def calculate_status
      self.status = puppet_task.status.to_sym
    end

    def validation
      validate_presence(@task, 'node_id')
      validate_presence(@task['parameters'], 'puppet_manifest')
    end

    def setup_default
      default_options = {
        'retries' => Astute.config.puppet_retries,
        'puppet_manifest' => '/etc/puppet/manifests/site.pp',
        'puppet_modules' => Astute.config.puppet_module_path,
        'cwd' => Astute.config.shell_cwd,
        'timeout' => Astute.config.puppet_timeout,
        'puppet_debug' => false,
        'succeed_retries' => Astute.config.puppet_succeed_retries,
        'undefined_retries' => Astute.config.puppet_undefined_retries,
        'raw_report' => Astute.config.puppet_raw_report,
        'puppet_noop_run' => Astute.config.puppet_noop_run,
        'puppet_start_timeout' => Astute.config.puppet_start_timeout,
        'puppet_start_interval' => Astute.config.puppet_start_interval
      }
      @task['parameters'].compact!
      @task['parameters'].reverse_merge!(default_options)
    end

    def puppet_task
      @puppet_task ||= PuppetJob.new(
        task_name,
        PuppetMClient.new(
          @ctx,
          @task['node_id'],
          @task['parameters'],
        ),
        {
          'retries' => @task['parameters']['retries'],
          'succeed_retries' => @task['parameters']['succeed_retries'],
          'undefined_retries' => @task['parameters']['undefined_retries'],
          'timeout' => @task['parameters']['timeout'],
          'puppet_start_timeout' => @task['parameters'][
            'puppet_start_timeout'],
          'puppet_start_interval' => @task['parameters'][
            'puppet_start_interval']
        }
      )
    end

  end # class
end
