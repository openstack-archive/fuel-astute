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

module Astute
  class PuppetTask

    FINAL_TASK_STATUSES = [
      'successful', 'failed'
    ]

    TASK_STATUSES = [
      'successful', 'failed', 'running'
    ]

    PUPPET_STATUSES = [
      'running', 'stopped', 'disabled'
    ]

    ALLOWING_STATUSES_TO_RUN = [
      'stopped'
    ]

    BUSY_STATUSES = [
      'running'
    ]

    STOPPED_STATUSES = [
      'stopped', 'disabled'
    ]

    def initialize(ctx, node, options={})
      default_options = {
        :retries => Astute.config.puppet_retries,
        :puppet_manifest =>  '/etc/puppet/manifests/site.pp',
        :puppet_modules => Astute.config.puppet_module_path,
        :cwd => Astute.config.shell_cwd,
        :timeout => Astute.config.puppet_timeout,
        :puppet_debug => false,
        :succeed_retries => Astute.config.puppet_succeed_retries,
        :raw_report => Astute.config.puppet_raw_report,
        :puppet_noop_run => Astute.config.puppet_noop_run,
      }
      @options = options.compact.reverse_merge(default_options)
      @options.freeze

      @ctx = ctx
      @node = node
      @retries = @options[:retries]
      @time_observer = TimeObserver.new(@options[:timeout])
      @succeed_retries = @options[:succeed_retries]
      @summary = {}
      self.task_status = 'running'
    end

    # Run selected puppet manifest on node
    # @return [void]
    def run
      Astute.logger.info "Start puppet with timeout #{@time_observer.time_limit}"\
                         " sec. #{task_details_for_log}"
      Astute.logger.debug "Puppet task options: #{@options.pretty_inspect}"

      @time_observer.start
      self.task_status = puppetd_runonce
    end

    # Return actual status of puppet run
    # @return [String] Task status: successful, failed or running
    def status
      return @task_status if FINAL_TASK_STATUSES.include?(@task_status) &&
                             @retries < 1

      unless @time_observer.enough_time?
        Astute.logger.error "Puppet agent took too long to run puppet task. "\
                            "Mark task as error. #{task_details_for_log}"
        self.task_status = 'failed'
        @retries = 0
        return @task_status
      end

      current_status, summary = puppet_status
      log_current_status(current_status)

      self.task_status = case puppet_to_task_status(current_status, summary)
        when 'successful'
          processing_succeed_task
        when 'running'
          processing_running_task
        when 'failed'
          processing_error_task
        end
    end

    # Return actual last run summary for puppet run
    # @return [Hash] Puppet summary
    def summary
      @summary
    end

    private

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
    # @return [String, Hash]: Puppet status (check PUPPET_STATUSES), summary
    def puppet_status
      @summary = puppet_last_run_summary
      validate_status(@summary[:status])
      return @summary[:status], @summary
    rescue MClientError, MClientTimeout => e
      Astute.logger.warn "Error to get puppet status. #{task_details_for_log}."\
                         "Reason: #{e.message}"
      @summary = {}
      return 'error', {}
    end

    # Validate puppet status
    # @param [String] status The puppet status
    # @return [void]
    # @raise [StandardError] Unknown status
    def validate_status(status)
      unless PUPPET_STATUSES.include?(status)
        raise MClientError, "Unknow status #{status} from mcollective agent"
      end
    end

    # Detect succeed of puppet task using summary
    # @param [Hash] summary The puppet summary
    # @return [true, false]
    def succeed?(summary)
      return false if summary.blank?

      summary[:status] == 'stopped' &&
      summary[:resources]['failed'].to_i == 0 &&
      summary[:resources]['failed_to_restart'].to_i == 0
    end

    # Run puppet manifest using mcollective puppet agent
    # @return [String] Task status: running or failed
    def puppetd_runonce
      if allow_to_start?
        puppet_run
        'running'
      else
        Astute.logger.error "Unable to start puppet, because it is busy "\
                            "by other task. #{task_details_for_log}"
        'failed'
      end
    rescue MClientError, MClientTimeout => e
      Astute.logger.error "Problem with puppet start. #{task_details_for_log}"\
                         " Reason: #{e.message}"
      'failed'
    end

    # Clarifiy ability to run puppet on node
    # @return [true, false] Task status
    # TODO(vsharshov): Prepare to support async call
    def allow_to_start?
      fade_timeout = TimeObserver.new(Astute.config.puppet_fade_timeout)
      fade_timeout.start

      while fade_timeout.enough_time?
        current_status, _summary = puppet_status
        break if STOPPED_STATUSES.include?(current_status)

        Astute.logger.debug "Detecting unexpected puppet process "\
          "#{task_details_for_log}. Waiting #{fade_timeout.left_time} sec"
        sleep Astute.config.puppet_fade_interval
      end

      ALLOWING_STATUSES_TO_RUN.include?(current_status)
    end

    # Convert puppet status to task status
    # @param [String] puppet_status The puppet status of task
    # @param [Hash] summary Optional last run summary from mco puppet agent
    # @return [String] Task status
    # @raise [StandardError] Unknown status
    def puppet_to_task_status(mco_puppet_status, summary={})
      case
      when succeed?(summary)
        'successful'
      when BUSY_STATUSES.include?(mco_puppet_status)
        'running'
      when STOPPED_STATUSES.include?(mco_puppet_status)
        'failed'
      else
        raise "Unknow status: #{mco_puppet_status}. Summary #{summary}"
      end
    end

    # Return short useful info about node and puppet task
    # @return [String]
    def task_details_for_log
      "Node #{@node['uid']}, task #{@node['task']}, manifest: "\
      "#{@options[:cwd].chomp('/') + '/' + @options[:puppet_manifest]}"
    end

    # Write to log with needed message level actual task status
    # @param [String] status Actual puppet status of task
    # @return [void]
    def log_current_status(status)
      message = "#{task_details_for_log}, status: #{status}"
      if status == 'error'
        Astute.logger.error message
      else
        Astute.logger.debug message
      end
    end

    # Process additional action in case of puppet succeed
    # @return [String] Task status: successful, failed or running
    def processing_succeed_task
      Astute.logger.debug "Puppet completed within #{@time_observer.stop} seconds"
      if @succeed_retries > 0
        @succeed_retries -= 1
        Astute.logger.debug "Succeed puppet on node will be "\
          "restarted. #{@succeed_retries} retries remained. "\
          "#{task_details_for_log}"
        Astute.logger.info "Retrying to run puppet for following succeed "\
          "node: #{@node['uid']}"
        puppetd_runonce
      else
        Astute.logger.info "Node #{@node['uid']} has succeed to deploy. "\
          "There is no more retries for puppet run. #{task_details_for_log}"
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
          "nodes: #{@node['uid']}"
        puppetd_runonce
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

    # Create configured mcollective agent
    # @return [Astute::MClient]
    def puppetd
      puppetd = MClient.new(
        @ctx,
        "puppetd",
        [@node['uid']],
        _check_result=true,
        _timeout=nil,
        _retries=1,
        _enable_result_logging=false
      )
      puppetd.on_respond_timeout do |uids|
        Astute.logger.error "Nodes #{uids} reached the response timeout"
        raise MClientTimeout
      end
      puppetd
    end

    # Run last_run_summary action using mcollective puppet agent
    # @return [Hash] return hash with status and resources
    # @raise [MClientTimeout, MClientError]
    def puppet_last_run_summary
      puppetd.last_run_summary(
        :puppet_noop_run => @options[:puppet_noop_run],
        :raw_report => @options[:raw_report]
      ).first[:data]
    end

    # Run runonce action using mcollective puppet agent
    # @return [void]
    # @raise [MClientTimeout, MClientError]
    def puppet_run
      puppetd.runonce(
        :puppet_debug => @options[:puppet_debug],
        :manifest => @options[:puppet_manifest],
        :modules  => @options[:puppet_modules],
        :cwd => @options[:cwd],
        :puppet_noop_run => @options[:puppet_noop_run],
      )
    end

  end #PuppetTask
end
