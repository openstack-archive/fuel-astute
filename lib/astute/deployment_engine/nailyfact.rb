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

class Astute::DeploymentEngine::NailyFact < Astute::DeploymentEngine

  def deploy_piece(nodes, retries=1)
    return false unless validate_nodes(nodes)

    @ctx.reporter.report(nodes_status(nodes, 'deploying', {'progress' => 0}))

    begin
      @ctx.deploy_log_parser.prepare(nodes)
    rescue => e
      Astute.logger.warn "Some error occurred when prepare LogParser: #{e.message}, trace: #{e.format_backtrace}"
    end

    Astute.logger.info "#{@ctx.task_id}: Starting deployment"

    Astute::PuppetdDeployer.deploy(@ctx, nodes, retries)
    nodes_roles = nodes.map { |n| {n['uid'] => n['role']} }
    Astute.logger.info "#{@ctx.task_id}: Finished deployment of nodes => roles: #{nodes_roles.inspect}"
  end

  def pre_deployment_actions(deployment_info, pre_deployment)
    PreDeploymentActions.new(deployment_info, @ctx).process
    NailgunHooks.new(pre_deployment, @ctx).process
  end

  def pre_node_actions(part)
    @action ||= PreNodeActions.new(@ctx)
    @action.process(part)
  end

  def pre_deploy_actions(part)
    PreDeployActions.new(part, @ctx).process
  end

  def post_deploy_actions(part)
    PostDeployActions.new(part, @ctx).process
  end

  def post_deployment_actions(deployment_info, post_deployment)
    begin
      NailgunHooks.new(post_deployment, @ctx).process
    rescue => e
      # We should fail all nodes in case of post deployment
      # process. In other case they will not sending back
      # for redeploy
      nodes = deployment_info.uniq {|n| n['uid']}.map do |node|
        { 'uid' => node['uid'],
          'status' => 'error',
          'role' => 'hook',
          'error_type' => 'deploy',
        }
      end
      @ctx.report_and_update_status('nodes' => nodes)
      raise e
    end

    PostDeploymentActions.new(deployment_info, @ctx).process
  end

end
