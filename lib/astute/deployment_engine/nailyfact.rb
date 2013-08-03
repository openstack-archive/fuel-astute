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


class Astute::DeploymentEngine::NailyFact < Astute::DeploymentEngine

  def deploy(nodes, attrs)
    attrs_for_mode = self.send("attrs_#{attrs['deployment_mode']}", nodes, attrs)
    super(nodes, attrs_for_mode)
  end

  def create_facts(node, attrs)
    # calculate_networks method is common and you can find it in superclass
    # if node['network_data'] is undefined, we use empty list because we later try to iterate over it
    #   otherwise we will get KeyError
    node_network_data = node['network_data'].nil? ? [] : node['network_data']
    interfaces = node['meta']['interfaces']
    network_data_puppet = calculate_networks(node_network_data, interfaces)
    attrs_to_puppet = {
      'role' => node['role'],
      'uid'  => node['uid'],
      'network_data' => network_data_puppet.to_json
    }

    # Let's calculate interface settings we need for OpenStack:
    node_network_data.each do |iface|
      device = if iface['vlan'] && iface['vlan'] > 0
        [iface['dev'], iface['vlan']].join('.')
      else
        iface['dev']
      end

      if iface['name'].is_a?(String)
        attrs_to_puppet["#{iface['name']}_interface"] = device
      elsif iface['name'].is_a?(Array)
       iface['name'].each do |name|
         attrs_to_puppet["#{name}_interface"] = device
       end
      end
    end

    if attrs['novanetwork_parameters']['network_manager'] == 'VlanManager' && !attrs_to_puppet['fixed_interface']
      attrs_to_puppet['fixed_interface'] = get_fixed_interface(node)
    end

    attrs_to_puppet.merge!(attrs)

    attrs_to_puppet.each do |k, v|
      unless v.is_a?(String)
        attrs_to_puppet[k] = v.to_json
      end
    end

    attrs_to_puppet
  end

  def deploy_piece(nodes, attrs, retries=2, change_node_status=true)
    return false unless validate_nodes(nodes)
    @ctx.reporter.report nodes_status(nodes, 'deploying', {'progress' => 0})

    Astute.logger.info "#{@ctx.task_id}: Calculation of required attributes to pass, include netw.settings"
    nodes.each do |node|
      # Use predefined facts or create new.
      node['facts'] ||= create_facts(node, attrs)
      Astute::Metadata.publish_facts(@ctx, node['uid'], node['facts'])
    end
    Astute.logger.info "#{@ctx.task_id}: All required attrs/metadata passed via facts extension. Starting deployment."

    Astute::PuppetdDeployer.deploy(@ctx, nodes, retries, change_node_status)
    nodes_roles = nodes.map { |n| { n['uid'] => n['role'] } }
    Astute.logger.info "#{@ctx.task_id}: Finished deployment of nodes => roles: #{nodes_roles.inspect}"
  end

  private
  def get_fixed_interface(node)
    return node['vlan_interface'] if node['vlan_interface']

    Astute.logger.warn "Can not find vlan_interface for node #{node['uid']}"
    nil
  end

end
