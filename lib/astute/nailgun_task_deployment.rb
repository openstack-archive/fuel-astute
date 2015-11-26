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
require 'fuel-deployment'

module Astute

  class NailgunNode < Deployment::Node
    def run

    end

    def pull

    end
  end


  class TaskDeployment

    def initialize(context)
      @ctx = context
    end

    def deploy(deployment_info)
      raise "Deployment info are not provided!" if deployment_info.blank?

      # TODO: implement integration with fuel-deployment

      # FIXME: this key must be change to real
      nodes = deployment_info['tasks'].keys.inject([]) do |nodes, node_id|
        nodes << NailgunNode.new(node_id)
      end


      Deployment::Process.new(nodes)
      remove_failed_nodes(deployment_info)

    end

    private

    # Removes nodes which failed to provision
    def remove_failed_nodes(deployment_info, pre_deployment, post_deployment)
      uids = get_uids_from_deployment_info deployment_info
      required_nodes = deployment_info.select { |node| node["fail_if_error"] }
      required_uids = required_nodes.map { |node| node["uid"]}

      available_uids = detect_available_nodes(uids)
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
          error_message = "Critical nodes are not available for deployment: #{missing_required}"
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

      [pre_deployment, post_deployment].each do |deployment_task|
        deployment_task.select! do |task|
          if task['uids'].present?
            true
          else
            Astute.logger.info "Task(hook) was deleted because there is no " \
              "node where it should be run \n#{task.to_yaml}"
            false
          end
        end
      end

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

    def detect_available_nodes(uids)
      all_uids = uids.clone
      available_uids = []

      # In case of big amount of nodes we should do several calls to be sure
      # about node status
      Astute.config[:mc_retries].times.each do
        systemtype = Astute::MClient.new(@ctx, "systemtype", all_uids, check_result=false, 10)
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
