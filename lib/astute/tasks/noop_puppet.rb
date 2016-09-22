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

require 'astute/tasks/puppet'

module Astute
  class NoopPuppet < Puppet

    private

    def create_puppet_task
      PuppetTask.new(
        @ctx,
        {'uid' => @task['node_id'].to_s, 'task' => task_name},
        {
          :retries => @task['parameters']['retries'],
          :puppet_manifest => @task['parameters']['puppet_manifest'],
          :puppet_modules => @task['parameters']['puppet_modules'],
          :cwd => @task['parameters']['cwd'],
          :timeout => @task['parameters']['timeout'],
          :puppet_debug => @task['parameters']['debug'],
          :puppet_noop_run => true,
          :raw_report => true
        }
      )
    end

  end
end
