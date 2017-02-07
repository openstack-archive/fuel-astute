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

    ALLOWED_STATUSES = [:successful, :failed, :running, :pending, :skipped]
    attr_reader :task
    def initialize(task, context)
      # WARNING: this code expect that only one node will be send
      # on one hook.
      @task = task
      @status = :pending
      @ctx = context
      @time_start = Time.now.to_i
    end

    # Run current task on node, specified in task
    def run
      validation
      setup_default
      running!
      process
    rescue => e
      Astute.logger.warn("Fail to run task #{task['type']} #{task_name}" \
        " with error #{e.message} trace: #{e.format_backtrace}")
      failed!
    end

    # Polls the status of the task
    def status
      calculate_status unless finished?
      @status
    rescue => e
      Astute.logger.warn("Fail to detect status of the task #{task['type']}" \
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

    # Run current task on node, specified in task, using sync mode
    def sync_run
      run
      loop do
        sleep Astute.config.task_poll_delay
        status
        break if finished?
      end

      successful?
    end

    # Show additional info about tasks: last run summary, sdtout etc
    def summary
      {}
    end

    def finished?
      [:successful, :failed, :skipped].include? @status
    end

    def successful?
      @status == :successful
    end

    def pending?
      @status == :pending
    end

    def skipped?
      @status == :skipped
    end

    def running?
      @status == :running
    end

    def failed?
      @status == :failed
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
      ShellMClient.new(@ctx, node_uid).run_without_check(cmd, timeout)
    end

    # Create file with content on selected node
    # should use only for small file
    # In other case please use separate thread or
    # use upload file task.
    # Synchronous (blocking) call
    def upload_file(node_uid, mco_params)
      UploadFileMClient.new(@ctx, node_uid).upload_without_check(mco_params)
    end

    def failed!
      self.status = :failed
      time_summary
    end

    def running!
      self.status = :running
    end

    def succeed!
      self.status = :successful
      time_summary
    end

    def skipped!
      self.status = :skipped
      time_summary
    end

    def task_name
      task['id'] || task['diagnostic_name']
    end

    def time_summary
      amount_time = (Time.now.to_i - @time_start).to_i
      wasted_time = Time.at(amount_time).utc.strftime("%H:%M:%S")
      Astute.logger.debug("Task time summary: #{task_name} with status" \
        " #{@status.to_s} on node #{task['node_id']} took #{wasted_time}")
    end

  end
end
