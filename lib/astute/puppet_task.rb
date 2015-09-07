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

require 'timeout'

module Astute

  class PuppetTask

    def initialize(ctx, node, retries=1, puppet_manifest=nil, puppet_modules=nil, cwd=nil, timeout=nil, puppet_debug=false)
      @ctx = ctx
      @node = node
      @retries = retries
      @puppet_manifest = puppet_manifest || '/etc/puppet/manifests/site.pp'
      @puppet_modules = puppet_modules || '/etc/puppet/modules'
      @cwd = cwd || '/'
      @time_observer = TimeObserver.new(timeout || Astute.config.puppet_timeout)
      @prev_summary = nil
      @is_hung = false
      @puppet_debug = puppet_debug
    end

    def run
      Astute.logger.debug "Waiting for puppet to finish deployment on " \
        "node #{@node['uid']} (timeout = #{@time_observer.time_limit} sec)..."
      @time_observer.start
      @prev_summary ||= puppet_status
      puppetd_runonce
    end

    # expect to run this method with respect of Astute.config.puppet_fade_interval
    def status
      raise Timeout::Error unless @time_observer.enough_time?

      last_run = puppet_status
      status = node_status(last_run)
      Astute.logger.debug "Node #{@node['uid']}(#{@node['role']}) status: #{status}"

      result = case status
        when 'succeed'
          processing_succeed_node
        when 'running'
          processing_running_node
        when 'error'
          processing_error_node(last_run)
        end

      #TODO(vsharshov): Should we move it to control module?
      @ctx.report_and_update_status('nodes' => [result]) if result

      # ready, error or deploying
      result.fetch('status', 'deploying')
    rescue MClientTimeout
      Astute.logger.warn "MCollective agents #{@node['uid']} " \
        "didn't respond within the allotted time"
      'error'
    end

    private

    def puppetd
      puppetd = MClient.new(@ctx, "puppetd", [@node['uid']])
      puppetd.on_respond_timeout do |uids|
        nodes = uids.map do |uid|
          {
            'uid' => uid,
            'status' => 'error',
            'error_type' => 'deploy',
            'role' => @node['role']
          }
        end
        @ctx.report_and_update_status('nodes' => nodes)
        raise MClientTimeout
      end
      puppetd
    end

    def puppet_status
      puppetd.last_run_summary.first[:data]
    end

    def puppet_run
      puppetd.runonce(
        :puppet_debug => @puppet_debug,
        :manifest => @puppet_manifest,
        :modules  => @puppet_modules,
        :cwd => @cwd
      )
    end

    def running?(status)
      ['running'].include? status[:status]
    end

    def idling?(status)
      ['idling'].include? status[:status]
    end

    def stopped?(status)
      ['stopped', 'disabled'].include? status[:status]
    end

    def succeed?(status)
      status[:status] == 'stopped' &&
      status[:resources]['failed'].to_i == 0 &&
      status[:resources]['failed_to_restart'].to_i == 0 &&
      status[:time]['last_run'] != (@prev_summary && @prev_summary[:time]['last_run'])
    end

    # Runs puppetd.runonce only if puppet is stopped on the host at the time
    # If it isn't stopped, we wait a bit and try again.
    # Returns list of nodes uids which appear to be with hung puppet.
    def puppetd_runonce
      started = Time.now.to_i
      while Time.now.to_i - started < Astute.config.puppet_fade_timeout
        status = puppet_status

        is_stopped = stopped?(status)
        is_idling = idling?(status)
        is_running = running?(status)

        #Try to kill 'idling' process and run again by 'runonce' call
        puppet_run if is_stopped || is_idling

        break if !is_running && !is_idling
        sleep Astute.config.puppet_fade_interval
      end

      if is_running || is_idling
        Astute.logger.warn "Following nodes have puppet hung " \
          "(#{is_running ? 'running' : 'idling'}): '#{@node['uid']}'"
        @is_hung = true
      else
        @is_hung = false
      end
    end

    def node_status(last_run)
      case
      when @is_hung
        'error'
      when succeed?(last_run) && !@is_hung
        'succeed'
      when (running?(last_run) || idling?(last_run)) && !@is_hung
        'running'
      when stopped?(last_run) && !succeed?(last_run) && !@is_hung
        'error'
      else
        msg = "Unknow status: " \
          "is_hung #{@is_hung}, succeed? #{succeed?(last_run)}, " \
          "running? #{running?(last_run)}, stopped? #{stopped?(last_run)}, " \
          "idling? #{idling?(last_run)}"
        raise msg
      end
    end

    def processing_succeed_node
      Astute.logger.debug "Puppet completed within #{@time_observer.stop} seconds"
      { 'uid' => @node['uid'], 'status' => 'ready', 'role' => @node['role'] }
    end

    def processing_error_node(last_run)
      if @retries > 0
        @retries -= 1
        Astute.logger.debug "Puppet on node #{@node['uid']} will be "\
          "restarted. #{@retries} retries remained."
        Astute.logger.info "Retrying to run puppet for following error " \
          "nodes: #{@node['uid']}"
        puppetd_runonce
        # We need this magic with prev_summary to reflect new puppetd run statuses..
        @prev_summary = last_run
        node_report_format('status' => 'deploying')
      else
        Astute.logger.debug "Node #{@node['uid']} has failed to deploy. " \
          "There is no more retries for puppet run."
        node_report_format('status' => 'error', 'error_type' => 'deploy')
      end
    end

    def processing_running_node
      nodes_to_report = []
      begin
        # Pass nodes because logs calculation needs IP address of node, not just uid
        nodes_progress = @ctx.deploy_log_parser.progress_calculate([@node['uid']], [@node])
        if nodes_progress.present?
          Astute.logger.debug "Got progress for nodes:\n#{nodes_progress.pretty_inspect}"

          # Nodes with progress are running, so they are not included in nodes_to_report yet
          nodes_progress.map! { |x| x.merge!('status' => 'deploying', 'role' => @node['role']) }
          nodes_to_report = nodes_progress
        end
      rescue => e
        Astute.logger.warn "Some error occurred when parse logs for " \
          "nodes progress: #{e.message}, trace: #{e.format_backtrace}"
      end
      nodes_to_report.first || node_report_format('status' => 'deploying')
    end

    def node_report_format(add_info={})
      add_info.merge('uid' => @node['uid'], 'role' => @node['role'])
    end

  end #PuppetTask

  class TimeObserver

    def initialize(timeout)
      @timeout = timeout
    end

    def start
      @time_before = Time.now
    end

    def stop
      (Time.now - @time_before).to_i
    end

    def enough_time?
      Time.now - @time_before < time_limit
    end

    def time_limit
      @timeout
    end
  end #TimeObserver

end