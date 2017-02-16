#    Copyright 2016 Mirantis, Inc.
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
  class MasterShell < Task

    # Accept to run shell tasks using existing shell asynchronous
    # mechanism. It will run task on master node.

    def post_initialize(task, context)
      @shell_task = nil
    end

    def summary
      @shell_task.summary
    rescue
      {}
    end

    private

    def process
      @shell_task = Shell.new(
        generate_master_shell,
        @ctx
      )
      @shell_task.run
    end

    def calculate_status
      self.status = @shell_task.status
    end

    def validation
      validate_presence(task['parameters'], 'cmd')
    end

    def setup_default
      task['parameters']['timeout'] ||= Astute.config.shell_timeout
      task['parameters']['cwd'] ||= Astute.config.shell_cwd
      task['parameters']['retries'] ||= Astute.config.shell_retries
      task['parameters']['interval'] ||= Astute.config.shell_interval
    end

    def generate_master_shell
      task.merge('node_id' => 'master')
    end
  end
end
