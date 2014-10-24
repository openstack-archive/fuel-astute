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

      @ctx.deploy_log_parser.deploy_type = deployment_info.first['deployment_mode']
      Astute.logger.info "Deployment mode #{@ctx.deploy_log_parser.deploy_type}"

      begin
        PreDeploymentActions.new(deployment_info, @ctx).process
        NailgunHooks.new(pre_deployment, @ctx).process
      rescue => e
        Astute.logger.error("Unexpected error #{e.message} traceback #{e.format_backtrace}")
        raise e
      end

      pre_node_actions = PreNodeActions.new(@ctx)

      fail_deploy = false
      # Sort by priority (the lower the number, the higher the priority)
      # and send groups to deploy
      deployment_info.sort_by { |f| f['priority'] }.group_by{ |f| f['priority'] }.each do |_, nodes|
        # Prevent attempts to run several deploy on a single node.
        # This is possible because one node
        # can perform multiple roles.
        group_by_uniq_values(nodes).each do |nodes_group|
          # Prevent deploy too many nodes at once
          nodes_group.each_slice(Astute.config[:MAX_NODES_PER_CALL]) do |part|
            if !fail_deploy

              # Pre deploy hooks
              pre_node_actions.process(part)
              PreDeployActions.new(part, @ctx).process

              deploy_piece(part)

              # Post deploy hook
              PostDeployActions.new(part, @ctx).process

              fail_deploy = fail_critical_node?(part)
            else
              nodes_to_report = part.map do |n|
                {
                  'uid' => n['uid'],
                  'role' => n['role']
                }
              end
              Astute.logger.warn "This nodes: #{nodes_to_report} will " \
                "not deploy because at least one critical node deployment fail"
            end
          end
        end
      end

      # Post deployment hooks
      begin
        NailgunHooks.new(post_deployment, @ctx).process
      rescue => e
        # We should fail all nodes in case of post deployment
        # process. In other case they will not sending back
        # for redeploy
        nodes = deployment_info.uniq {|n| n['uid']}.map do |node|
          { 'uid' => node['uid'],
            'status' => 'error',
            'role' => 'hook',
            'error_type' => 'deploy',
          }
        end
        @ctx.report_and_update_status('nodes' => nodes)
        raise e
      end

      PostDeploymentActions.new(deployment_info, @ctx).process
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

    def fail_critical_node?(part)
      nodes_status = @ctx.status
      return false unless nodes_status.has_value?('error')

      stop_uids = part.select{ |n| n['fail_if_error'] }.map{ |n| n['uid'] } &
                  nodes_status.select { |k, v| v == 'error' }.keys
      return false if stop_uids.empty?

      Astute.logger.warn "#{@ctx.task_id}: Critical nodes with uids: #{stop_uids.join(', ')} " \
                         "fail to deploy. Stop deployment"
      true
    end

  end
end
