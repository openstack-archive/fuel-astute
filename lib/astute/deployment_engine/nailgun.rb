#    Copyright 2014 Mirantis, Inc.
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

class Astute::DeploymentEngine::Nailgun < Astute::DeploymentEngine

  def deploy_piece(nodes, retries=1)
    return false unless validate_nodes(nodes)

    @ctx.reporter.report(nodes_status(nodes, 'deploying', {'progress' => 0}))

    begin
      @ctx.deploy_log_parser.prepare(nodes)
    rescue => e
      Astute.logger.warn "Some error occurred when prepare LogParser: " \
        "#{e.message}, trace: #{e.format_backtrace}"
    end

    Astute.logger.info "#{@ctx.task_id}: Starting deployment"

    begin
      raw_tasks = nodes.map{ |n| n['tasks'] }.flatten

      # Group tasks by priorites
      tasks = []
      raw_tasks.group_by{|x| x['priority']}.values.each do |group_task|
        if group_task.size < 2
          tasks << group_task.first
          next
        end

        # TODO: need update for PuppetD to support uniq parameters
        task = group_task.shift
        task['uids'] += group_task.inject([]) { |sum, t| sum += t['uids'] }
        tasks << task
      end
      # TODO: need to update NailgunHooks to report status for role
      Astute::NailgunHooks.new(tasks.compact, @ctx).process
      report_nodes = nodes.uniq{ |n| n['uid'] }.map do |node|
        { 'uid' => node['uid'],
          'status' => 'ready',
          'role' => node['role'],
          'progress' => 100
        }
      end

      @ctx.report_and_update_status('nodes' => report_nodes)
    rescue => e
      # We should fail all nodes in case of post deployment
      # process. In other case they will not sending back
      # for redeploy
      report_nodes = nodes.uniq{ |n| n['uid'] }.map do |node|
        { 'uid' => node['uid'],
          'status' => 'error',
          'role' => 'hook',
          'error_type' => 'deploy'
        }
      end

      @ctx.report_and_update_status('nodes' => report_nodes)
      raise e
    end

    nodes_roles = nodes.map { |n| {n['uid'] => n['role']} }
    Astute.logger.info "#{@ctx.task_id}: Finished deployment of nodes" \
      " => roles: #{nodes_roles.inspect}"
  end

end