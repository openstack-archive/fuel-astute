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

require 'digest/md5'

module Astute
  module ProxyReporter
    class TaskProxyReporter

      INTEGRATED_STATES = ['error', 'stopped']

      REPORT_REAL_TASK_STATE_MAP = {
        'running' => 'running',
        'successful' => 'ready',
        'failed' => 'error',
        'skipped' => 'skipped'
      }

      REPORT_REAL_NODE_MAP = {
        'virtual_sync_node' => nil
      }

      def initialize(up_reporter)
        @up_reporter = up_reporter
        @messages_cache = []
      end

      def report(original_data)
        return if duplicate?(original_data)

        data = original_data.deep_dup
        if data['nodes']
          nodes_to_report = get_nodes_to_report(data['nodes'])
          return if nodes_to_report.empty? # Let's report only if nodes updated

          data['nodes'] = nodes_to_report
        end

        @up_reporter.report(data)
      end

      private

      def get_nodes_to_report(nodes)
        nodes.map{ |node| node_validate(node) }.compact
      end

      def node_validate(original_node)
        node = deep_copy(original_node)
        return unless node_should_include?(node)
        convert_node_name_to_original(node)
        return node unless are_fields_valid?(node)
        convert_task_status_to_status(node)
        normalization_progress(node)
        return node
      end

      def are_fields_valid?(node)
        are_node_basic_fields_valid?(node) && are_task_basic_fields_valid?(node)
      end

      def node_should_include?(node)
        is_num?(node['uid']) ||
        ['master', 'virtual_sync_node'].include?(node['uid'])
      end

      def valid_task_status?(status)
        REPORT_REAL_TASK_STATE_MAP.keys.include? status.to_s
      end

      def integrated_status?(status)
        INTEGRATED_STATES.include? status.to_s
      end

      # Validate of basic fields in message about node
      def are_node_basic_fields_valid?(node)
        err = []
        err << "Node uid is not provided" unless node['uid']

        err.any? ? fail_validation(node, err) : true
      end

       # Validate of basic fields in message about task
      def are_task_basic_fields_valid?(node)
        err = []

        err << "Task status provided '#{node['task_status']}' is not supported" if
         !valid_task_status?(node['task_status'])
        err << "Task name is not provided" if node['deployment_graph_task_name'].blank?

        err.any? ? fail_validation(node, err) : true
      end


      def convert_task_status_to_status(node)
        node['task_status'] = REPORT_REAL_TASK_STATE_MAP.fetch(node['task_status'])
      end

      # Normalization of progress field: ensures that the scaling progress was
      # in range from 0 to 100 and has a value of 100 fot the integrated node
      # status
      def normalization_progress(node)
        if node['progress']
          node['progress'] = 100 if node['progress'] > 100
          node['progress'] = 0 if node['progress'] < 0
        else
          node['progress'] = 100 if integrated_status?(node['status'])
        end
      end

      def fail_validation(node, err)
        msg = "Validation of node:\n#{node.pretty_inspect} for " \
          "report failed: #{err.join('; ')}"
        Astute.logger.warn(msg)
        false
      end

      def convert_node_name_to_original(node)
        if REPORT_REAL_NODE_MAP.keys.include?(node['uid'])
          node['uid'] = REPORT_REAL_NODE_MAP.fetch(node['uid'])
        end
      end

      def is_num?(str)
        Integer(str)
      rescue ArgumentError, TypeError
        false
      end

      # Save message digest to protect server from
      # message flooding. Sure, because of Hash is complicated structure
      # which does not respect order and can be generate different strings
      # but we still catch most of possible duplicates.
      def duplicate?(data)
        msg_digest = Digest::MD5.hexdigest(data.to_s)
        return true if @messages_cache.include?(msg_digest)

        @messages_cache << msg_digest
        return false
      end

    end
  end
end