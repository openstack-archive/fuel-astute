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
  class TaskDeployment

    def initialize(context)
      @ctx = context
    end

    def deploy(tasks_graph: {}, tasks_directory: {} , deployment_info: [], dry_run: false)
      raise DeploymentEngineError, "Deployment graph was not provided!" if
        tasks_graph.blank?

      support_virtual_node(tasks_graph)
      unzip_graph(tasks_graph, tasks_directory)

      Deployment::Log.logger = Astute.logger
      cluster = TaskCluster.new
      cluster.node_concurrency.maximum = Astute.config.max_nodes_per_call
      cluster.stop_condition { Thread.current[:gracefully_stop] }

      offline_uids = fail_offline_nodes(tasks_graph)

      tasks_graph.keys.each do |node_id|
        node = TaskNode.new(node_id, cluster)
        node.context = @ctx
        node.set_critical if critical_node_uids(tasks_graph).include?(node_id)
        node.set_status_failed if offline_uids.include?(node_id)
      end

      setup_tasks(tasks_graph, cluster)
      setup_task_depends(tasks_graph, cluster)
      setup_task_concurrency(tasks_graph, cluster)

      write_graph_to_file(cluster)
      if dry_run
        result = Hash.new
        result[:success] = true
      else
        result = cluster.run
      end
      report_deploy_result(result)
    end

    private

    def unzip_graph(tasks_graph, tasks_directory)
      tasks_graph.each do |node_id, tasks|
        tasks.each do |task|
            task.merge!({'node_id' => node_id})
                .reverse_merge(tasks_directory.fetch(task['id'], {}))
        end
      end
      tasks_graph
    end

    def setup_tasks(tasks_graph, cluster)
      tasks_graph.each do |node_id, tasks|
        tasks.each do |task|
          cluster[node_id].graph.create_task(task['id'], task)
        end
      end
    end

    def setup_task_depends(tasks_graph, cluster)
      tasks_graph.each do |node_id, tasks|
        tasks.each do |task|
          task.fetch('requires', []).each do |d_t|
            cluster[node_id][task['id']].depends(
              cluster[d_t['node_id']][d_t['name']])
          end

          task.fetch('required_for', []).each do |d_t|
            cluster[node_id][task['id']].depended_on(
              cluster[d_t['node_id']][d_t['name']])
          end
        end
      end
    end

    def setup_task_concurrency(tasks_graph, cluster)
      tasks_graph.each do |_node_id, tasks|
        tasks.each do |task|
          cluster.task_concurrency[task['id']].maximum = task_concurrency_value(task)
        end
      end
    end

    def task_concurrency_value(task)
      strategy = task.fetch('parameters', {}).fetch('strategy', {})
      value = case strategy['type']
      when 'one_by_one' then 1
      when 'parallel' then strategy['amount'].to_i
      else 0
      end
      return value if value >= 0
      raise DeploymentEngineError, "Task concurrency expect only "\
        "non-negative integer, but got #{value}. Please check task #{task}"
    end

    def report_deploy_result(result)
      if result[:success] && result.fetch(:failed_nodes, []).empty?
        @ctx.report('status' => 'ready', 'progress' => 100)
      elsif result[:success] && result.fetch(:failed_nodes, []).present?
        report_failed_nodes(result)
        @ctx.report('status' => 'ready', 'progress' => 100)
      else
        report_failed_nodes(result)
        @ctx.report(
          'status' => 'error',
          'progress' => 100,
          'error' => result[:status]
        )
      end
    end

    def report_failed_nodes(result)
      result[:failed_nodes].each do |node|
        node_status = {
          'uid' => node.id,
          'status' => 'error',
          'error_type' => 'deploy',
          'error_msg' => result[:status]
        }
        task = result[:failed_tasks].find{ |t| t.node == node }
        if task
          node_status.merge!({
            'deployment_graph_task_name' => task.name,
            'task_status' => task.status.to_s
          })
        end
        @ctx.report('nodes' => [node_status])
      end
    end


    def write_graph_to_file(deployment)
      return unless Astute.config.enable_graph_file
      graph_file = File.join(
        Astute.config.graph_dot_dir,
        "graph-#{@ctx.task_id}.dot"
      )
      File.open(graph_file, 'w') { |f| f.write(deployment.to_dot) }
      Astute.logger.info("Check graph into file #{graph_file}")
    end

    # Astute use special virtual node for deployment tasks, because
    # any task must be connected to node. For task, which play
    # synchronization role, we create virtual_sync_node
    def support_virtual_node(tasks_graph)
      tasks_graph['virtual_sync_node'] = tasks_graph['null']
      tasks_graph.delete('null')

      tasks_graph.each do |node_id, tasks|
        tasks.each do |task|
          task.fetch('requires',[]).each do |d_t|
            d_t['node_id'] = 'virtual_sync_node' if d_t['node_id'].nil?
          end

          task.fetch('required_for', []).each do |d_t|
            d_t['node_id'] = 'virtual_sync_node' if d_t['node_id'].nil?
          end
        end
      end

      tasks_graph
    end

    def critical_node_uids(tasks_graph)
      @critical_node ||= tasks_graph.select { |n, tasks| critical_node?(tasks) }.keys
    end

    def critical_node?(tasks)
      tasks.any? { |task| task['fail_on_error'] }
    end

    def fail_offline_nodes(tasks_graph)
      offline_uids = detect_offline_nodes(tasks_graph.keys)
      if offline_uids.present?
        nodes = offline_uids.map do |uid|
          {'uid' => uid,
           'status' => 'error',
           'error_type' => 'provision',
           'error_msg' => 'Node is not ready for deployment: '\
                          'mcollective has not answered'
          }
        end

        @ctx.report_and_update_status(
          'nodes' => nodes,
          'error' => 'Node is not ready for deployment'
        )

        missing_required = critical_node_uids(tasks_graph) & offline_uids
        if missing_required.present?
          error_message = "Critical nodes are not available for deployment: " \
                          "#{missing_required}"
          raise Astute::DeploymentEngineError, error_message
        end
      end

      offline_uids
    end

    def detect_offline_nodes(uids)
      available_uids = []

      uids.delete('master')
      uids.delete('virtual_sync_node')
      # In case of big amount of nodes we should do several calls to be sure
      # about node status
      Astute.config.mc_retries.times.each do
        systemtype = Astute::MClient.new(
          @ctx,
          "systemtype",
          uids,
          _check_result=false,
          10
        )
        available_nodes = systemtype.get_type.select do |node|
          node.results[:data][:node_type].chomp == "target"
        end

        available_uids += available_nodes.map { |node| node.results[:sender] }
        uids -= available_uids
        break if uids.empty?

        sleep Astute.config.mc_retry_interval
      end

      uids
    end

  end
end
