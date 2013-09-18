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
      def initialize(up_reporter, deployment_info=[], is_deploy=false)
        @up_reporter = up_reporter
        @nodes = []
        deployment_info.select { |node| node['status'] != 'ready' }.each do |di|
          @nodes << {'uid' => di['id'], 'role' => di['role']}
        end
        @is_deploy = is_deploy
      end

      def report(data)
        Astute.logger.debug("Data received by DeploymetProxyReporter to report it up: #{data.inspect}")
        report_new_data(data)
      end

    private

      def report_new_data(data)
        if data['nodes']
          nodes_to_report = get_nodes_to_report(data['nodes'])
          # Let's report only if nodes updated
          return if nodes_to_report.empty?
          # Update nodes attributes in @nodes.
          update_saved_nodes(nodes_to_report)
          data['nodes'] = nodes_to_report
        end
        data.merge!(get_overall_status(data))
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
        # Validate basic correctness of attributes.
        err = []
        if node['status']
          err << "Status provided #{node['status']} is not supported" unless STATES[node['status']]
        elsif node['progress']
          err << "progress value provided, but no status"
        end  
        err << "Node role is not provided" if @is_deploy && !node['role']
        err << "Node uid is not provided" unless node['uid']
        
        if err.any?
          msg = "Validation of node: #{node.inspect} for report failed: #{err.join('; ')}."
          Astute.logger.error(msg)
          raise msg
        end

        # Validate progress field.
        if node['progress']
          calculate_multiroles_node_progress(node) if @is_deploy
          node['progress'] = case
          when node['progress'] > 100
            Astute.logger.warn("Passed report for node with progress > 100: "\
                                "#{node.inspect}. Adjusting progress to 100.")
            100
          when node['progress'] < 0
            Astute.logger.warn("Passed report for node with progress < 0: "\
                                "#{node.inspect}. Adjusting progress to 0.")
            0
          end
        end
        if node['status'] && ['provisioned', 'ready'].include?(node['status']) && node['progress'] != 100
          Astute.logger.warn("In #{node['status']} state node should have progress 100, "\
                              "but node passed: #{node.inspect}. Setting it to 100")
          node['progress'] = 100
        end

        # Comparison with previous state.
        saved_node = @nodes.find { |x| x['uid'] == node['uid'] && x['role'] == node['role'] }
        if saved_node
          saved_status = STATES[saved_node['status']].to_i
          node_status = STATES[node['status']] || saved_status
          saved_progress = saved_node['progress'].to_i
          node_progress = node['progress'] || saved_progress

          if node_status < saved_status
            Astute.logger.warn("Attempt to assign lower status detected: "\
                               "Status was: #{saved_status}, attempted to "\
                               "assign: #{node_status}. Skipping this node (id=#{node['uid']})")
            return
          end
          if node_progress < saved_progress && node_status == saved_status
            Astute.logger.warn("Attempt to assign lesser progress detected: "\
                               "Progress was: #{saved_progress}, attempted to "\
                               "assign: #{node_progress}. Skipping this node (id=#{node['uid']})")
            return
          end

          # We need to update node here only if progress is greater, or status changed
          return if node.select{|k, v| saved_node[k] != v }.empty?
        end

        node
      end
      
      # Proportionally reduce the progress on the number of roles. For example 
      # node have 3 roles and already success deploy first role and now deploying 
      # second(50%). Overall progress of the operation for node is 
      # 50 / 3 + 1 * 100 / 3 = 49 
      # Based on the fact that each part makes the same contribution to the 
      # progress, we calculate it as 100/3 = 33% for every finished(success or 
      # fail) role
      def calculate_multiroles_node_progress(node)
        roles_of_nodes = @nodes.select { |n| n['uid'] == node['uid'] }
        all_roles = roles_of_nodes.size
        return if all_roles == 1 # calculation should only be done for multi roles
        
        finish_roles = roles_of_nodes.select { |n| ['ready', 'error'].include? n['status'] }.size
        return if finish_roles == all_roles # already done all work
        
        # recalculate progress for node
        node['progress'] = node['progress']/all_roles + 100 * finish_roles/all_roles
        
        # save final state if exist
        if ['ready', 'error'].include? node['status']
          roles_of_nodes.find { |n| n['role'] == node['role'] }['status'] = node['status']
        end

        if all_roles - finish_roles != 1
          # block 'ready' or 'error' status for node if not all roles deployed
          node['status'] = 'deploying'
        else
          node['status'] = roles_of_nodes.select{ |n| n['status'] == 'error' }.empty? ? 'ready' : 'error'
          node['progress'] = 100
        end
      end
      
    end

    class DLReleaseProxyReporter <DeploymentProxyReporter
      def initialize(up_reporter, amount)
        @amount = amount
        super(up_reporter)
      end

      def report(data)
        Astute.logger.debug("Data received by DLReleaseProxyReporter to report it up: #{data.inspect}")
        report_new_data(data)
      end

    private

      def calculate_overall_progress
        @nodes.inject(0) { |sum, node| sum + node['progress'].to_i } / @amount
      end

      def get_overall_status(data)
        status = data['status']
        error_nodes = @nodes.select {|n| n['status'] == 'error'}.map{|n| n['uid']}
        msg = data['error']
        err_msg = "Cannot download release on nodes #{error_nodes.inspect}" if error_nodes.any?
        if status == 'error'
          msg ||= err_msg
        elsif status ==  'ready' and err_msg
          msg = err_msg
          status = 'error'
        end
        progress = data['progress'] || calculate_overall_progress

        {'status' => status, 'error' => msg, 'progress' => progress}.reject{|k,v| v.nil?}
      end
    end
  end
end
