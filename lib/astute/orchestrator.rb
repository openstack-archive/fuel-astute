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

module Astute

  class Orchestrator
    def initialize(log_parsing=false)
      @log_parsing = log_parsing
    end

    def node_type(reporter, task_id, nodes_uids, timeout=nil)
      context = Context.new(task_id, reporter)
      systemtype = MClient.new(context, "systemtype", nodes_uids, check_result=false, timeout)
      systems = systemtype.get_type
      systems.map do |n|
        {
          'uid'       => n.results[:sender],
          'node_type' => n.results[:data][:node_type].chomp
        }
      end
    end

    def execute_tasks(up_reporter, task_id, tasks)
      ctx = Context.new(task_id, up_reporter)
      Astute::NailgunHooks.new(tasks, ctx, 'execute_tasks').process
      report_result({}, up_reporter)
    end

    def deploy(up_reporter, task_id, deployment_info, pre_deployment=[], post_deployment=[])
      deploy_cluster(
        up_reporter,
        task_id,
        deployment_info,
        Astute::DeploymentEngine::NailyFact,
        pre_deployment,
        post_deployment
      )
    end

    def task_deployment(up_reporter, task_id, deployment_info, pre_deployment=[], post_deployment=[])
      deploy_cluster(
        up_reporter,
        task_id,
        deployment_info,
        Astute::DeploymentEngine::Tasklib,
        pre_deployment,
        post_deployment
      )
    end

    def granular_deploy(up_reporter, task_id, deployment_info, pre_deployment=[], post_deployment=[])
      deploy_cluster(
        up_reporter,
        task_id,
        deployment_info,
        Astute::DeploymentEngine::GranularDeployment,
        pre_deployment,
        post_deployment
      )
    end

    def provision(reporter, task_id, engine_attrs, nodes)
      raise "Nodes to provision are not provided!" if nodes.empty?
      provision_method = engine_attrs['provision_method'] || 'cobbler'

      cobbler = CobblerManager.new(engine_attrs, reporter)
      begin
        remove_nodes(
          reporter,
          task_id,
          engine_attrs,
          nodes,
          reboot=false,
          raise_if_error=true
        )
        cobbler.add_nodes(nodes)

        # if provision_method is 'image', we do not need to immediately
        # reboot nodes. instead, we need to run image based provisioning
        # process and then reboot nodes

        # TODO(kozhukalov): do not forget about execute_shell_command timeout which is 3600
        # watch_provision_progress has PROVISIONING_TIMEOUT + 3600 is much longer than PROVISIONING_TIMEOUT
        if provision_method == 'image'
          # disabling pxe boot
          cobbler.netboot_nodes(nodes, false)
          image_provision(reporter, task_id, nodes)
        end
        # TODO(vsharshov): maybe we should reboot nodes using mco or ssh instead of Cobbler
        reboot_events = cobbler.reboot_nodes(nodes)
        failed_nodes  = cobbler.check_reboot_nodes(reboot_events)

        # control reboot for nodes which still in bootstrap state
	# Note: if the image based provisioning is used nodes are already
	# provisioned and rebooting is not necessary. In fact the forced
	# reboot can corrupt a node if it manages to reboot fast enough
	# (see LP #1394599)
	# XXX: actually there's a tiny probability to reboot a node being
	# provisioned in a traditional way (by Debian installer or anaconda),
	# however such a double reboot is not dangerous since cobbler will
	# boot such a node into installer once again.
	if provision_method != 'image'
          control_reboot_using_ssh(reporter, task_id, nodes)
        end
      rescue => e
        Astute.logger.error("Error occured while provisioning: #{e.inspect}")
        reporter.report({
            'status' => 'error',
            'error' => e.message,
            'progress' => 100})
        unlock_nodes_discovery(reporter, task_id, nodes.map {|n| n['slave_name']}, nodes)
        raise e
      end

      if failed_nodes.present?
        err_msg = "Nodes failed to reboot: #{failed_nodes.inspect}"
        Astute.logger.error(err_msg)
        reporter.report({
            'status' => 'error',
            'error' => err_msg,
            'progress' => 100})

        unlock_nodes_discovery(reporter, task_id="", failed_nodes, nodes)
        raise FailedToRebootNodesError.new(err_msg)
      end

      watch_provision_progress(reporter, task_id, nodes)
    end

    def image_provision(reporter, task_id, nodes)
      failed_uids_provis = ImageProvision.provision(Context.new(task_id, reporter), nodes)
      if failed_uids_provis.empty?
        reporter.report({
          'status' => 'provisioning',
          'progress' => 80,
          'msg' => 'Nodes have beed successfully provisioned. Next step is reboot.'
        })
      else
        err_msg = 'At least one of nodes have failed during provisioning'
        Astute.logger.error("#{task_id}: #{err_msg}")
        reporter.report({
          'status' => 'error',
          'progress' => 100,
          'msg' => err_msg,
          'error_type' => 'provision'
        })
        raise FailedImageProvisionError.new(err_msg)
      end
    end


    def watch_provision_progress(reporter, task_id, nodes)
      raise "Nodes to provision are not provided!" if nodes.empty?

      provision_log_parser = @log_parsing ? LogParser::ParseProvisionLogs.new : LogParser::NoParsing.new
      proxy_reporter = ProxyReporter::DeploymentProxyReporter.new(reporter)

      prepare_logs_for_parsing(provision_log_parser, nodes)

      nodes_not_booted = nodes.map{ |n| n['uid'] }
      result_msg = {'nodes' => []}
      begin
        Timeout.timeout(Astute.config.PROVISIONING_TIMEOUT) do  # Timeout for booting target OS
          catch :done do
            loop do
              sleep_not_greater_than(20) do
                nodes_types = node_type(proxy_reporter, task_id, nodes.map {|n| n['uid']}, 5)
                target_uids, nodes_not_booted, reject_uids = analize_node_types(nodes_types, nodes_not_booted)

                if reject_uids.present?
                  ctx ||= Context.new(task_id, proxy_reporter)
                  reject_nodes = reject_uids.map { |uid| {'uid' => uid } }
                  NodesRemover.new(ctx, reject_nodes, reboot=true).remove
                end

                if nodes_not_booted.empty?
                  Astute.logger.info "All nodes are provisioned"
                  throw :done
                end

                Astute.logger.debug("Still provisioning follow nodes: #{nodes_not_booted}")
                report_about_progress(proxy_reporter, provision_log_parser, target_uids, nodes)
              end
            end
          end
          # We are here if jumped by throw from while cycle
        end
      rescue Timeout::Error
        Astute.logger.error("Timeout of provisioning is exceeded. Nodes not booted: #{nodes_not_booted}")
        nodes_progress = nodes_not_booted.map do |n|
          {
            'uid' => n,
            'status' => 'error',
            'error_msg' => "Timeout of provisioning is exceeded",
            'progress' => 100,
            'error_type' => 'provision'
          }
        end

        result_msg.merge!({
            'status' => 'error',
            'error' => 'Timeout of provisioning is exceeded',
            'progress' => 100})

        result_msg['nodes'] += nodes_progress
      end

      node_uids = nodes.map { |n| n['uid'] }
      (node_uids - nodes_not_booted).each do |uid|
        result_msg['nodes'] << {'uid' => uid, 'progress' => 100, 'status' => 'provisioned'}
      end

      # If there was no errors, then set status to ready
      result_msg.reverse_merge!({'status' => 'ready', 'progress' => 100})

      proxy_reporter.report(result_msg)

      result_msg
    end

    def remove_nodes(reporter, task_id, engine_attrs, nodes, reboot=true, raise_if_error=false)
      cobbler = CobblerManager.new(engine_attrs, reporter)
      cobbler.remove_nodes(nodes)
      ctx = Context.new(task_id, reporter)
      result = NodesRemover.new(ctx, nodes, reboot).remove

      if (result['error_nodes'] || result['inaccessible_nodes']) && raise_if_error
        bad_node_ids = result.fetch('error_nodes', []) +
          result.fetch('inaccessible_nodes', [])
        raise "Mcollective problem with nodes #{bad_node_ids}, please check log for details"
      end

      Rsyslogd.send_sighup(ctx, engine_attrs["master_ip"])
      result
    end

    def stop_puppet_deploy(reporter, task_id, nodes)
      nodes_uids = nodes.map { |n| n['uid'] }.uniq
      puppetd = MClient.new(Context.new(task_id, reporter), "puppetd", nodes_uids, check_result=false)
      puppetd.stop_and_disable
    end

    def stop_provision(reporter, task_id, engine_attrs, nodes)
      ctx = Context.new(task_id, reporter)

      ssh_result = stop_provision_via_ssh(ctx, nodes, engine_attrs)

      # Remove already provisioned node. Possible erasing nodes twice
      provisioned_nodes, mco_result = stop_provision_via_mcollective(ctx, nodes)

      # For nodes responded via mcollective use mcollective result instead of ssh
      ['nodes', 'error_nodes', 'inaccessible_nodes'].each do |node_status|
        ssh_result[node_status] = ssh_result.fetch(node_status, []) - provisioned_nodes
      end

      result = merge_rm_nodes_result(ssh_result, mco_result)
      result['status'] = 'error' if result['error_nodes'].present?
      result
    end

    def dump_environment(reporter, task_id, settings)
      Dump.dump_environment(Context.new(task_id, reporter), settings)
    end

    def verify_networks(reporter, task_id, nodes)
      ctx = Context.new(task_id, reporter)
      validate_nodes_access(ctx, nodes)
      Network.check_network(ctx, nodes)
    end

    def check_dhcp(reporter, task_id, nodes)
      ctx = Context.new(task_id, reporter)
      validate_nodes_access(ctx, nodes)
      Network.check_dhcp(ctx, nodes)
    end

    def multicast_verification(reporter, task_id, nodes)
      ctx = Context.new(task_id, reporter)
      validate_nodes_access(ctx, nodes)
      Network.multicast_verification(ctx, nodes)
    end

    private

    def validate_nodes_access(ctx, nodes)
      nodes_types = node_type(ctx.reporter, ctx.task_id, nodes.map{ |n| n['uid'] }, timeout=10)
      not_avaliable_nodes = nodes.map { |n| n['uid'].to_s } - nodes_types.map { |n| n['uid'].to_s }
      unless not_avaliable_nodes.empty?
        raise "Network verification not avaliable because nodes #{not_avaliable_nodes} " \
          "not avaliable via mcollective"
      end
    end

    def deploy_cluster(up_reporter, task_id, deployment_info, deploy_engine, pre_deployment, post_deployment)
      proxy_reporter = ProxyReporter::DeploymentProxyReporter.new(up_reporter, deployment_info)
      log_parser = @log_parsing ? LogParser::ParseDeployLogs.new : LogParser::NoParsing.new
      context = Context.new(task_id, proxy_reporter, log_parser)
      deploy_engine_instance = deploy_engine.new(context)
      Astute.logger.info "Using #{deploy_engine_instance.class} for deployment."

      deploy_engine_instance.deploy(deployment_info, pre_deployment, post_deployment)

      context.status
    end

    def report_result(result, reporter)
      default_result = {'status' => 'ready', 'progress' => 100}

      result = {} unless result.instance_of?(Hash)
      status = default_result.merge(result)
      reporter.report(status)
    end

    def prepare_logs_for_parsing(provision_log_parser, nodes)
      sleep_not_greater_than(10) do # Wait while nodes going to reboot
        Astute.logger.info "Starting OS provisioning for nodes: #{nodes.map{ |n| n['uid'] }.join(',')}"
        begin
          provision_log_parser.prepare(nodes)
        rescue => e
          Astute.logger.warn "Some error occurred when prepare LogParser: #{e.message}, trace: #{e.format_backtrace}"
        end
      end
    end

    def analize_node_types(types, nodes_not_booted)
      types.each { |t| Astute.logger.debug("Got node types: uid=#{t['uid']} type=#{t['node_type']}") }
      target_uids = types.reject{ |n| n['node_type'] != 'target' }.map{ |n| n['uid'] }
      reject_uids = types.reject{ |n| n['node_type'] == 'target' }.map{ |n| n['uid'] }
      Astute.logger.debug("Not target nodes will be rejected: #{reject_uids.join(',')}")

      nodes_not_booted -= target_uids
      Astute.logger.debug "Not provisioned: #{nodes_not_booted.join(',')}, " \
       "got target OSes: #{target_uids.join(',')}"
      return target_uids, nodes_not_booted, reject_uids
    end

    def sleep_not_greater_than(sleep_time, &block)
      time = Time.now.to_f
      block.call
      time = time + sleep_time - Time.now.to_f
      sleep(time) if time > 0
    end

    def report_about_progress(reporter, provision_log_parser, target_uids, nodes)
      begin
        nodes_progress = provision_log_parser.progress_calculate(nodes.map{ |n| n['uid'] }, nodes)
        nodes_progress.each do |n|
          if target_uids.include?(n['uid'])
            n['progress'] = 100
            n['status']   = 'provisioned'
          else
            n['status']   = 'provisioning'
          end
        end
        reporter.report({'nodes' => nodes_progress})
      rescue => e
        Astute.logger.warn "Some error occurred when parse logs for nodes progress: #{e.message}, trace: #{e.format_backtrace}"
      end
    end

    def stop_provision_via_mcollective(ctx, nodes)
      return [], {} if nodes.empty?

      mco_result = {}
      nodes_uids = nodes.map{ |n| n['uid'] }

      Astute.config.MC_RETRIES.times do |i|
        sleep Astute.config.NODES_REMOVE_INTERVAL

        Astute.logger.debug "Trying to connect to nodes #{nodes_uids} using mcollective"
        nodes_types = node_type(ctx.reporter, ctx.task_id, nodes_uids, 2)
        next if nodes_types.empty?

        provisioned = nodes_types.select{ |n| ['target', 'bootstrap'].include? n['node_type'] }
                                 .map{ |n| {'uid' => n['uid']} }
        current_mco_result = NodesRemover.new(ctx, provisioned, reboot=true).remove
        Astute.logger.debug "Retry result #{i}: "\
          "mco success nodes: #{current_mco_result['nodes']}, "\
          "mco error nodes: #{current_mco_result['error_nodes']}, "\
          "mco inaccessible nodes: #{current_mco_result['inaccessible_nodes']}"

        mco_result = merge_rm_nodes_result(mco_result, current_mco_result)
        nodes_uids -= provisioned.map{ |n| n['uid'] }

        break if nodes_uids.empty?
      end

      provisioned_nodes = nodes.map{ |n| {'uid' => n['uid']} } - nodes_uids.map {|n| {'uid' => n} }

      Astute.logger.debug "MCO final result: "\
        "mco success nodes: #{mco_result['nodes']}, "\
        "mco error nodes: #{mco_result['error_nodes']}, "\
        "mco inaccessible nodes: #{mco_result['inaccessible_nodes']}, "\
        "all mco nodes: #{provisioned_nodes}"

      return provisioned_nodes, mco_result
    end

    def stop_provision_via_ssh(ctx, nodes, engine_attrs)
      ssh_result = Ssh.execute(ctx, nodes, SshEraseNodes.command)
      CobblerManager.new(engine_attrs, ctx.reporter).remove_nodes(nodes)
      Ssh.execute(ctx,
                  nodes,
                  SshHardReboot.command,
                  timeout=5,
                  retries=1)
      ssh_result
    end

    def merge_rm_nodes_result(res1, res2)
      ['nodes', 'error_nodes', 'inaccessible_nodes'].inject({}) do |result, node_status|
        result[node_status] = (res1.fetch(node_status, []) + res2.fetch(node_status, [])).uniq
        result
      end
    end

    def unlock_nodes_discovery(reporter, task_id="", failed_nodes, nodes)
      nodes_uids = nodes.select{ |n| failed_nodes.include?(n['slave_name']) }
                        .map{ |n| n['uid'] }
      shell = MClient.new(Context.new(task_id, reporter),
                          'execute_shell_command',
                          nodes_uids,
                          check_result=false,
                          timeout=2)
      mco_result = shell.execute(:cmd => 'rm -f /var/run/nodiscover')
      result = mco_result.map do |n|
        {
          'uid'       => n.results[:sender],
          'exit code' => n.results[:data][:exit_code]
        }
      end
      Astute.logger.debug "Unlock discovery for failed nodes. Result: #{result}"
    end

    def control_reboot_using_ssh(reporter, task_id="", nodes)
      ctx = Context.new(task_id, reporter)
      nodes.each { |n| n['admin_ip'] = n['power_address'] }
      Ssh.execute(ctx,
                  nodes,
                  SshHardReboot.command,
                  timeout=5,
                  retries=1)
    end

  end # class
end # module
