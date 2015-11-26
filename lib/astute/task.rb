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

module Astute
  class Task

    ALLOWED_STATUSES = [:successful, :failed, :running, :pending]

    def initialize(task, context)
      # WARNING: this code expect that only one node will be send
      # on one hook.
      @task = task
      @status = :pending
      @ctx = context
    end

    # Run current task on node, specified in task
    def run
      validation
      setup_default
      running!
      process
    rescue => e
      Astute.logger.warn("Fail to run task #{@task['type']} #{task_name}" \
        " with error #{e.message} trace: #{e.format_backtrace}")
      failed!
    end

    # Polls the status of the task
    def status
      calculate_status unless finished?
      @status
    rescue => e
      Astute.logger.warn("Fail to detect status of the task #{@task['type']}" \
        " #{task_name} with error #{e.message} trace: #{e.format_backtrace}")
      failed!
    end

    def status=(value)
      value = value.to_sym
      unless ALLOWED_STATUSES.include?(value)
        raise AstuteError::InvalidArgument,
              "#{self}: Invalid task status: #{value}"
      end
      @status = value
    end

    private

    # Run current task on node, specified in task
    # should be fast and async and do not raise exceptions
    # @abstract Should be implemented in a subclass
    def process
      raise NotImplementedError
    end

    # Polls the status of the task
    # should update the task status and do not raise exceptions
    # @abstract Should be implemented in a subclass
    def calculate_status
      raise NotImplementedError
    end

    def validate_presence(data, key)
      raise TaskValidationError,
            "Missing a required parameter #{key}" unless data[key].present?
    end

    # Pre validation of the task
    # should check task and raise error if something went wrong
    # @raise [TaskValidationError] if the object is not a task or has missing fields
    def validation

    end

    # Setup default value for hook
    # should not raise any exception
    def setup_default

    end

    # Run short shell commands
    # should use only in case of short run command
    # In other case please use shell task
    # Synchronous (blocking) call
    def run_shell_without_check(node_uid, cmd, timeout=2)
      shell = MClient.new(
        @ctx,
        'execute_shell_command',
        Array(node_uid),
        check_result=false,
        timeout=timeout
      )
      result = shell.execute(:cmd => cmd).first
      Astute.logger.debug(
        "#{@ctx.task_id}: cmd: #{cmd}\n" \
        "stdout: #{result.results[:data][:stdout]}\n" \
        "stderr: #{result.results[:data][:stderr]}\n" \
        "exit code: #{result.results[:data][:exit_code]}")
      {
        :stdout =>result.results[:data][:stdout].chomp,
        :stderr => result.results[:data][:stderr].chomp,
        :exit_code => result.results[:data][:exit_code]
      }
    end


    # Create file with content on selected node
    # should use only for small file
    # In other case please use separate thread or
    # use upload file task.
    # Synchronous (blocking) call
    def upload_file(node_uid, mco_params={})
      upload_mclient = Astute::MClient.new(
        @ctx,
        "uploadfile",
        Array(node_uid)
      )

      mco_params['overwrite'] = true if mco_params['overwrite'].nil?
      mco_params['parents'] = true if mco_params['parents'].nil?
      mco_params['permissions'] ||= '0644'
      mco_params['user_owner']  ||= 'root'
      mco_params['group_owner'] ||= 'root'
      mco_params['dir_permissions'] ||= '0755'

      upload_mclient.upload(
        :path => mco_params['path'],
        :content => mco_params['content'],
        :overwrite => mco_params['overwrite'],
        :parents => mco_params['parents'],
        :permissions => mco_params['permissions'],
        :user_owner => mco_params['user_owner'],
        :group_owner => mco_params['group_owner'],
        :dir_permissions => mco_params['dir_permissions']
      )

      true
    rescue MClientTimeout, MClientError => e
      Astute.logger.error("#{@ctx.task_id}: mcollective upload_file "\
                          "agent error: #{e.message}")
      false
    end

    def finished?
      [:successful, :failed].include? @status
    end

    def failed!
      self.status = :failed
    end

    def failed?
      @status == :failed
    end

    def running!
      self.status = :running
    end

    def running?
      @status == :running
    end

    def succeed!
      self.status = :successful
    end

    def successful?
      @status == :successful
    end

    def pending?
      @status == :pending
    end

    def task_name
      @task['id'] || @task['diagnostic_name']
    end

  end
end