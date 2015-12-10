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

module Astute
  class Sync < Task

    private

    def process
      @shell_task = Shell.new(
        generate_shell_hook,
        @ctx
      )
      @shell_task.run
    end

    def calculate_status
      self.status = @shell_task.status
    end

    def validation
      validate_presence(@task, 'node_id')
      validate_presence(@task['parameters'], 'dst')
      validate_presence(@task['parameters'], 'src')
    end

    def setup_default
      @task['parameters']['timeout'] ||= 300
      @task['parameters']['retries'] ||= 10
    end

    def generate_shell_hook
      path = @task['parameters']['dst']
      rsync_cmd = "mkdir -p #{path} && rsync #{Astute.config.rsync_options}" \
                  " #{@task['parameters']['src']} #{path}"
      {
        "node_id" => @task['node_id'],
        "id" => @task['id'],
        "parameters" =>  {
          "cmd" =>  rsync_cmd,
          "cwd" =>  "/",
          "timeout" => @task['parameters']['timeout'],
          "retries" => @task['parameters']['retries']
        }
      }
    end

  end
end
