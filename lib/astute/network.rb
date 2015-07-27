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

require 'erb'

module Astute
  module Network

    def self.check_network(ctx, nodes)
      if nodes.empty?
        Astute.logger.info(
          "#{ctx.task_id}: Network checker: nodes list is empty. Nothing to check.")
        return {
          'status' => 'error',
          'error' => "Network verification requires a minimum of two nodes."
        }
      elsif nodes.length == 1
        Astute.logger.info(
          "#{ctx.task_id}: Network checker: nodes list contains one node only. Do nothing.")
        return {'nodes' => [{
          'uid' => nodes[0]['uid'],
          'networks' => nodes[0]['networks']
        }]}
      end

      uids = nodes.map { |node| node['uid'].to_s }
      # TODO Everything breakes if agent not found. We have to handle that
      net_probe = MClient.new(ctx, "net_probe", uids)

      versioning = Versioning.new(ctx)
      old_version, new_version = versioning.split_on_version(uids, '6.1.0')

      old_uids = old_version.map { |node| node['uid'].to_i }
      new_uids = new_version.map { |node| node['uid'].to_i }
      old_nodes = nodes.select { |node| old_uids.include? node['uid'] }
      new_nodes = nodes.select { |node| new_uids.include? node['uid'] }

      if old_uids.present?
        start_frame_listeners_60(ctx, net_probe, old_nodes)
      end

      if new_uids.present?
        start_frame_listeners(ctx, net_probe, new_nodes)
      end
      ctx.reporter.report({'progress' => 30})

      if old_uids.present?
        send_probing_frames_60(ctx, net_probe, old_nodes)
      end

      if new_uids.present?
        send_probing_frames(ctx, net_probe, new_nodes)
      end
      ctx.reporter.report({'progress' => 60})

      net_probe.discover(:nodes => uids)
      stats = net_probe.get_probing_info
      result = format_result(stats)
      Astute.logger.debug "#{ctx.task_id}: Network checking is done. Results: #{result.inspect}"

      {'nodes' => result}
    end

    def self.check_dhcp(ctx, nodes)
      uids = nodes.map { |node| node['uid'].to_s }
      net_probe = MClient.new(ctx, "net_probe", uids)

      data_to_send = {}
      nodes.each do |node|
        data_to_send[node['uid'].to_s] = make_interfaces_to_send(node['networks'], joined=false).to_json
      end
      repeat = Astute.config.dhcp_repeat
      result = net_probe.dhcp_discover(:interfaces => data_to_send,
        :timeout => 10, :repeat => repeat).map do |response|
          format_dhcp_response(response)
      end

      {'nodes' => result, 'status'=> 'ready'}
    end

    def self.multicast_verification(ctx, nodes)
      uids = nodes.map { |node| node['uid'].to_s }
      net_probe = MClient.new(ctx, "net_probe", uids)
      data_to_send = {}
      nodes.each do |node|
        data_to_send[node['uid']] = node
      end

      listen_resp = net_probe.multicast_listen(:nodes => data_to_send.to_json)
      Astute.logger.debug("Mutlicast verification listen: #{listen_resp.inspect}")
      ctx.reporter.report({'progress' => 30})

      send_resp = net_probe.multicast_send()
      Astute.logger.debug("Mutlicast verification send: #{send_resp.inspect}")
      ctx.reporter.report({'progress' => 60})

      results = net_probe.multicast_info()
      Astute.logger.debug("Mutlicast verification info: #{results.inspect}")
      response = {}
      results.each do |node|
        if node.results[:data][:out].present?
          response[node.results[:sender].to_i] = JSON.parse(node.results[:data][:out])
        end
      end
      {'nodes' => response}
    end

    def self.check_urls_access(ctx, nodes, urls)
      uids = nodes.map { |node| node['uid'].to_s }
      net_probe = MClient.new(ctx, "net_probe", uids)

      result = net_probe.check_url_retrieval(:urls => urls)

      {'nodes' => flatten_response(result), 'status'=> 'ready'}
    end

    def self.check_repositories_with_setup(ctx, nodes)
      uids = nodes.map { |node| node['uid'].to_s }
      net_probe = MClient.new(ctx, "net_probe", uids, check_result=false)

      data = nodes.inject({}) { |h, node| h.merge({node['uid'].to_s => node}) }

      result = net_probe.check_repositories_with_setup(:data => data)
      bad_nodes = nodes.map { |n| n['uid'] } - result.map { |n| n.results[:sender] }

      if bad_nodes.present?
        error_msg = "Astute could not get result from nodes #{bad_nodes} " \
                    "in time (600 sec). Please check it manually:\n"
        error_msg += bad_nodes.inject("") do |cmd_list, uid|
          cmd_list << "Node #{uid}: urlaccesscheck with setup " \
            "-i #{data[uid]['iface']} " \
            "-g #{data[uid]['gateway']} " \
            " -a #{data[uid]['addr']} " \
            " --vlan #{data[uid]['vlan']} " \
            "'#{data[uid]['urls'].join("' '")}'\n"
        end
        raise MClientTimeout, ERB.new(error_msg).result
      end

      {'nodes' => flatten_response(result), 'status'=> 'ready'}
    end

    private
    def self.start_frame_listeners(ctx, net_probe, nodes)
      data_to_send = {}
      nodes.each do |node|
        data_to_send[node['uid'].to_s] = make_interfaces_to_send(node['networks'])
      end

      uids = nodes.map { |node| node['uid'].to_s }

      Astute.logger.debug(
        "#{ctx.task_id}: Network checker listen: nodes: #{uids} data: #{data_to_send.inspect}")

      net_probe.discover(:nodes => uids)
      net_probe.start_frame_listeners(:interfaces => data_to_send.to_json)
    end

    def self.send_probing_frames(ctx, net_probe, nodes)
      nodes.each_slice(Astute.config[:max_nodes_net_validation]) do |nodes_part|
        data_to_send = {}
        nodes_part.each do |node|
          data_to_send[node['uid'].to_s] = make_interfaces_to_send(node['networks'])
        end

        uids = nodes_part.map { |node| node['uid'].to_s }

        Astute.logger.debug(
          "#{ctx.task_id}: Network checker send: nodes: #{uids} data: #{data_to_send.inspect}")

        net_probe.discover(:nodes => uids)
        net_probe.send_probing_frames(:interfaces => data_to_send.to_json)
      end
    end

    def self.start_frame_listeners_60(ctx, net_probe, nodes)
      nodes.each do |node|
        data_to_send = make_interfaces_to_send(node['networks'])

        Astute.logger.debug(
          "#{ctx.task_id}: Network checker listen: node: #{node['uid']} data: #{data_to_send.inspect}")

        net_probe.discover(:nodes => [node['uid'].to_s])
        net_probe.start_frame_listeners(:interfaces => data_to_send.to_json)
      end
    end

    def self.send_probing_frames_60(ctx, net_probe, nodes)
      nodes.each do |node|
        data_to_send = make_interfaces_to_send(node['networks'])

        Astute.logger.debug(
          "#{ctx.task_id}: Network checker send: node: #{node['uid']} data: #{data_to_send.inspect}")

        net_probe.discover(:nodes => [node['uid'].to_s])
        net_probe.send_probing_frames(:interfaces => data_to_send.to_json)
      end
    end

    def self.make_interfaces_to_send(networks, joined=true)
      data_to_send = {}
      networks.each do |network|
        if joined
          data_to_send[network['iface']] = network['vlans'].join(",")
        else
          data_to_send[network['iface']] = network['vlans']
        end
      end

      data_to_send
    end

    def self.format_dhcp_response(response)
      node_result = {:uid => response.results[:sender],
                     :status=>'ready'}
      if response.results[:data][:out].present?
        Astute.logger.debug("DHCP checker received: #{response.inspect}")
        node_result[:data] = JSON.parse(response.results[:data][:out])
      elsif response.results[:data][:error].present?
        Astute.logger.debug("DHCP checker errred with: #{response.inspect}")
        node_result[:status] = 'error'
        node_result[:error_msg] = 'Error in dhcp checker. Check logs for details'
      end
      node_result
    end

    def self.format_result(stats)
      uids = stats.map{|node| node.results[:sender]}.sort
      stats.map do |node|
        {
          'uid' => node.results[:sender],
          'networks' => check_vlans_by_traffic(
            node.results[:sender],
            uids,
            node.results[:data][:neighbours])
        }
      end
    end

    def self.flatten_response(response)
      response.map do |node|
        {:out => node.results[:data][:out],
         :err => node.results[:data][:err],
         :status => node.results[:data][:status],
         :uid => node.results[:sender]}
      end
    end

    def self.check_vlans_by_traffic(uid, uids, data)
      data.map do |iface, vlans|
        {
          'iface' => iface,
          'vlans' => remove_extra_data(uid, uids, vlans).select {|k,v|
              v.keys.present?
             }.keys.map(&:to_i)
        }
      end
    end

    # Remove unnecessary data
    def self.remove_extra_data(uid, uids, vlans)
      vlans.each do |k, data|
        # remove data sent by node itself
        data.delete(uid)
        # remove data sent by nodes from different envs
        data.keep_if { |k, v| uids.include?(k) }
      end
      vlans
    end

  end
end

