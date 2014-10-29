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

class Astute::DeploymentEngine::Tasklib < Astute::DeploymentEngine

  TASKLIB_STATUS = {
    0 => :ended_successfully,
    1 => :running,
    2 => :valid_but_failed,
    3 => :unexpected_error,
    4 => :not_found_such_task
  }

  def deploy_piece(nodes, retries=1)
    return false unless validate_nodes(nodes)

    tasklib_deploy(nodes, retries)

    nodes_roles = nodes.map { |n| {n['uid'] => n['role']} }
    Astute.logger.info "#{@ctx.task_id}: Finished deployment of nodes => roles: #{nodes_roles.inspect}"
  end

  private

  def pre_tasklib_deploy
    @time_before = Time.now.to_i

    @ctx.reporter.report(nodes_status(@nodes, 'deploying', {'progress' => 0}))

    begin
      @ctx.deploy_log_parser.prepare(@nodes)
    rescue => e
      Astute.logger.warn "Some error occurred when prepare LogParser: #{e.message}, trace: #{e.format_backtrace}"
    end
  end

  def tasklib_deploy(nodes, retries=2)
    @nodes = nodes
    @nodes_roles = nodes.inject({}) { |h, n| h.merge({n['uid'] => n['role']}) }
    @task_manager = TaskManager.new(nodes)
    @debug = nodes.first['debug']

    Timeout::timeout(Astute.config.PUPPET_TIMEOUT) do
      pre_tasklib_deploy

      deploy_nodes

      post_tasklib_deploy
    end
  end

  def post_tasklib_deploy
    time_spent = (Time.now.to_i - @time_before) / 60.to_f
    Astute.logger.info "#{@ctx.task_id}: Spent #{time_spent.round(1)} minutes on tasklib run " \
                         "for following nodes(uids): #{@nodes.map {|n| n['uid']}.join(',')}"
  end

  def tasklib_mclient(node_ids)
    shell = Astute::MClient.new(
      @ctx,
      'execute_shell_command',
      Array(node_ids),
      check_result=true,
      timeout=timeout,
      retries=1
    )

    shell.on_respond_timeout do |uids|
      nodes = uids.map do |uid|
        { 'uid' => uid,
          'status' => 'error',
          'error_type' => 'deploy',
          'role' => @nodes_roles[uid],
          'task' => @task_manager.current_task(uid)
        }
      end
      @ctx.report_and_update_status('nodes' => nodes)
      @task_manager.delete(uid)
    end
    shell
  end

  def run_task(node_id, task)
    Astute.logger.info "#{@ctx.task_id}: run task '#{task}' on node #{node_id}"
    debug_option = @debug ? "--debug" : ""
    cmd = "taskcmd #{debug_option} daemon #{task}"
    tasklib_mclient(node_id).execute(:cmd => cmd).first
  end

  def check_status(node_id, task)
    cmd = "taskcmd status #{task}"
    response = tasklib_mclient(node_id).execute(:cmd => cmd).first
    status = response[:data][:exit_code].to_i
    if TASKLIB_STATUS.keys.include? status
      TASKLIB_STATUS[status]
    else
      raise "Internal error. Unknown status '#{status}'"
    end
  end

  def deploy_nodes
    @task_manager.node_uids.each { |n| task = @task_manager.next_task(n) and run_task(n, task) }

    while @task_manager.task_in_queue?
      nodes_to_report = []
      @task_manager.node_uids.each do |node_id|
        if task = @task_manager.current_task(node_id)
          case status = check_status(node_id, task)
          when :ended_successfully
            Astute.logger.info "Task '#{task}' on node uid=#{node_id} ended successfully"
            new_task = @task_manager.next_task(node_id)
            if new_task
              run_task(node_id, new_task)
            else
              Astute.logger.info "No more tasks provided for node #{node_id}. All node " \
                "tasks completed successfully"
              nodes_to_report << {
                "uid" => node_id,
                'status' => 'ready',
                'role' => @nodes_roles[node_id],
                "progress" => 100,
                'task' => task
              }
            end
          when :running
            progress_report = process_running_node(node_id, task)
            nodes_to_report << progress_report if progress_report
          when :valid_but_failed
            Astute.logger.error "Task '#{task}' on node #{node_id} valid, but failed"
            nodes_to_report << process_fail_node(node_id, task)
          when :unexpected_error
            Astute.logger.error "Task '#{task}' on node #{node_id} finished with an unexpected error"
            nodes_to_report << process_fail_node(node_id, task)
          when :not_found_such_task
            Astute.logger.error "Task '#{task}' on node #{node_id} not found"
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
      sleep Astute.config.PUPPET_DEPLOY_INTERVAL
    end
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

  def process_running_node(node_id, task)
    begin
      # Pass nodes because logs calculation needs IP address of node, not just uid
      nodes_progress = @ctx.deploy_log_parser.progress_calculate(Array(node_id), @nodes)
      if nodes_progress.present?
        nodes_progress.map! { |x| x.merge!(
          'status' => 'deploying',
          'role' => @nodes_roles[x['uid']],
          'task' => task
        ) }
      end
    rescue => e
      Astute.logger.warn "Some error occurred when parse logs for nodes progress: #{e.message}, "\
                         "trace: #{e.format_backtrace}"
      nil
    end
    nodes_progress.first
  end

end # class

class TaskManager
  def initialize(nodes)
    @tasks = nodes.inject({}) { |h, n| h.merge({n['uid'] => n['tasks'].map{ |t| t['name'] }.each}) }
    @current_task = {}
    Astute.logger.info "The following tasks will be performed on nodes: " \
      "#{@tasks.map {|k, v| {k => v.to_a}}.to_yaml}"
  end

  def current_task(node_id)
    @current_task[node_id]
  end

  def next_task(node_id)
    @current_task[node_id] = @tasks[node_id].next
  rescue StopIteration
    @current_task[node_id] = nil
    delete_node(node_id)
  end

  def delete_node(node_id)
    @tasks[node_id] = nil
  end

  def task_in_queue?
    @tasks.select{ |_k,v| v }.present?
  end

  def node_uids
    @tasks.select{ |_k,v| v }.keys
  end
end
