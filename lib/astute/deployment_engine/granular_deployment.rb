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

class Astute::DeploymentEngine::GranularDeployment < Astute::DeploymentEngine

  NAILGUN_STATUS = ['ready', 'error', 'deploying']

  def deploy_piece(nodes, retries=1)
    report_ready_for_nodes_without_tasks(nodes)
    nodes = filter_nodes_with_tasks(nodes)
    return false unless validate_nodes(nodes)

    @ctx.reporter.report(nodes_status(nodes, 'deploying', {'progress' => 0}))
    log_preparation(nodes)

    Astute.logger.info "#{@ctx.task_id}: Starting deployment"

    @running_tasks = {}
    @nodes_roles = nodes.inject({}) { |h, n| h.merge({n['uid'] => n['role']}) }
    @nodes_by_uid = nodes.inject({}) { |h, n| h.merge({ n['uid'] => n }) }
    @puppet_debug = nodes.first.fetch('puppet_debug', true)

    begin
      @task_manager = Astute::TaskManager.new(nodes)
      @hook_context = Astute::Context.new(
        @ctx.task_id,
        HookReporter.new,
        Astute::LogParser::NoParsing.new
      )
      deploy_nodes(nodes)
    rescue => e
      # We should fail all nodes in case of post deployment
      # process. In other case they will not sending back
      # for redeploy
      report_nodes = nodes.uniq{ |n| n['uid'] }.map do |node|
        { 'uid' => node['uid'],
          'status' => 'error',
          'role' => node['role'],
          'error_type' => 'deploy'
        }
      end

      @ctx.report_and_update_status('nodes' => report_nodes)
      raise e
    end

    Astute.logger.info "#{@ctx.task_id}: Finished deployment of nodes" \
      " => roles: #{@nodes_roles.inspect}"
  end

  def puppet_task(node_id, task)
    # Use fake reporter because of logic. We need to handle report here
    Astute::PuppetTask.new(
      @hook_context,
      @nodes_by_uid[node_id], # Use single node uid instead of task['uids']
      retries=task['parameters']['retries'] || Astute.config.puppet_retries,
      task['parameters']['puppet_manifest'],
      task['parameters']['puppet_modules'],
      task['parameters']['cwd'],
      task['parameters']['timeout'],
      @puppet_debug
    )
  end

  def run_task(node_id, task)
    Astute.logger.info "#{@ctx.task_id}: run task '#{task.to_yaml}' on node #{node_id}"
    @running_tasks[node_id] = puppet_task(node_id, task)
    @running_tasks[node_id].run
  end

  def check_status(node_id)
    status = @running_tasks[node_id].status
    if NAILGUN_STATUS.include? status
      status
    else
      raise "Internal error. Unknown status '#{status}'"
    end
  end

  def deploy_nodes(nodes)
    @task_manager.node_uids.each { |n| task = @task_manager.next_task(n) and run_task(n, task) }

    while @task_manager.task_in_queue?
      nodes_to_report = []
      sleep Astute.config.puppet_deploy_interval
      @task_manager.node_uids.each do |node_id|
        if task = @task_manager.current_task(node_id)
          case status = check_status(node_id)
          when 'ready'
            Astute.logger.info "Task '#{task}' on node uid=#{node_id} ended successfully"
            new_task = @task_manager.next_task(node_id)
            if new_task
              run_task(node_id, new_task)
            else
              nodes_to_report << process_success_node(node_id, task)
            end
          when 'deploying'
            progress_report = process_running_node(node_id, task, nodes)
            nodes_to_report << progress_report if progress_report
          when 'error'
            Astute.logger.error "Task '#{task}' failed on node #{node_id}"
            nodes_to_report << process_fail_node(node_id, task)
          else
            raise "Internal error. Known status '#{status}', but handler not provided"
          end
        else
          Astute.logger.debug "No more tasks provided for node #{node_id}"
        end
      end

      @ctx.report_and_update_status('nodes' => nodes_to_report) if nodes_to_report.present?

      break unless @task_manager.task_in_queue?
    end
  end

  def process_success_node(node_id, task)
    Astute.logger.info "No more tasks provided for node #{node_id}. All node " \
      "tasks completed successfully"
    {
      "uid" => node_id,
      'status' => 'ready',
      'role' => @nodes_roles[node_id],
      "progress" => 100,
      'task' => task
    }
  end

  def process_fail_node(node_id, task)
    Astute.logger.error "No more tasks will be executed on the node #{node_id}"
    @task_manager.delete_node(node_id)
    {
      'uid' => node_id,
      'status' => 'error',
      'error_type' => 'deploy',
      'role' => @nodes_roles[node_id],
      'task' => task
    }
  end

  def process_running_node(node_id, task, nodes)
    Astute.logger.debug "Task '#{task}' on node uid=#{node_id} deploying"
    begin
      # Pass nodes because logs calculation needs IP address of node, not just uid
      nodes_progress = @ctx.deploy_log_parser.progress_calculate(Array(node_id), nodes)
      if nodes_progress.present?
        nodes_progress.map! { |x| x.merge!(
          'status' => 'deploying',
          'role' => @nodes_roles[x['uid']],
          'task' => task
        ) }
        nodes_progress.first
      else
        nil
      end
    rescue => e
      Astute.logger.warn "Some error occurred when parse logs for nodes progress: #{e.message}, "\
                         "trace: #{e.format_backtrace}"
      nil
    end
  end

  def log_preparation(nodes)
    @ctx.deploy_log_parser.prepare(nodes)
  rescue => e
    Astute.logger.warn "Some error occurred when prepare LogParser: " \
      "#{e.message}, trace: #{e.format_backtrace}"
  end

  # If node doesn't have tasks, it means that node
  # is ready, because it doesn't require deployment
  def report_ready_for_nodes_without_tasks(nodes)
    nodes_without_tasks = filter_nodes_without_tasks(nodes)
    @ctx.reporter.report(nodes_status(nodes_without_tasks, 'ready', {'progress' => 100}))
  end

  def filter_nodes_with_tasks(nodes)
    nodes.select { |n| node_with_tasks?(n) }
  end

  def filter_nodes_without_tasks(nodes)
    nodes.select { |n| !node_with_tasks?(n) }
  end

  def node_with_tasks?(node)
    node['tasks'].present?
  end

  # Pre/post hooks
  def pre_deployment_actions(deployment_info, pre_deployment)
    Astute::GranularPreDeploymentActions.new(deployment_info, @ctx).process
    Astute::NailgunHooks.new(pre_deployment, @ctx).process
  end

  def pre_node_actions(part)
    @action ||= Astute::GranularPreNodeActions.new(@ctx)
    @action.process(part)
  end

  def pre_deploy_actions(part)
    Astute::GranularPreDeployActions.new(part, @ctx).process
  end

  def post_deploy_actions(part)
    Astute::GranularPostDeployActions.new(part, @ctx).process
  end

  def post_deployment_actions(deployment_info, post_deployment)
    begin
      Astute::NailgunHooks.new(post_deployment, @ctx).process
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
  end

  class HookReporter
    def report(msg)
      Astute.logger.debug msg
    end
  end

end
