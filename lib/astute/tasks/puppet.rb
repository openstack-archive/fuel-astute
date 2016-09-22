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

require 'timeout'

module Astute
  class Puppet < Task

    def summary
      @puppet_task.summary
    rescue
      {}
    end

    private

    def process
      @puppet_task = create_puppet_task
      @puppet_task.run
    end

    def calculate_status
      self.status = @puppet_task.status.to_sym
    end

    def validation
      validate_presence(@task, 'node_id')
      validate_presence(@task['parameters'], 'puppet_manifest')
    end

    def setup_default
      @task['parameters']['cwd'] ||= '/'
      @task['parameters']['timeout'] ||= Astute.config.puppet_timeout
      @task['parameters']['retries'] ||= Astute.config.puppet_retries
      @task['parameters']['debug'] = false unless @task['parameters']['debug'].present?
      @task['parameters']['puppet_modules'] ||= Astute.config.puppet_module_path
    end

    def create_puppet_task
      PuppetJob.new(
        @ctx,
        {'uid' => @task['node_id'].to_s, 'task' => task_name},
        {
          :retries => @task['parameters']['retries'],
          :puppet_manifest => @task['parameters']['puppet_manifest'],
          :puppet_modules => @task['parameters']['puppet_modules'],
          :cwd => @task['parameters']['cwd'],
          :timeout => @task['parameters']['timeout'],
          :puppet_debug => @task['parameters']['debug']
        }
      )
    end

  end # class
end
