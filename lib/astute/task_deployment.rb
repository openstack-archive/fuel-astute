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
require_relative '../fuel_deployment'

module Astute
  class TaskDeployment

    def initialize(context, cluster_class=TaskCluster, node_class=TaskNode)
      @ctx = context
      @cluster_class = cluster_class
      @node_class = node_class
    end

    def create_cluster(deployment_options={})
      tasks_graph = deployment_options.fetch(:tasks_graph, {})
      tasks_directory = deployment_options.fetch(:tasks_directory, {})
      tasks_metadata = deployment_options.fetch(:tasks_metadata, {})

      raise DeploymentEngineError, 'Deployment graph was not provided!' if tasks_graph.blank?

      support_virtual_node(tasks_graph)
      unzip_graph(tasks_graph, tasks_directory)

      cluster = @cluster_class.new
      cluster.node_concurrency.maximum = Astute.config.max_nodes_per_call
      cluster.stop_condition { Thread.current[:gracefully_stop] }
      cluster.fault_tolerance_groups = tasks_metadata.fetch(
        'fault_tolerance_groups',
        []
      )
      cluster.noop_run = tasks_metadata.fetch(
        'noop',
        false
      )

      offline_uids = fail_offline_nodes(tasks_graph)
      critical_uids = critical_node_uids(cluster.fault_tolerance_groups)

      tasks_graph.keys.each do |node_id|
        node = @node_class.new(node_id, cluster)
        node.context = @ctx
        node.set_critical if critical_uids.include?(node_id)
        node.set_as_sync_point if sync_point?(node_id)
        node.set_status_failed if offline_uids.include?(node_id)
      end

      setup_tasks(tasks_graph, cluster)
      setup_task_depends(tasks_graph, cluster)
      setup_task_concurrency(tasks_graph, cluster)
      cluster
    end

    def deploy(deployment_options={})
      cluster = create_cluster(deployment_options)
      dry_run = deployment_options.fetch(:dry_run, false)
      Deployment::Log.logger = Astute.logger if Astute.respond_to? :logger
      write_graph_to_file(cluster)
      if dry_run
        result = Hash.new
        result[:success] = true
      else
        result = cluster.run
        # imitate dry_run results for noop run after deployment
        if cluster.noop_run
          result = Hash.new
          result[:success] = true
        end
      end
      report_deploy_result(result)
    end

    private

    def sync_point?(node_id)
      'virtual_sync_node' == node_id
    end

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
      result.fetch(:failed_nodes, []).each do |node|
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

      tasks_graph.each do |_node_id, tasks|
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

    def critical_node_uids(fault_tolerance_groups)
      return [] unless fault_tolerance_groups
      critical_nodes = fault_tolerance_groups.inject([]) do |critical_uids, group|
        critical_uids += group['node_ids'] if group['fault_tolerance'].zero?
        critical_uids
      end
      Astute.logger.info "Critical node #{critical_nodes}" if critical_nodes.present?
      critical_nodes
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
      if !uids.empty?
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
      end

      Astute.logger.warn "Offline node #{uids}" if uids.present?
      uids
    end

  end
end
