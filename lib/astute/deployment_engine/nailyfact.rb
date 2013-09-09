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

require 'json'

class Astute::DeploymentEngine::NailyFact < Astute::DeploymentEngine

  # Just merge attributes of concrete node
  # with attributes of cluster
  def create_facts(node_attrs)
    facts = deep_copy(node_attrs)

    facts.each do |k, v|
      facts[k] = v.to_json if v.is_a?(Hash) || v.is_a?(Array)
    end

    facts
  end

  def deploy_piece(nodes, retries=2, change_node_status=true)
    return false unless validate_nodes(nodes)

    nodes_to_deploy = get_nodes_to_deploy(nodes)
    if nodes_to_deploy.empty?
      Astute.logger.info "#{@ctx.task_id}: Returning from deployment stage. No nodes to deploy"
      return
    end

    Astute.logger.info "#{@ctx.task_id}: Calculation of required attributes to pass, include netw.settings"
    @ctx.reporter.report(nodes_status(nodes_to_deploy, 'deploying', {'progress' => 0}))

    begin
      @ctx.deploy_log_parser.prepare(nodes_group)
    rescue Exception => e
      Astute.logger.warn "Some error occurred when prepare LogParser: #{e.message}, trace: #{e.format_backtrace}"
    end
    
    nodes_to_deploy.each { |node| Astute::Metadata.publish_facts @ctx, node['uid'], create_facts(node) }
    Astute.logger.info "#{@ctx.task_id}: Required attrs/metadata passed via facts extension. Starting deployment."

    Astute::PuppetdDeployer.deploy(@ctx, nodes_to_deploy, retries, change_node_status)
    
    nodes_roles = nodes_to_deploy.map { |n| {n['uid'] => n['role']} }
    Astute.logger.info "#{@ctx.task_id}: Finished deployment of nodes => roles: #{nodes_roles.inspect}"
  end

  private
  def get_nodes_to_deploy(nodes)
    Astute.logger.info "#{@ctx.task_id}: Getting which nodes to deploy"
    nodes_to_deploy = []
    nodes.each do |node|
      if node['status'] != 'ready'
        nodes_to_deploy << node
      else
        Astute.logger.info "#{@ctx.task_id}: Not adding node #{node['uid']} with hostname #{node['name']} as it does not require deploying."
      end
    end

    nodes_to_deploy
  end

end
