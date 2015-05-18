#    Copyright 2013 Mirantis, Inc.
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
  class DeploymentEngine

    def initialize(context)
      if self.class.superclass.name == 'Object'
        raise "Instantiation of this superclass is not allowed. Please subclass from #{self.class.name}."
      end
      @ctx = context
    end

    def deploy(deployment_info, pre_deployment=[], post_deployment=[])
      raise "Deployment info are not provided!" if deployment_info.blank?

      deployment_info, pre_deployment, post_deployment = remove_failed_nodes(deployment_info,
                                                                             pre_deployment,
                                                                             post_deployment)

      @ctx.deploy_log_parser.deploy_type = deployment_info.first['deployment_mode']
      Astute.logger.info "Deployment mode #{@ctx.deploy_log_parser.deploy_type}"

      begin
        pre_deployment_actions(deployment_info, pre_deployment)
      rescue => e
        Astute.logger.error("Unexpected error #{e.message} traceback #{e.format_backtrace}")
        raise e
      end

      failed = []
      # Sort by priority (the lower the number, the higher the priority)
      # and send groups to deploy
      deployment_info.sort_by { |f| f['priority'] }.group_by{ |f| f['priority'] }.each do |_, nodes|
        # Prevent attempts to run several deploy on a single node.
        # This is possible because one node
        # can perform multiple roles.
        group_by_uniq_values(nodes).each do |nodes_group|
          # Prevent deploy too many nodes at once
          nodes_group.each_slice(Astute.config[:max_nodes_per_call]) do |part|

            # for each chunk run group deployment pipeline

            # create links to the astute.yaml
            pre_deploy_actions(part)

            # run group deployment
            deploy_piece(part)

            failed = critical_failed_nodes(part)

            # if any of the node are critical and failed
            # raise an error and mark all other nodes as error
            if failed.any?
              # TODO(dshulyak) maybe we should print all failed tasks for this nodes
              # but i am not sure how it will look like
              raise Astute::DeploymentEngineError, "Deployment failed on nodes #{failed.join(', ')}"
            end
          end
        end
      end

      # Post deployment hooks
      post_deployment_actions(deployment_info, post_deployment)
    end

    protected

    def validate_nodes(nodes)
      return true unless nodes.empty?

      Astute.logger.info "#{@ctx.task_id}: Nodes to deploy are not provided. Do nothing."
      false
    end

    private

    # Transform nodes source array to array of nodes arrays where subarray
    # contain only uniq elements from source
    # Source: [
    #   {'uid' => 1, 'role' => 'cinder'},
    #   {'uid' => 2, 'role' => 'cinder'},
    #   {'uid' => 2, 'role' => 'compute'}]
    # Result: [
    #   [{'uid' =>1, 'role' => 'cinder'},
    #    {'uid' => 2, 'role' => 'cinder'}],
    #   [{'uid' => 2, 'role' => 'compute'}]]
    def group_by_uniq_values(nodes_array)
      nodes_array = deep_copy(nodes_array)
      sub_arrays = []
      while !nodes_array.empty?
        sub_arrays << uniq_nodes(nodes_array)
        uniq_nodes(nodes_array).clone.each {|e| nodes_array.slice!(nodes_array.index(e)) }
      end
      sub_arrays
    end

    def uniq_nodes(nodes_array)
      nodes_array.inject([]) { |result, node| result << node unless include_node?(result, node); result }
    end

    def include_node?(nodes_array, node)
      nodes_array.find { |n| node['uid'] == n['uid'] }
    end

    def nodes_status(nodes, status, data_to_merge)
      {
        'nodes' => nodes.map do |n|
          {'uid' => n['uid'], 'status' => status, 'role' => n['role']}.merge(data_to_merge)
        end
      }
    end

    def critical_failed_nodes(part)
        part.select{ |n| n['fail_if_error'] }.map{ |n| n['uid'] } &
            @ctx.status.select { |k, v| v == 'error' }.keys
    end

    def pre_deployment_actions(deployment_info, pre_deployment)
      raise "Should be implemented"
    end

    def pre_node_actions(part)
      raise "Should be implemented"
    end

    def pre_deploy_actions(part)
      raise "Should be implemented"
    end

    def post_deploy_actions(part)
      raise "Should be implemented"
    end

    def post_deployment_actions(deployment_info, post_deployment)
      raise "Should be implemented"
    end

    # Removes nodes which failed to provision
    def remove_failed_nodes(deployment_info, pre_deployment, post_deployment)
      uids = deployment_info.map { |node| node["uid"]}
      required_nodes = deployment_info.select { |node| node["fail_if_error"] }
      required_uids = required_nodes.map { |node| node["uid"]}

      systemtype = Astute::MClient.new(@ctx, "systemtype", uids, check_result=false, 10)
      available_nodes = systemtype.get_type.select do |node|
        node.results[:data][:node_type].chomp == "target"
      end
      available_uids = available_nodes.map { |node| node.results[:sender]}
      offline_uids = uids - available_uids
      if offline_uids.present?
        # set status for all failed nodes to error
        nodes = (uids - available_uids).map do |uid|
          {'uid' => uid,
           'status' => 'error',
           'error_type' => 'provision',
           # Avoid deployment reporter param validation
           'role' => 'hook',
           'error_msg' => 'Node is not ready for deployment: mcollective has not answered'
          }
        end

        @ctx.report_and_update_status('nodes' => nodes, 'error' => 'Node is not ready for deployment')

        # check if all required nodes are online
        # if not, raise error
        missing_required = required_uids - available_uids
        if missing_required.present?
          error_message = 'Critical nodes are not available for deployment: #{missing_required}'
          raise Astute::DeploymentEngineError, error_message
        end
      end

      return remove_offline_nodes(
        uids,
        available_uids,
        pre_deployment,
        deployment_info,
        post_deployment,
        offline_uids)
    end

    def remove_offline_nodes(uids, available_uids, pre_deployment, deployment_info, post_deployment, offline_uids)
      if offline_uids.blank?
        return [deployment_info, pre_deployment, post_deployment]
      end

      Astute.logger.info "Removing nodes which failed to provision: #{offline_uids}"
      deployment_info = cleanup_nodes_block(deployment_info, offline_uids)
      deployment_info = deployment_info.select { |node| available_uids.include? node['uid'] }

      available_uids += ["master"]
      pre_deployment.each do |task|
        task['uids'] = task['uids'].select { |uid| available_uids.include? uid }
      end
      post_deployment.each do |task|
        task['uids'] = task['uids'].select { |uid| available_uids.include? uid }
      end

      # Remove irrelevant tasks if there is no node, where they should be run
      [pre_deployment, post_deployment].each do |deployment_task|
        deployment_task.select! { |task| task['uids'].present? }
      end

      pre_deployment = cleanup_nodes_task_block(pre_deployment, offline_uids)
      post_deployment = cleanup_nodes_task_block(post_deployment, offline_uids)

      [deployment_info, pre_deployment, post_deployment]
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
      nodes_wthout_missing = nodes.select { |node| !offline_uids.include?(node['uid']) }
      deployment_info.each { |node| node['nodes'] = nodes_wthout_missing }
      deployment_info
    end

    def cleanup_nodes_task_block(deployment_tasks, offline_uids)
      return deployment_tasks if offline_uids.blank?

      # We have hosts hook which contain info about
      # all nodes including missing
      deployment_tasks.each do |task|
        if (task['type'] == 'upload_file') &&
            is_host_nodes?(task.fetch('parameters', {})['data'])
          data = YAML.load task['parameters']['data']
          data['nodes'].select! { |node| !offline_uids.include? node['uid'] }
          # FIXME(vsharshov): ruby add leading hyphens '---'
          # It can potencially broken multiline YAML content
          task['parameters']['data'] = YAML.dump data
        end
      end

      deployment_tasks
    end

    def is_host_nodes?(text)
      # Example:
      # nodes:
      # - {fqdn: node-6.test.domain.local, name: node-6, role: cinder, swift_zone '6, uid: '6', user_node_name: slave-06_cinder}
      is_hosts = ['nodes', 'fqdn', 'name', 'role', 'uid', 'user_node_name'].all? { |key| text.include? key }
      return false unless is_hosts
      data = YAML.load text
      data['nodes'].present?
    rescue
      false
    end

  end
end
