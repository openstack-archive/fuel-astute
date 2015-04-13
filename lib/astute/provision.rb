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

  class Provisioner
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

    def provision(reporter, task_id, provisioning_info, provision_method)
      engine_attrs = provisioning_info['engine']
      nodes = provisioning_info['nodes']

      raise "Nodes to provision are not provided!" if nodes.empty?

      fault_tolerance = provisioning_info.fetch('fault_tolerance', [])

      cobbler = CobblerManager.new(engine_attrs, reporter)
      result_msg = {'nodes' => []}
      begin
        check_ubuntu_repo_connectivity(nodes, task_id, reporter)

        remove_nodes(
          reporter,
          task_id,
          engine_attrs,
          nodes,
          reboot=false,
          raise_if_error=true
        )
        cobbler.add_nodes(nodes)
        failed_uids, timeouted_uids = provision_and_watch_progress(reporter,
                                                                    task_id,
                                                                    Array.new(nodes),
                                                                    engine_attrs,
                                                                    provision_method,
                                                                    fault_tolerance)

      rescue => e
        Astute.logger.error("Error occured while provisioning: #{e.inspect}")
        reporter.report({
            'status' => 'error',
            'error' => e.message,
            'progress' => 100})
        unlock_nodes_discovery(reporter, task_id, nodes.map {|n| n['slave_name']}, nodes)
        raise e
      end

      handle_failed_nodes(failed_uids, result_msg)
      if failed_uids.count > 0
        unlock_nodes_discovery(reporter, task_id, failed_uids, nodes)
      end
      handle_timeouted_nodes(timeouted_uids, result_msg)

      node_uids = nodes.map { |n| n['uid'] }

      (node_uids - timeouted_uids - failed_uids).each do |uid|
        result_msg['nodes'] << {'uid' => uid, 'progress' => 100, 'status' => 'provisioned'}
      end

      if should_fail(failed_uids + timeouted_uids, fault_tolerance)
        result_msg['status'] = 'error'
        result_msg['error'] = 'Too many nodes failed to provision'
        result_msg['progress'] = 100
      end

      # If there was no errors, then set status to ready
      result_msg.reverse_merge!({'status' => 'ready', 'progress' => 100})
      Astute.logger.info "Message: #{result_msg}"

      reporter.report(result_msg)

      result_msg
    end

    def image_provision(reporter, task_id, nodes)
      failed_uids_provis = ImageProvision.provision(Context.new(task_id, reporter), nodes)
    end

    def provision_and_watch_progress(reporter,
                                     task_id,
                                     nodes_to_provision,
                                     engine_attrs,
                                     provision_method,
                                     fault_tolerance)
      raise "Nodes to provision are not provided!" if nodes_to_provision.empty?

      provision_log_parser = @log_parsing ? LogParser::ParseProvisionLogs.new : LogParser::NoParsing.new

      prepare_logs_for_parsing(provision_log_parser, nodes_to_provision)

      nodes_not_booted = []
      nodes = []
      nodes_timeout = {}
      timeouted_uids = []
      failed_uids = []
      max_nodes = Astute.config[:max_nodes_to_provision]
      Astute.logger.debug("Starting provision")
      catch :done do
        loop do
          sleep_not_greater_than(20) do
            #provision more
            if nodes_not_booted.count < max_nodes && nodes_to_provision.count > 0
              new_nodes = nodes_to_provision.shift(max_nodes - nodes_not_booted.count)

              Astute.logger.debug("Provisioning nodes: #{new_nodes}")
              failed_uids += provision_piece(reporter, task_id, engine_attrs, new_nodes, provision_method)
              Astute.logger.info "Nodes failed to reboot: #{failed_uids} "

              nodes_not_booted += new_nodes.map{ |n| n['uid'] }
              nodes_not_booted -= failed_uids
              nodes += new_nodes

              timeout_time = Time.now.utc + Astute.config.provisioning_timeout
              new_nodes.each {|n| nodes_timeout[n['uid']] = timeout_time}
            end

            nodes_types = node_type(reporter, task_id, nodes.map {|n| n['uid']}, 5)
            target_uids, nodes_not_booted, reject_uids = analize_node_types(nodes_types, nodes_not_booted)

            if reject_uids.present?
              ctx ||= Context.new(task_id, reporter)
              reject_nodes = reject_uids.map { |uid| {'uid' => uid } }
              NodesRemover.new(ctx, reject_nodes, reboot=true).remove
            end

            #check timouted nodes
            nodes_not_booted.each do |uid|
                time_now = Time.now.utc
                if nodes_timeout[uid] < time_now
                    Astute.logger.info "Node timed out to provision: #{uid} "
                    timeouted_uids.push(uid)
                end
            end
            nodes_not_booted -= timeouted_uids

            if should_fail(failed_uids + timeouted_uids, fault_tolerance)
              Astute.logger.debug("Aborting provision. To many nodes failed: #{failed_uids + timeouted_uids}")
              return failed_uids, timeouted_uids
            end

            if nodes_not_booted.empty? and nodes_to_provision.empty?
              Astute.logger.info "Provisioning finished"
              throw :done
            end

            Astute.logger.debug("Still provisioning following nodes: #{nodes_not_booted}")
            report_about_progress(reporter, provision_log_parser, target_uids, nodes)
          end
        end
      end
      return failed_uids, timeouted_uids
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

    def provision_piece(reporter, task_id, engine_attrs, nodes, provision_method)
      cobbler = CobblerManager.new(engine_attrs, reporter)
      failed_uids = []

      # if provision_method is 'image', we do not need to immediately
      # reboot nodes. instead, we need to run image based provisioning
      # process and then reboot nodes

      # TODO(kozhukalov): do not forget about execute_shell_command timeout which is 3600
      # provision_and_watch_progress has provisioning_timeout + 3600 is much longer than provisioning_timeout
      if provision_method == 'image'
        # disabling pxe boot
        cobbler.netboot_nodes(nodes, false)
        # change node type to prevent unexpected erase
        change_nodes_type(reporter, task_id, nodes)
        # Run parallel reporter
        report_image_provision(reporter, task_id, nodes) do
          failed_uids |= image_provision(reporter, task_id, nodes)
        end
      end
      # TODO(vsharshov): maybe we should reboot nodes using mco or ssh instead of Cobbler
      reboot_events = cobbler.reboot_nodes(nodes)
      not_rebooted = cobbler.check_reboot_nodes(reboot_events)
      not_rebooted = nodes.select { |n| not_rebooted.include?(n['slave_name'])}
      failed_uids |= not_rebooted.map { |n| n['uid']}

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
      return failed_uids
    end

    def report_image_provision(reporter, task_id, nodes,
      provision_log_parser=LogParser::ParseProvisionLogs.new, &block)
      prepare_logs_for_parsing(provision_log_parser, nodes)

      watch_and_report = Thread.new do
        loop do
          report_about_progress(reporter, provision_log_parser, [], nodes)
          sleep 1
        end
      end

      block.call
    ensure
      watch_and_report.exit if defined? watch_and_report
    end

    private

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
      reject_uids = types.reject{ |n| ['target', 'image'].include? n['node_type'] }.map{ |n| n['uid'] }
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

      Astute.config.mc_retries.times do |i|
        sleep Astute.config.nodes_remove_interval

        Astute.logger.debug "Trying to connect to nodes #{nodes_uids} using mcollective"
        nodes_types = node_type(ctx.reporter, ctx.task_id, nodes_uids, 2)
        next if nodes_types.empty?

        provisioned = nodes_types.select{ |n| ['target', 'bootstrap', 'image'].include? n['node_type'] }
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

    def unlock_nodes_discovery(reporter, task_id="", failed_uids, nodes)
      nodes_uids = nodes.select{ |n| failed_uids.include?(n['uid']) }
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

    def merge_rm_nodes_result(res1, res2)
      ['nodes', 'error_nodes', 'inaccessible_nodes'].inject({}) do |result, node_status|
        result[node_status] = (res1.fetch(node_status, []) + res2.fetch(node_status, [])).uniq
        result
      end
    end

    def change_nodes_type(reporter, task_id="", nodes)
      nodes_uids = nodes.map{ |n| n['uid'] }
      shell = MClient.new(Context.new(task_id, reporter),
                          'execute_shell_command',
                          nodes_uids,
                          check_result=false,
                          timeout=5)
      mco_result = shell.execute(:cmd => "echo 'image' > /etc/nailgun_systemtype")
      result = mco_result.map do |n|
        {
          'uid'       => n.results[:sender],
          'exit code' => n.results[:data][:exit_code]
        }
      end
      Astute.logger.debug "Change node type to image. Result: #{result}"
    end

    def handle_failed_nodes(failed_uids, result_msg)
      if failed_uids.present?
        Astute.logger.error("Provision of some nodes failed. Failed nodes: #{failed_uids}")
        nodes_progress = failed_uids.map do |n|
          {
            'uid' => n,
            'status' => 'error',
            'error_msg' => "Failed to provision",
            'progress' => 100,
            'error_type' => 'provision'
          }
        end
        result_msg['nodes'] += nodes_progress
      end
    end

    def  handle_timeouted_nodes(timeouted_uids, result_msg)
      if timeouted_uids.present?
        Astute.logger.error("Timeout of provisioning is exceeded. Nodes not booted: #{timeouted_uids}")
        nodes_progress = timeouted_uids.map do |n|
          {
            'uid' => n,
            'status' => 'error',
            'error_msg' => "Timeout of provisioning is exceeded",
            'progress' => 100,
            'error_type' => 'provision'
          }
        end
        result_msg['nodes'] += nodes_progress
      end
    end

    def should_fail(failed_uids, fault_tolerance)
      return failed_uids.present? if fault_tolerance.empty?

      fault_tolerance.each do |group|
        failed_from_group = failed_uids.select { |uid| group['uids'].include? uid }
        max_to_fail = group['percentage'] / 100.0 * group['uids'].count
        if failed_from_group.count > max_to_fail
          return true
        end
      end
      false
    end

    def check_ubuntu_repo_connectivity(nodes, task_id, reporter)
      ubuntu_nodes = nodes.select{|n| n['profile'] and n['profile'].include? 'ubuntu'}
      node_ids = ubuntu_nodes.map{|n| n['uid']}

      if ubuntu_nodes.empty?
        return
      end

      wget_timeout = 5

      shell = MClient.new(Context.new(task_id, reporter),
                          'execute_shell_command',
                          node_ids,
                          check_result=false,
                          timeout=wget_timeout*node_ids.length)

      # we are using first ubuntu nodes repo setup, because all nodes get their
      # repo config from fuel config for their cluster, so they all have same
      # repositories in them
      urls = ubuntu_nodes[0]['ks_meta']['repo_setup']['repos']
        .select{|r| r['type'] == 'deb'}
        .map{|n| [n['uri'], 'dists', n['suite'], 'Release'].map{|s| s.gsub(/^\/+|\/+$/, "")}.join('/')}

      command = "for i in '#{urls.join("' '")}'; do wget --timeout=5 $i || exit 1; done"

      mco_result = shell.execute(:cmd => command)

      result = mco_result.map do |n|
        {
          'uid'       => n.results[:sender],
          'exit code' => n.results[:data][:exit_code]
        }
      end

      if result.any?{|n| n['exit code'] != 0}
        failed_ids = result.select{|r| r['exit code'] != 0}.map{|r| r['uid']}
        failed_nodes = ubuntu_nodes.select{|n| failed_ids.include?(n['uid'].to_i)}

        error_message = "These nodes are unable to connect to Ubuntu repositories: #{failed_nodes.map{|n| n['slave_name']}.join(',')}"
        Astute.logger.error(error_message)
        raise error_message
      end
    end
  end
end
