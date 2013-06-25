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


class Astute::DeploymentEngine::SimplePuppet < Astute::DeploymentEngine
  # It is trivial puppet run. It's assumed that user has prepared site.pp
  #   with all required parameters for modules
  def deploy_piece(nodes, attrs, retries=2, change_node_status=true)
    return false unless validate_nodes(nodes)
    @ctx.reporter.report nodes_status(nodes, 'deploying', {'progress' => 0})
    Astute::PuppetdDeployer.deploy(@ctx, nodes, retries, change_node_status)
    nodes_roles = nodes.map { |n| { n['uid'] => n['role'] } }
    Astute.logger.info "#{@ctx.task_id}: Finished deployment of nodes => roles: #{nodes_roles.inspect}"
  end
end
