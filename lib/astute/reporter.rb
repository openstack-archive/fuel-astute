# -*- coding: utf-8 -*-
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

require 'set'

STATES = {
  'offline'      => 0,
  'discover'     => 10,
  'provisioning' => 30,
  'provisioned'  => 40,
  'deploying'    => 50,
  'ready'        => 60,
  'error'        => 70
}

module Astute
  module ProxyReporter
    class DeploymentProxyReporter
      attr_accessor :deploy
      alias_method :deploy?, :deploy

      def initialize(up_reporter, deployment_info=[])
        @up_reporter = up_reporter
        @nodes = deployment_info.inject([]) do |nodes, di|
          nodes << {'uid' => di['uid'], 'role' => di['role'], 'fail_if_error' => di['fail_if_error']}
        end
        @deploy = deployment_info.present?
      end

      def report(data)
        Astute.logger.debug("Data received by DeploymentProxyReporter to report it up: #{data.inspect}")
        report_new_data(data)
      end

      private

      def report_new_data(data)
        if data['nodes']
          nodes_to_report = get_nodes_to_report(data['nodes'])
          return if nodes_to_report.empty? # Let's report only if nodes updated

          # Update nodes attributes in @nodes.
          update_saved_nodes(nodes_to_report)
          data['nodes'] = nodes_to_report
        end
        data.merge!(get_overall_status(data))
        Astute.logger.debug("Data send by DeploymentProxyReporter to report it up: #{data.inspect}")
        @up_reporter.report(data)
      end

      def get_overall_status(data)
        status = data['status']
        error_nodes = @nodes.select { |n| n['status'] == 'error' }.map{ |n| n['uid'] }
        msg = data['error']

        if status == 'ready' && error_nodes.any?
          status = 'error'
          msg = "Some error occured on nodes #{error_nodes.inspect}"
        end
        progress = data['progress']

        {'status' => status, 'error' => msg, 'progress' => progress}.reject{|k,v| v.nil?}
      end

      def get_nodes_to_report(nodes)
        nodes.map{ |node| node_validate(node) }.compact
      end

      def update_saved_nodes(new_nodes)
        # Update nodes attributes in @nodes.
        new_nodes.each do |node|
          saved_node = @nodes.find { |n| n['uid'] == node['uid'] && n['role'] == node['role'] }
          if saved_node
            node.each {|k, v| saved_node[k] = v}
          else
            @nodes << node
          end
        end
      end

      def node_validate(node)
        validates_basic_fields(node)

        calculate_multiroles_node_progress(node) if deploy?

        normalization_progress(node)

        compare_with_previous_state(node)
      end

      # Validate of basic fields in message about nodes
      def validates_basic_fields(node)
        err = []
        case
        when node['status']
          err << "Status provided #{node['status']} is not supported" unless STATES[node['status']]
        when node['progress']
          err << "progress value provided, but no status"
        end

        err << "Node role is not provided" if deploy? && !node['role']
        err << "Node uid is not provided" unless node['uid']

        if err.any?
          msg = "Validation of node: #{node.inspect} for report failed: #{err.join('; ')}."
          Astute.logger.error(msg)
          raise msg
        end
      end

      # Proportionally reduce the progress on the number of roles. Based on the
      # fact that each part makes the same contribution to the progress we divide
      # 100 to number of roles for this node. Also we prevent send final status for
      # node before all roles will be deployed. Final result for node:
      # * any error — error;
      # * without error — succes.
      # Example:
      # Node have 3 roles and already success deploy first role and now deploying
      # second(50%). Overall progress of the operation for node is
      # 50 / 3 + 1 * 100 / 3 = 49
      # We calculate it as 100/3 = 33% for every finished(success or fail) role
      # Exception: node which have fail_if_error status equal true for some
      # assigned node role. If this node role fail, we send error state for
      # the entire node immediately.
      def calculate_multiroles_node_progress(node)
        @finish_roles_for_nodes ||= []
        roles_of_node = @nodes.select { |n| n['uid'] == node['uid'] }
        all_roles_amount = roles_of_node.size

        return if all_roles_amount == 1 # calculation should only be done for multi roles

        finish_roles_amount = @finish_roles_for_nodes.select do |n|
          n['uid'] == node['uid'] && ['ready', 'error'].include?(n['status'])
        end.size
        return if finish_roles_amount == all_roles_amount # already done all work

        # recalculate progress for node
        node['progress'] = node['progress'].to_i/all_roles_amount + 100 * finish_roles_amount/all_roles_amount

        # save final state if present
        if ['ready', 'error'].include? node['status']
          @finish_roles_for_nodes << { 'uid' => node['uid'], 'role' => node['role'], 'status' => node['status'] }
          node['progress'] = 100 * (finish_roles_amount + 1)/all_roles_amount
        end

        # No more status update will be for node which failed and have fail_if_error as true
        fail_if_error = @nodes.select { |n| n['uid'] == node['uid'] && n['role'] == node['role'] }[0]['fail_if_error']
        fail_now = fail_if_error && node['status'] == 'error'

        if all_roles_amount - finish_roles_amount != 1 && !fail_now
          # block 'ready' or 'error' final status for node if not all roles yet deployed
          node['status'] = 'deploying'
          node.delete('error_type') # Additional field for error response
        elsif ['ready', 'error'].include? node['status']
          node['status'] = @finish_roles_for_nodes.select { |n| n['uid'] == node['uid'] }
                                                  .select { |n| n['status'] == 'error' }
                                                  .empty? ? 'ready' : 'error'
          node['progress'] = 100
          node['error_type'] = 'deploy' if node['status'] == 'error'
        end
      end

      # Normalization of progress field: ensures that the scaling progress was
      # in range from 0 to 100 and has a value of 100 fot the final node status
      def normalization_progress(node)
        if node['progress']
          if node['progress'] > 100
            Astute.logger.warn("Passed report for node with progress > 100: "\
                              "#{node.inspect}. Adjusting progress to 100.")
            node['progress'] = 100
          elsif node['progress'] < 0
            Astute.logger.warn("Passed report for node with progress < 0: "\
                              "#{node.inspect}. Adjusting progress to 0.")
            node['progress'] = 0
          end
        end
        if node['status'] && ['provisioned', 'ready'].include?(node['status']) && node['progress'] != 100
          Astute.logger.warn("In #{node['status']} state node should have progress 100, "\
                              "but node passed: #{node.inspect}. Setting it to 100")
          node['progress'] = 100
        end
      end

      # Comparison information about node with previous state.
      def compare_with_previous_state(node)
        saved_node = @nodes.find { |x| x['uid'] == node['uid'] && x['role'] == node['role'] }
        if saved_node
          saved_status = STATES[saved_node['status']].to_i
          node_status = STATES[node['status']] || saved_status
          saved_progress = saved_node['progress'].to_i
          node_progress = node['progress'] || saved_progress

          if node_status < saved_status
            Astute.logger.warn("Attempt to assign lower status detected: "\
                               "Status was: #{saved_node['status']}, attempted to "\
                               "assign: #{node['status']}. Skipping this node (id=#{node['uid']})")
            return
          end
          if node_progress < saved_progress && node_status == saved_status
            Astute.logger.warn("Attempt to assign lesser progress detected: "\
                               "Progress was: #{saved_node['status']}, attempted to "\
                               "assign: #{node['progress']}. Skipping this node (id=#{node['uid']})")
            return
          end

          # We need to update node here only if progress is greater, or status changed
          return if node.select{|k, v| saved_node[k] != v }.empty?
        end
        node
      end

    end # DeploymentProxyReporter
  end # ProxyReporter
end # Astute
