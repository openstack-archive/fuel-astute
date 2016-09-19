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
      report_node_status if report_running?(task.data)
    end

    def poll
      return unless busy?

      debug("Node #{uid}: task #{task.name}, task status #{task.status}")

      # Please be informed that this code define special method
      # of Deployment::Node class. We use special method `task`
      # to manage task status, graph of tasks and nodes.
      task.status = setup_task_status
      if @task.running?
        @ctx.report({
          'nodes' => [{
            'uid' => uid,
            'deployment_graph_task_name' => task.name,
            'progress' => current_progress_bar,
            'task_status' => task.status.to_s,
          }]
        })
      else
        info "Finished task: #{task} with status: #{status}"
        setup_node_status
        report_node_status
      end
    end

    def report_node_status
      node_status = {
        'uid' => uid,
        'progress' => current_progress_bar,
      }
      node_status.merge!(node_report_status)

      if task
        node_status.merge!(
          'deployment_graph_task_name' => task.name,
          'task_status' => task.status.to_s,
          'summary' => @task_engine.summary
        )
        node_status.merge!(
          'error_msg' => "Task #{task.name} failed on node #{name}"
        ) if task.failed?
      end

      @ctx.report('nodes' => [node_status], 'progress' => cluster_progress)
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
      if tasks_total_count != 0
        100 * tasks_finished_count / tasks_total_count
      else
        100
      end
    end

    def cluster_progress
      if cluster.tasks_total_count != 0
        100 * cluster.tasks_finished_count / cluster.tasks_total_count
      else
        100
      end
    end

    def select_task_engine(data)
      noop_prefix = noop_run? && not_noop_type?(data) ? "Noop" : ""
      task_class_name = noop_prefix + data['type'].split('_').collect(&:capitalize).join
      Object.const_get('Astute::' + task_class_name).new(data, @ctx)
    rescue => e
      raise TaskValidationError, "Unknown task type '#{data['type']}'. Detailed: #{e.message}"
    end

    def report_running?(data)
      !['noop', 'stage', 'skipped'].include?(data['type'])
    end

    def noop_run?
      cluster.noop_run
    end

    def node_report_status
      if !finished?
        {}
      elsif successful?
        cluster.node_statuses_transitions.fetch('successful', {})
      elsif skipped?
        cluster.node_statuses_transitions.fetch('stopped', {})
      else
        cluster.node_statuses_transitions.fetch('failed', {})
      end
    end

    def not_noop_type?(data)
      !['noop', 'stage', 'skipped'].include?(data['type'])
    end

  end
end
