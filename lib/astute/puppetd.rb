require 'json'
require 'timeout'

module Astute
  module PuppetdDeployer
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

    private
    # Runs puppetd.runonce only if puppet is stopped on the host at the time
    # If it isn't stopped, we wait a bit and try again.
    # Returns list of nodes uids which appear to be with hung puppet.
    def self.puppetd_runonce(puppetd, uids)
      started = Time.now.to_i
      while Time.now.to_i - started < Astute.config.PUPPET_FADE_TIMEOUT
        puppetd.discover(:nodes => uids)
        last_run = puppetd.last_run_summary
        running_uids = last_run.select {|x| x.results[:data][:status] != 'stopped'}.map {|n| n.results[:sender]}
        stopped_uids = uids - running_uids
        if stopped_uids.any?
          puppetd.discover(:nodes => stopped_uids)
          puppetd.runonce
        end
        uids = running_uids
        break if uids.empty?
        sleep Astute.config.PUPPET_FADE_INTERVAL
      end
      Astute.logger.debug "puppetd_runonce completed within #{Time.now.to_i - started} seconds."
      Astute.logger.debug "Following nodes have puppet hung: '#{running_uids.join(',')}'" if running_uids.any?
      running_uids
    end

    def self.calc_nodes_status(last_run, prev_run)
      # Finished are those which are not in running state,
      #   and changed their last_run time, which is changed after application of catalog,
      #   at the time of updating last_run_summary file. At that particular time puppet is
      #   still running, and will finish in a couple of seconds.
      # If Puppet had crashed before it got a catalog (e.g. certificate problems),
      #   it didn't update last_run_summary file and switched to 'stopped' state.

      stopped = last_run.select {|x| x.results[:data][:status] == 'stopped'}

      # Select all finished nodes which not failed and changed last_run time.
      succeed_nodes = stopped.select { |n|
        prev_n = prev_run.find{|ps| ps.results[:sender] == n.results[:sender] }
        n.results[:data][:resources]['failed'].to_i == 0 &&
          n.results[:data][:resources]['failed_to_restart'].to_i == 0 &&
          n.results[:data][:time]['last_run'] != (prev_n && prev_n.results[:data][:time]['last_run'])
      }.map{|x| x.results[:sender] }

      stopped_nodes = stopped.map {|x| x.results[:sender]}
      error_nodes = stopped_nodes - succeed_nodes

      # Running are all which didn't appear in finished
      running_nodes = last_run.map {|n| n.results[:sender]} - stopped_nodes

      nodes_to_check = running_nodes + succeed_nodes + error_nodes
      unless nodes_to_check.size == last_run.size
        raise "Shoud never happen. Internal error in nodes statuses calculation. Statuses calculated for: #{nodes_to_check.inspect},"
                    "nodes passed to check statuses of: #{last_run.map {|n| n.results[:sender]}}"
      end
      {'succeed' => succeed_nodes, 'error' => error_nodes, 'running' => running_nodes}
    end

    public
    def self.deploy(ctx, nodes, retries=2, change_node_status=true)
      # TODO: can we hide retries, ignore_failure into @ctx ?
      uids = nodes.map {|n| n['uid']}
      # Keep info about retries for each node
      node_retries = {}
      uids.each {|x| node_retries.merge!({x => retries}) }
      Astute.logger.debug "Waiting for puppet to finish deployment on all nodes (timeout = #{Astute.config.PUPPET_TIMEOUT} sec)..."
      time_before = Time.now
      Timeout::timeout(Astute.config.PUPPET_TIMEOUT) do
        puppetd = MClient.new(ctx, "puppetd", uids)
        puppetd.on_respond_timeout do |uids|
          ctx.reporter.report('nodes' => uids.map{|uid| {'uid' => uid, 'status' => 'error', 'error_type' => 'deploy'}})
        end if change_node_status
        prev_summary = puppetd.last_run_summary
        puppetd_runonce(puppetd, uids)
        nodes_to_check = uids
        last_run = prev_summary
        while nodes_to_check.any?
          calc_nodes = calc_nodes_status(last_run, prev_summary)
          Astute.logger.debug "Nodes statuses: #{calc_nodes.inspect}"

          # At least we will report about successfully deployed nodes
          nodes_to_report = []
          nodes_to_report.concat(calc_nodes['succeed'].map { |n| {'uid' => n, 'status' => 'ready'} }) if change_node_status

          # Process retries
          nodes_to_retry = []
          calc_nodes['error'].each do |uid|
            if node_retries[uid] > 0
              node_retries[uid] -= 1
              Astute.logger.debug "Puppet on node #{uid.inspect} will be restarted. "\
                                  "#{node_retries[uid]} retries remained."
              nodes_to_retry << uid
            else
              Astute.logger.debug "Node #{uid.inspect} has failed to deploy. There is no more retries for puppet run."
              nodes_to_report << {'uid' => uid, 'status' => 'error', 'error_type' => 'deploy'} if change_node_status
            end
          end
          if nodes_to_retry.any?
            Astute.logger.info "Retrying to run puppet for following error nodes: #{nodes_to_retry.join(',')}"
            puppetd_runonce(puppetd, nodes_to_retry)
            # We need this magic with prev_summary to reflect new puppetd run statuses..
            prev_summary.delete_if { |x| nodes_to_retry.include?(x.results[:sender]) }
            prev_summary += last_run.select { |x| nodes_to_retry.include?(x.results[:sender]) }
          end
          # /end of processing retries

          if calc_nodes['running'].any?
            begin
              # Pass nodes because logs calculation needs IP address of node, not just uid
              nodes_progress = ctx.deploy_log_parser.progress_calculate(calc_nodes['running'], nodes)
              if nodes_progress.any?
                Astute.logger.debug "Got progress for nodes: #{nodes_progress.inspect}"
                # Nodes with progress are running, so they are not included in nodes_to_report yet
                nodes_progress.map! {|x| x.merge!({'status' => 'deploying'})}
                nodes_to_report += nodes_progress
              end
            rescue Exception => e
              Astute.logger.warn "Some error occurred when parse logs for nodes progress: #{e.message}, "\
                                 "trace: #{e.backtrace.inspect}"
            end
          end
          ctx.reporter.report('nodes' => nodes_to_report) if nodes_to_report.any?

          # we will iterate only over running nodes and those that we restart deployment for
          nodes_to_check = calc_nodes['running'] + nodes_to_retry
          break if nodes_to_check.empty?

          sleep Astute.config.PUPPET_DEPLOY_INTERVAL
          puppetd.discover(:nodes => nodes_to_check)
          last_run = puppetd.last_run_summary
        end
      end
      time_spent = Time.now - time_before
      Astute.logger.info "#{ctx.task_id}: Spent #{time_spent} seconds on puppet run "\
                         "for following nodes(uids): #{nodes.map {|n| n['uid']}.join(',')}"
    end
  end
end
