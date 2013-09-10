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

    def deploy(deployment_info)
      # Sort by priority (the lower the number, the higher the priority)
      # and send groups to deploy
      deployment_info.sort_by { |f| f['priority'] }.group_by{ |f| f['priority'] }.each do |priority, nodes|
        # Prevent attempts to run several deploy on a single node.
        # This is possible because one node
        # can perform multiple roles.
        group_by_uniq_values(nodes).each { |nodes_group| deploy_piece(nodes_group) }
      end
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
      {'nodes' => nodes.map { |n| {'uid' => n['uid'], 'status' => status}.merge(data_to_merge) }}
    end

  end
end
