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

      deployment_info, offline_uids = pre_deployment_process(deployment_info)

      support_virtual_node(tasks_graph)
      unzip_graph(tasks_graph, tasks_directory)

      Deployment::Log.logger = Astute.logger
      cluster = TaskCluster.new
      cluster.node_concurrency.maximum = Astute.config.max_nodes_per_call
      cluster.stop_condition { Thread.current[:gracefully_stop] }

      tasks_graph.keys.each do |node_id|
        node = TaskNode.new(node_id, cluster)
        node.context = @ctx
        node.set_critical if critical_node_uids(deployment_info).include?(node_id)
        node.set_status_failed if offline_uids.include? node_id
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

    def pre_deployment_process(deployment_info)
      return [[],[]] if deployment_info.blank?

      deployment_info, offline_uids = remove_failed_nodes(deployment_info)
      Astute::TaskPreDeploymentActions.new(deployment_info, @ctx).process
      [deployment_info, offline_uids]
    end

    def report_deploy_result(result)
      if result[:success]
        @ctx.report('status' => 'ready', 'progress' => 100)
      else
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
        @ctx.report(
          'status' => 'error',
          'progress' => 100,
          'error' => result[:status]
        )
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

    def critical_node_uids(deployment_info)
      @critical_nodes ||= deployment_info.select{ |n| n['fail_if_error'] }
                                         .map{ |n| n['uid'] }.uniq
    end

    # Removes nodes which failed to provision
    def remove_failed_nodes(deployment_info)
      uids = get_uids_from_deployment_info deployment_info
      required_uids = critical_node_uids(deployment_info)

      available_uids = detect_available_nodes(uids)
      offline_uids = uids - available_uids
      if offline_uids.present?
        # set status for all failed nodes to error
        nodes = (uids - available_uids).map do |uid|
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

        # check if all required nodes are online
        # if not, raise error
        missing_required = required_uids - available_uids
        if missing_required.present?
          error_message = "Critical nodes are not available for deployment: " \
                          "#{missing_required}"
          raise Astute::DeploymentEngineError, error_message
        end
      end

      return remove_offline_nodes(
        uids,
        available_uids,
        deployment_info,
        offline_uids)
    end

    def remove_offline_nodes(uids, available_uids, deployment_info, offline_uids)
      if offline_uids.blank?
        return [deployment_info, offline_uids]
      end

      Astute.logger.info "Removing nodes which failed to provision: " \
                         "#{offline_uids}"
      deployment_info = cleanup_nodes_block(deployment_info, offline_uids)
      deployment_info = deployment_info.select do |node|
        available_uids.include? node['uid']
      end

      [deployment_info, offline_uids]
    end

    def cleanup_nodes_block(deployment_info, offline_uids)
      return deployment_info if offline_uids.blank?

      nodes = deployment_info.first['nodes']

      # In case of deploy in already existing cluster in nodes block
      # we will have all cluster nodes. We should remove only missing
      # nodes instead of stay only avaliable.
      # Example: deploy 3 nodes, after it deploy 2 nodes.
      # In 1 of 2 seconds nodes missing, in nodes block we should
      # contain only 4 nodes.
      nodes_wthout_missing = nodes.select do |node|
        !offline_uids.include?(node['uid'])
      end
      deployment_info.each { |node| node['nodes'] = nodes_wthout_missing }
      deployment_info
    end

    def detect_available_nodes(uids)
      all_uids = uids.clone
      available_uids = []

      # In case of big amount of nodes we should do several calls to be sure
      # about node status
      Astute.config[:mc_retries].times.each do
        systemtype = Astute::MClient.new(
          @ctx,
          "systemtype",
          all_uids,
          _check_result=false,
          10
        )
        available_nodes = systemtype.get_type.select do |node|
          node.results[:data][:node_type].chomp == "target"
        end

        available_uids += available_nodes.map { |node| node.results[:sender] }
        all_uids -= available_uids
        break if all_uids.empty?

        sleep Astute.config[:mc_retry_interval]
      end

      available_uids
    end

    def get_uids_from_deployment_info(deployment_info)
      top_level_uids = deployment_info.map{ |node| node["uid"] }

      inside_uids = deployment_info.inject([]) do |uids, node|
        uids += node.fetch('nodes', []).map{ |n| n['uid'] }
      end
      top_level_uids | inside_uids
    end
  end
end
