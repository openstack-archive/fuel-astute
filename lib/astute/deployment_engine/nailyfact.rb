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

require 'yaml'

class Astute::DeploymentEngine::NailyFact < Astute::DeploymentEngine

  def deploy_piece(nodes, retries=2, change_node_status=true)
    return false unless validate_nodes(nodes)

    @ctx.reporter.report(nodes_status(nodes, 'deploying', {'progress' => 0}))

    begin
      @ctx.deploy_log_parser.prepare(nodes)
    rescue => e
      Astute.logger.warn "Some error occurred when prepare LogParser: #{e.message}, trace: #{e.format_backtrace}"
    end

    nodes.each { |node| upload_facts(node) }
    Astute.logger.info "#{@ctx.task_id}: Required attrs/metadata passed via facts extension. Starting deployment."

    Astute::PuppetdDeployer.deploy(@ctx, nodes, retries, change_node_status)
    nodes_roles = nodes.map { |n| {n['uid'] => n['role']} }
    Astute.logger.info "#{@ctx.task_id}: Finished deployment of nodes => roles: #{nodes_roles.inspect}"
  end

  private

  def upload_facts(node)
    Astute.logger.info  "#{@ctx.task_id}: storing metadata for node uid=#{node['uid']}"
    Astute.logger.debug "#{@ctx.task_id}: stores metadata: #{node.to_yaml}"

    # This is synchronious RPC call, so we are sure that data were sent and processed remotely
    upload_mclient = Astute::MClient.new(@ctx, "uploadfile", [node['uid']])
    upload_mclient.upload(:path => '/etc/astute.yaml', :content => node.to_yaml, :overwrite => true, :parents => true)
  end

end
