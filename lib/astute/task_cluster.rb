#    Copyright 2016 Mirantis, Inc.
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
  class TaskCluster < Deployment::Cluster

    attr_reader :fault_tolerance_groups

    def hook_post_node_poll(*args)
      super
      validate_fault_tolerance(args[0])
    end

    def hook_post_gracefully_stop(*args)
      report_new_node_status(args[0])
    end

    def report_new_node_status(node)
      node.report_node_status
    end

    def fault_tolerance_groups=(groups=[])
      @fault_tolerance_groups = groups.select { |group| group['node_ids'].present? }
    end

    private

    def validate_fault_tolerance(node)
      if node.failed? && !node.skipped?
        count_tolerance_fail(node)
        gracefully_stop! if fault_tolerance_excess?
      end
    end

    def count_tolerance_fail(node)
      @fault_tolerance_groups.each do |group|
        group['fault_tolerance'] -= 1 if group['node_ids'].include?(node.name)
      end
    end

    def fault_tolerance_excess?
      @fault_tolerance_groups.any? { |group| group['fault_tolerance'] < 0 }
    end

  end
end
