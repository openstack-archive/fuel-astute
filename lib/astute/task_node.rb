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
      @task_engine = select_task_engine(task.data, noop_run?)
      @task_engine.run
      task.set_status_running
      set_status_busy
      report_node_status if report_running?(task.data)
    end

    def poll
      return unless busy?

      debug("Node #{id}: task #{task.name}, task status #{task.status}")

      # Please be informed that this code define special method
      # of Deployment::Node class. We use special method `task`
      # to manage task status, graph of tasks and nodes.
      task.status = setup_task_status
      if @task.running?
        @ctx.report({
          'nodes' => [{
            'uid' => id,
            'status' => 'deploying',
            'deployment_graph_task_name' => task.name,
            'progress' => current_progress_bar,
            'task_status' => task.status.to_s,
          }]
        })
      else
        setup_node_status
        report_node_status
      end
    end

    def report_node_status
      deploy_status = if !finished?
        'deploying'
      elsif successful?
        'ready'
      elsif skipped?
        'stopped'
      else
        'error'
      end

      node_status = {
        'uid' => id,
        'status' => deploy_status,
        'progress' => current_progress_bar,
      }

      node_status.merge!(
        'deployment_graph_task_name' => task.name,
        'task_status' => task.status.to_s,
        'custom' => @task_engine.summary
      ) if task

      node_status.merge!('error_type' => 'deploy') if
        deploy_status == 'error'

      @ctx.report('nodes' => [node_status])
    end

    private

    # This method support special task behavior. If task failed
    # and we do not think that deployment should be stopped, Astute
    # will mark such task as skipped and do not report error
    def setup_task_status
      if !task.data.fetch('fail_on_error', true) && @task_engine.failed?
        Astute.logger.warn "Task #{task.name} failed, but marked as skipped "\
                           "because of 'fail on error' behavior"
        return :skipped
      end
      @task_engine.status
    end

    def setup_node_status
      if task
        set_status_failed && return if task.failed?
        set_status_skipped && return if task.dep_failed?
      end

      set_status_online
    end

    def current_progress_bar
      100 * tasks_finished_count / tasks_total_count
    end

    def select_task_engine(data, noop)
      # TODO: replace by Object.const_get(type.split('_').collect(&:capitalize).join)
      case data['type']
      when 'shell' then Shell.new(data, @ctx)
      when 'puppet'
        if noop
          NoopPuppet.new(data, @ctx)
        else
          Puppet.new(data, @ctx)
        end
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

    def report_running?(data)
      !['noop', 'stage', 'skipped'].include?(data['type'])
    end

  end
end
