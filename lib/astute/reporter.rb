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
      def initialize(up_reporter)
        @up_reporter = up_reporter
        @nodes = []
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
        msg = case status
              when 'ready'
                error_nodes = @nodes.select {|n| n['status'] == 'error'}
                if error_nodes.any?
                  status = 'error'
                  error_uids = error_nodes.map{|n| n['uid']}
                  "Some error occured on nodes #{error_uids.inspect}"
                else
                  data['error']
                end
              else
                data['error']
              end
        progress = data['progress']

        {'status' => status, 'error' => msg, 'progress' => progress}.reject{|k,v| v.nil?}
      end

      def get_nodes_to_report(nodes)
        nodes.compact.inject([]) { |result, node| n = node_validate(node) and result << n; result }
      end

      def update_saved_nodes(new_nodes)
        # Update nodes attributes in @nodes.
        new_nodes.each do |node|
          saved_node = @nodes.select {|x| x['uid'] == node['uid']}.first  # NOTE: use nodes hash
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
        else
          err << "progress value provided, but no status" if node['progress']
        end
        err << "Node uid is not provided" unless node['uid']
        if err.any?
          msg = "Validation of node: #{node.inspect} for report failed: #{err.join('; ')}."
          Astute.logger.error(msg)
          raise msg
        end

        # Validate progress field.
        if node['progress']
          if node['progress'] > 100
            Astute.logger.warn("Passed report for node with progress > 100: "\
                                "#{node.inspect}. Adjusting progress to 100.")
            node['progress'] = 100
          end
          if node['progress'] < 0
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

        # Comparison with previous state.
        saved_node = @nodes.select {|x| x['uid'] == node['uid']}.first
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
        error_nodes = @nodes.select {|n| n['status'] == 'error'}
        if error_nodes.any?
          error_uids = error_nodes.map{|n| n['uid']}
          msg = case status
                when 'error'
                  data['error'] || "Cannot download release on nodes #{error_uids.inspect}"
                when 'ready'
                  status = 'error'
                  "Cannot download release on nodes #{error_uids.inspect}"
                else
                  data['error']
                end
        else
          msg = data['error']
        end
        progress = data['progress'] || calculate_overall_progress

        {'status' => status, 'error' => msg, 'progress' => progress}.reject{|k,v| v.nil?}
      end
    end
  end
end
