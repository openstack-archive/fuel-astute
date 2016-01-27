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
    attr_accessor :gracefully_stop_mark

    def stop_condition(&block)
      self.gracefully_stop_mark = block
    end

    def hook_post_node_poll(*args)
      gracefully_stop(args[0])
    end

    # Check if the deployment process should stop
    # @return [true, false]
    def gracefully_stop?
      gracefully_stop_mark ? gracefully_stop_mark.call : false
    end

    def gracefully_stop(node)
      if gracefully_stop? && node.ready?
        node.set_status_skipped
        node.report_node_status
      end
    end

  end
end