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


require 'json'
require 'timeout'

module Astute
  module PuppetdDeployer

    def self.deploy(ctx, nodes, retries=1)
      @ctx = ctx
      @nodes_roles = nodes.inject({}) { |h, n| h.merge({n['uid'] => n['role']}) }
      @node_retries = nodes.inject({}) { |h, n| h.merge({n['uid'] => retries}) }
      @nodes = nodes

      Astute.logger.debug "Waiting for puppet to finish deployment on all
                           nodes (timeout = #{Astute.config.PUPPET_TIMEOUT} sec)..."
      time_before = Time.now

      deploy_nodes(@nodes.map { |n| n['uid'] })

      time_spent = Time.now - time_before
      Astute.logger.info "#{@ctx.task_id}: Spent #{time_spent} seconds on puppet run "\
                         "for following nodes(uids): #{@nodes.map {|n| n['uid']}.join(',')}"
    end

    private
    # Runs puppetd.runonce only if puppet is stopped on the host at the time
    # If it isn't stopped, we wait a bit and try again.
    # Returns list of nodes uids which appear to be with hung puppet.
    def self.puppetd_runonce(uids)
      started = Time.now.to_i
      while Time.now.to_i - started < Astute.config.PUPPET_FADE_TIMEOUT
        running_uids = puppetd(uids).last_run_summary.select { |x|
          ['running', 'idling'].include?(x.results[:data][:status])
        }.map { |n| n.results[:sender] }
        stopped_uids = uids - running_uids

        @nodes.select { |n| stopped_uids.include? n['uid'] }
             .group_by { |n| n['debug'] }
             .each do |debug, stop_nodes|
               puppetd(stop_nodes.map { |n| n['uid'] }).runonce(:puppet_debug => true)
             end
        break if running_uids.empty?

        uids = running_uids
        sleep Astute.config.PUPPET_FADE_INTERVAL
      end
      Astute.logger.debug "puppetd_runonce completed within #{Time.now.to_i - started} seconds."
      Astute.logger.warn "Following nodes have puppet hung: '#{running_uids.join(',')}'" if running_uids.present?
      running_uids
    end

    def self.calc_nodes_status(last_run, prev_run, hung_nodes=[])
      # Finished are those which are not in running state,
      #   and changed their last_run time, which is changed after application of catalog,
      #   at the time of updating last_run_summary file. At that particular time puppet is
      #   still running, and will finish in a couple of seconds.
      # If Puppet had crashed before it got a catalog (e.g. certificate problems),
      #   it didn't update last_run_summary file and switched to 'stopped' state.

      # Consider only hung nodes which was in last_run
      hung_nodes = hung_nodes & last_run.map { |n| n.results[:sender] }

      stopped = last_run.select { |x| ['stopped', 'disabled'].include? x.results[:data][:status] }

      # Select all finished nodes which not failed and changed last_run time.
      succeed_nodes = stopped.select { |n|
        prev_n = prev_run.find{|ps| ps.results[:sender] == n.results[:sender] }

        n.results[:data][:status] == 'stopped' &&
        n.results[:data][:resources]['failed'].to_i == 0 &&
        n.results[:data][:resources]['failed_to_restart'].to_i == 0 &&
        n.results[:data][:time]['last_run'] != (prev_n && prev_n.results[:data][:time]['last_run'])
      }.map{|x| x.results[:sender] }

      stopped_nodes = stopped.map { |x| x.results[:sender] }
      error_nodes = stopped_nodes - succeed_nodes
      running_nodes = last_run.map {|n| n.results[:sender]} - stopped_nodes

      # Hunged nodes can change state at this moment(success, error or still run),
      # but we should to turn it on only in error_nodes
      succeed_nodes -= hung_nodes
      error_nodes = (error_nodes + hung_nodes).uniq
      running_nodes -= hung_nodes

      nodes_to_check = running_nodes + succeed_nodes + error_nodes
      all_nodes = last_run.map { |n| n.results[:sender] }
      if nodes_to_check.size != all_nodes.size
        raise "Internal error. Check: #{nodes_to_check.inspect}, passed #{all_nodes.inspect}"
      end
      {'succeed' => succeed_nodes, 'error' => error_nodes, 'running' => running_nodes}
    end


    def self.puppetd(uids)
      puppetd = MClient.new(@ctx, "puppetd", Array(uids))
      puppetd.on_respond_timeout do |uids|
        nodes = uids.map do |uid|
          { 'uid' => uid, 'status' => 'error', 'error_type' => 'deploy', 'role' => @nodes_roles[uid] }
        end
        @ctx.report_and_update_status('nodes' => nodes)
      end
      puppetd
    end

    def self.processing_error_nodes(error_nodes)
      nodes_to_report = []
      nodes_to_retry = []

      error_nodes.each do |uid|
        if @node_retries[uid] > 0
          @node_retries[uid] -= 1
          Astute.logger.debug "Puppet on node #{uid.inspect} will be restarted. "\
                              "#{@node_retries[uid]} retries remained."
          nodes_to_retry << uid
        else
          Astute.logger.debug "Node #{uid.inspect} has failed to deploy. There is no more retries for puppet run."
          nodes_to_report << {'uid' => uid, 'status' => 'error', 'error_type' => 'deploy', 'role' => @nodes_roles[uid] }
        end
      end

      return nodes_to_report, nodes_to_retry
    end

    def self.processing_running_nodes(running_nodes)
      nodes_to_report = []
      if running_nodes.present?
        begin
          # Pass nodes because logs calculation needs IP address of node, not just uid
          nodes_progress = @ctx.deploy_log_parser.progress_calculate(running_nodes, @nodes)
          if nodes_progress.present?
            Astute.logger.debug "Got progress for nodes: #{nodes_progress.inspect}"
            # Nodes with progress are running, so they are not included in nodes_to_report yet
            nodes_progress.map! { |x| x.merge!('status' => 'deploying', 'role' => @nodes_roles[x['uid']]) }
            nodes_to_report = nodes_progress
          end
        rescue => e
          Astute.logger.warn "Some error occurred when parse logs for nodes progress: #{e.message}, "\
                             "trace: #{e.format_backtrace}"
        end
      end
      nodes_to_report
    end

    def self.processing_succeed_nodes(succeed_nodes)
      succeed_nodes.map do |uid|
        { 'uid' => uid, 'status' => 'ready', 'role' => @nodes_roles[uid] }
      end
    end

    # As I (Andrey Danin) understand, Puppet agent goes through these steps:
    #   * Puppetd has 'stopped' state.
    #   * We run it as a run_once, and puppetd goes to 'idling' state - it trying to
    #       retrieve catalog.
    #   * If it can't retrieve catalog, it goes back to 'stopped' state without
    #       any update of last_run_summary file.
    #   * If puppetd retrieve catalog, it goes to 'running' state, which means
    #       it appying catalog to system.
    #   * When puppetd finished catalog run, it updates last_run_summary file
    #       but stays in 'running' state for a while.
    #   * After puppetd finished all internal jobs connected with finished catalog,
    #       it goes to 'idling' state.
    #   * After a short time it goes to 'stopped' state because we ran it as a run_once.
    def self.deploy_nodes(nodes_to_check)
      Timeout::timeout(Astute.config.PUPPET_TIMEOUT) do
        prev_summary = puppetd(nodes_to_check).last_run_summary
        hung_nodes = puppetd_runonce(nodes_to_check)

        while nodes_to_check.present?
          last_run = puppetd(nodes_to_check).last_run_summary
          calc_nodes = calc_nodes_status(last_run, prev_summary, hung_nodes)
          Astute.logger.debug "Nodes statuses: #{calc_nodes.inspect}"

          report_succeed = processing_succeed_nodes calc_nodes['succeed']
          report_error, nodes_to_retry = processing_error_nodes(calc_nodes['error'])
          report_running = processing_running_nodes(calc_nodes['running'])

          nodes_to_report = report_succeed + report_error + report_running
          @ctx.report_and_update_status('nodes' => nodes_to_report) if nodes_to_report.present?

          if nodes_to_retry.present?
            Astute.logger.info "Retrying to run puppet for following error nodes: #{nodes_to_retry.join(',')}"
            hung_nodes = puppetd_runonce(nodes_to_retry)
            # We need this magic with prev_summary to reflect new puppetd run statuses..
            prev_summary.delete_if { |x| nodes_to_retry.include?(x.results[:sender]) }
            prev_summary += last_run.select { |x| nodes_to_retry.include?(x.results[:sender]) }
          end

          # we will iterate only over running nodes and those that we restart deployment for
          nodes_to_check = calc_nodes['running'] + nodes_to_retry

          break if nodes_to_check.empty?
          sleep Astute.config.PUPPET_DEPLOY_INTERVAL
        end
      end
    end

  end
end
