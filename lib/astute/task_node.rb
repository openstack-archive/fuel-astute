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

require 'fuel_deployment'

module Astute
  class TaskNode < Deployment::Node
    def context=(context)
      @ctx = context
    end

    def run(inbox_task)
      self.task = inbox_task
      @task_engine = select_task_engine(task.data)
      @task_engine.run
      task.set_status_running
      set_status_busy
    end

    def poll
      return unless busy?

      debug("Node #{id}: task #{task.name}, task status #{task.status}")

      # Please be informed that this code define special method
      # of Deployment::Node class. We use special method `task`
      # to manage task status, graph of tasks and nodes.
      task.status = @task_engine.status
      if @task.running?
        @ctx.report({
          'uid' => id,
          'status' => 'deploying',
          'task' => task.name,
          'progress' => current_progress_bar
        })
      else
        set_status_online

        deploy_status = if !finished?
          'deploying'
        elsif successful?
          'ready'
        else
          'error'
        end

        report_status = {
          'uid' => id,
          'status' => deploy_status,
          'task' => task.name,
          'task_status' => task.status.to_s,
          'progress' => current_progress_bar
        }
        report_status.merge!('error_type' => 'deploy') if
          deploy_status == 'error'
        @ctx.report(report_status)
      end
    end

    private

    def current_progress_bar
      100 * tasks_finished_count / tasks_total_count
    end

    def select_task_engine(data)
      # TODO: replace by Object.const_get(type.split('_').collect(&:capitalize).join)
      case data['type']
      when 'shell' then Shell.new(data, @ctx)
      when 'puppet' then Puppet.new(data, @ctx)
      when 'upload_file' then UploadFile.new(data, @ctx)
      when 'upload_files' then UploadFiles.new(data, @ctx)
      when 'reboot' then Reboot.new(data, @ctx)
      when 'sync' then Sync.new(data, @ctx)
      when 'cobbler_sync' then CobblerSync.new(data, @ctx)
      when 'copy_files' then CopyFiles.new(data, @ctx)
      when 'noop' then Noop.new(data, @ctx)
      when 'stage' then Noop.new(data, @ctx)
      when 'skipped' then Noop.new(data, @ctx)
      else raise TaskValidationError, "Unknown task type '#{data['type']}'"
      end
    end
  end
end