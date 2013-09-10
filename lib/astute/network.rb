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

      start_frame_listeners(ctx, net_probe, nodes)
      ctx.reporter.report({'progress' => 30})

      send_probing_frames(ctx, net_probe, nodes)
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
      result = []
      nodes.each do |node|
        data_to_send = make_interfaces_to_send(node['networks'], joined=false).to_json
        net_probe.discover(:nodes => [node['uid'].to_s])
        response = net_probe.dhcp_discover(:interfaces => data_to_send)
        node_result = {:uid => response[0][:sender],
                       :status=>'ready'}
        if response[0][:data].has_key?(:out) and not response[0][:data][:out].empty?
          Astute.logger.debug("DHCP checker received: node: #{node['uid']} response: #{response}")
          node_result[:data] = JSON.parse(response[0][:data][:out])
        elsif response[0][:data].has_key?(:error) and not response[0][:data][:error].empty?
          node_result[:status] = 'error'
          node_result[:error_msg] = 'Error in dhcp checker. Check logs for details'
        end
        result << node_result
      end
      {'nodes' => result}
    end

    private
    def self.start_frame_listeners(ctx, net_probe, nodes)
      nodes.each do |node|
        data_to_send = make_interfaces_to_send(node['networks'])

        Astute.logger.debug(
          "#{ctx.task_id}: Network checker listen: node: #{node['uid']} data: #{data_to_send.inspect}")

        net_probe.discover(:nodes => [node['uid'].to_s])
        net_probe.start_frame_listeners(:interfaces => data_to_send.to_json)
      end
    end

    def self.send_probing_frames(ctx, net_probe, nodes)
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

    def self.format_result(stats)
      uids = stats.map{|node| node.results[:sender]}.sort
      stats.map do |node|
        {
          'uid' => node.results[:sender],
          'networks' => check_vlans_by_traffic(
            uids,
            node.results[:data][:neighbours])
        }
      end
    end


    def self.check_vlans_by_traffic(uids, data)
      data.map do |iface, vlans|
        {
          'iface' => iface,
          'vlans' => vlans.reject{ |k, v|
            v.keys.sort != uids
          }.keys.map(&:to_i)
        }
      end
    end

  end
end
