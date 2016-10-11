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

module Astute
  class PuppetJob

    FINAL_TASK_STATUSES = [
      'successful', 'failed'
    ]

    TASK_STATUSES = [
      'successful', 'failed', 'running'
    ]

    SUCCEED_STATUSES = [
      'succeed'
    ]

    BUSY_STATUSES = [
      'running'
    ]

    UNDEFINED_STATUSES = [
      'undefined'
    ]

    STOPED_STATUSES = [
      'stopped', 'disabled'
    ]

    FAILED_STATUSES = UNDEFINED_STATUSES + STOPED_STATUSES

    def initialize(task, puppet_mclient, options)
      @task = task
      @retries = options['retries']
      @fade_timeout = options['fade_timeout']
      @time_observer = TimeObserver.new(options['timeout'])
      @succeed_retries = options['succeed_retries']
      self.task_status = 'running'
      @puppet_mclient = puppet_mclient
    end

    # Run selected puppet manifest on node
    # @return [void]
    def run
      Astute.logger.info "Start puppet with timeout "\
        "#{@time_observer.time_limit} sec. #{task_details_for_log}"

      @time_observer.start
      self.task_status = puppetd_run
    end

    # Return actual status of puppet run
    # @return [String] Task status: successful, failed or running
    def status
      return @task_status if FINAL_TASK_STATUSES.include?(@task_status) && @retries < 1

      current_task_status = puppet_to_task_status(puppet_status)

      self.task_status = case current_task_status
        when 'successful'
          processing_succeed_task
        when 'running'
          processing_running_task
        when 'failed'
          processing_error_task
        end

      time_is_up! if should_stop?
      @task_status
    end

    # Return actual last run summary for puppet run
    # @return [Hash] Puppet summary
    def summary
      @puppet_mclient.summary
    end

    private

    # Should stop process or not: task is still running but we are out of time
    # @return [true, false]
    def should_stop?
      !FINAL_TASK_STATUSES.include?(@task_status) && !@time_observer.enough_time?
    end

    # Set task status to failed and reset retires counter to 0 to avoid
    # redundant retries
    # @return [void]
    def time_is_up!
      Astute.logger.error "Puppet agent took too long to run puppet task."\
                          " Mark task as failed. #{task_details_for_log}"
      self.task_status = 'failed'
      @retries = 0
    end

    # Setup task status
    # @param [String] status The task status
    # @return [void]
    # @raise [StandardError] Unknown status
    def task_status=(status)
      if TASK_STATUSES.include?(status)
        @task_status = status
      else
        raise "Unknow status: #{status}. Expected: #{TASK_STATUSES}"
      end
    end

    # Return actual status of puppet using mcollective puppet agent
    # @return [String]: puppet status
    def puppet_status
      actual_status = @puppet_mclient.status
      log_current_status(actual_status)

      if UNDEFINED_STATUSES.include?(actual_status)
        Astute.logger.warn "Error to get puppet status. "\
          "#{task_details_for_log}."
      end

      actual_status
    end

    # Run puppet manifest using mcollective puppet agent
    # @return [String] Task status: running or failed
    # TODO(vsharshov): need refactoring to make this be async call
    def puppetd_run
      fade_obsorver = TimeObserver.new(@fade_timeout)
      fade_obsorver.start

      while fade_obsorver.enough_time?
        is_running = @puppet_mclient.run
        return 'running' if is_running

        Astute.logger.debug "Could not run puppet process "\
          "#{task_details_for_log}. Waiting #{fade_obsorver.left_time} sec"
        sleep Astute.config.puppet_fade_interval
      end
      Astute.logger.error "Problem with puppet start. Time "\
        "(#{@fade_timeout} sec) is over. #{task_details_for_log}"
      'failed'
    end

    # Convert puppet status to task status
    # @param [String] puppet_status The puppet status of task
    # @return [String] Task status
    # @raise [StandardError] Unknown status
    def puppet_to_task_status(mco_puppet_status)
      case
      when SUCCEED_STATUSES.include?(mco_puppet_status)
        'successful'
      when BUSY_STATUSES.include?(mco_puppet_status)
        'running'
      when FAILED_STATUSES.include?(mco_puppet_status)
        'failed'
      else
        raise "Unknow status: #{mco_puppet_status}"
      end
    end

    # Return short useful info about node and puppet task
    # @return [String]
    def task_details_for_log
      "Node #{@puppet_mclient.node_id}, task #{@task}, manifest "\
      "#{@puppet_mclient.manifest}"
    end

    # Write to log with needed message level actual task status
    # @param [String] status Actual puppet status of task
    # @return [void]
    def log_current_status(status)
      message = "#{task_details_for_log}, status: #{status}"
      if FAILED_STATUSES.include?(status)
        Astute.logger.error message
      else
        Astute.logger.debug message
      end
    end

    # Process additional action in case of puppet succeed
    # @return [String] Task status: successful, failed or running
    def processing_succeed_task
      Astute.logger.debug "Puppet completed within #{@time_observer.stop}"\
        "seconds"
      if @succeed_retries > 0
        @succeed_retries -= 1
        Astute.logger.debug "Succeed puppet on node will be "\
          "restarted. #{@succeed_retries} retries remained. "\
          "#{task_details_for_log}"
        Astute.logger.info "Retrying to run puppet for following succeed "\
          "node: #{@puppet_mclient.node_id}"
        puppetd_run
      else
        Astute.logger.info "Node #{@puppet_mclient.node_id} has succeed "\
          "to deploy. There is no more retries for puppet run. "\
          "#{task_details_for_log}"
        'successful'
      end
    end

    # Process additional action in case of puppet failed
    # @return [String] Task status: successful, failed or running
    def processing_error_task
      if @retries > 0
        @retries -= 1
        Astute.logger.debug "Puppet on node will be "\
          "restarted because of fail. #{@retries} retries remained."\
          "#{task_details_for_log}"
        Astute.logger.info "Retrying to run puppet for following error "\
          "nodes: #{@puppet_mclient.node_id}"
        puppetd_run
      else
        Astute.logger.error "Node has failed to deploy. There is"\
          " no more retries for puppet run. #{task_details_for_log}"
        'failed'
      end
    end

    # Process additional action in case of puppet running
    # @return [String]: Task status: successful, failed or running
    def processing_running_task
      'running'
    end

  end #PuppetJob

end
