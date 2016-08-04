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
  class NoopPuppet < Puppet

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

    def create_puppet_task
      PuppetTask.new(
        Context.new(
          @ctx.task_id,
          PuppetLoggerReporter.new,
          LogParser::NoParsing.new
        ),
        {'uid' => @task['node_id'].to_s, 'role' => task_name},
        {
          :retries => @task['parameters']['retries'],
          :puppet_manifest => @task['parameters']['puppet_manifest'],
          :puppet_modules => @task['parameters']['puppet_modules'],
          :cwd => @task['parameters']['cwd'],
          :timeout => @task['parameters']['timeout'],
          :puppet_debug => @task['parameters']['debug'],
          :puppet_noop => true,
          :puppet_noop_report => Astute.config.puppet_noop_report + task_name + '.json'
        }
      )
    end

  end # class

  class PuppetLoggerReporter
    def report(msg)
      Astute.logger.debug msg
    end
  end

end
