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
  class DeploymentEngine
    def initialize(context)
      if self.class.superclass.name == 'Object'
        raise "Instantiation of this superclass is not allowed. Please subclass from #{self.class.name}."
      end
      @ctx = context
    end

    def deploy(nodes, attrs)
      # See implementation in subclasses, this may be everriden
      attrs['deployment_mode'] ||= 'multinode'  # simple multinode deployment is the default
      attrs['use_cinder'] ||= nodes.any?{|n| n['role'] == 'cinder'}
      @ctx.deploy_log_parser.deploy_type = attrs['deployment_mode']
      Astute.logger.info "Deployment mode #{attrs['deployment_mode']}"
      result = self.send("deploy_#{attrs['deployment_mode']}", nodes, attrs)
    end

    def method_missing(method, *args)
      Astute.logger.error "Method #{method} is not implemented for #{self.class}, raising exception."
      raise "Method #{method} is not implemented for #{self.class}"
    end

    # we mix all attrs and prepare them for Puppet
    # Works for multinode deployment mode
    def attrs_multinode(nodes, attrs)
      attrs['nodes'] = nodes.map do |n|
        {
          'fqdn'                 => n['fqdn'],
          'name'                 => n['fqdn'].split(/\./)[0],
          'role'                 => n['role'],
          'internal_address'     => n['network_data'].select {|nd| select_ifaces(nd['name'], 'management')}[0]['ip'].split(/\//)[0],
          'internal_br'          => n['internal_br'],
          'internal_netmask'     => n['network_data'].select {|nd| select_ifaces(nd['name'], 'management')}[0]['netmask'],
          'storage_address'      => n['network_data'].select {|nd| select_ifaces(nd['name'], 'storage')}[0]['ip'].split(/\//)[0],
          'storage_netmask'      => n['network_data'].select {|nd| select_ifaces(nd['name'], 'storage')}[0]['netmask'],
          'public_address'       => n['network_data'].select {|nd| select_ifaces(nd['name'], 'public')}[0]['ip'].split(/\//)[0],
          'public_br'            => n['public_br'],
          'public_netmask'       => n['network_data'].select {|nd| select_ifaces(nd['name'], 'public')}[0]['netmask'],
          'default_gateway'      => n['default_gateway']
        }
      end
      # TODO(mihgen): we should report error back if there are not enough metadata passed
      attrs
    end

    # This method is called by Ruby metaprogramming magic from deploy method
    # It should not contain any magic with attributes, and should not directly run any type of MC plugins
    # It does only support of deployment sequence. See deploy_piece implementation in subclasses.
    def deploy_multinode(nodes, attrs)
      ctrl_nodes = nodes.select {|n| n['role'] == 'controller'}
      other_nodes = nodes - ctrl_nodes

      Astute.logger.info "Starting deployment of primary controller"
      deploy_piece(ctrl_nodes, attrs)

      Astute.logger.info "Starting deployment of other nodes"
      deploy_piece(other_nodes, attrs)

      return
    end

    def attrs_ha(nodes, attrs)
      # we use the same set of mount points for all storage nodes
      attrs['mp'] = [{'point' => '1', 'weight' => '1'},{'point'=>'2','weight'=>'2'}]
      mountpoints = ""
      attrs['mp'].each do |mountpoint|
        mountpoints << "#{mountpoint['point']} #{mountpoint['weight']}\n"
      end

      Astute.logger.debug("#{nodes}")
      attrs['nodes'] = nodes.map do |n|
        {
          'fqdn'                 => n['fqdn'],
          'name'                 => n['fqdn'].split(/\./)[0],
          'role'                 => n['role'],
          'mountpoints'          => mountpoints,
          'internal_address'     => n['network_data'].select {|nd| select_ifaces(nd['name'], 'management')}[0]['ip'].split(/\//)[0],
          'internal_br'          => n['internal_br'],
          'internal_netmask'     => n['network_data'].select {|nd| select_ifaces(nd['name'], 'management')}[0]['netmask'],
          'public_address'       => n['network_data'].select {|nd| select_ifaces(nd['name'], 'public')}[0]['ip'].split(/\//)[0],
          'public_br'            => n['public_br'],
          'public_netmask'       => n['network_data'].select {|nd| select_ifaces(nd['name'], 'public')}[0]['netmask'],
          'swift_zone'           => n['id'],
          'storage_address'      => n['network_data'].select {|nd| select_ifaces(nd['name'], 'storage')}[0]['ip'].split(/\//)[0],
          'storage_netmask'      => n['network_data'].select {|nd| select_ifaces(nd['name'], 'storage')}[0]['netmask'],
          'default_gateway'      => n['default_gateway']
        }
      end

      if attrs['nodes'].select { |node| node['role'] == 'primary-controller' }.empty?
        ctrl_nodes = attrs['nodes'].select {|n| n['role'] == 'controller'}
        ctrl_nodes[0]['role'] = 'primary-controller'
      end

      attrs
    end

    alias :attrs_ha_full  :attrs_ha
    alias :attrs_ha_compact :attrs_ha

    def deploy_ha_full(nodes, attrs)
      primary_ctrl_nodes = nodes.select {|n| n['role'] == 'primary-controller'}
      ctrl_nodes = nodes.select {|n| n['role'] == 'controller'}
      compute_nodes = nodes.select {|n| n['role'] == 'compute'}
      quantum_nodes = nodes.select {|n| n['role'] == 'quantum'}
      storage_nodes = nodes.select {|n| n['role'] == 'storage'}
      proxy_nodes = nodes.select {|n| n['role'] == 'swift-proxy'}
      primary_proxy_nodes = nodes.select {|n| n['role'] == 'primary-swift-proxy'}
      other_nodes = nodes - ctrl_nodes - primary_ctrl_nodes - \
        primary_proxy_nodes - quantum_nodes - storage_nodes - proxy_nodes

      Astute.logger.info "Starting deployment of primary swift proxy"
      deploy_piece(primary_proxy_nodes, attrs)

      Astute.logger.info "Starting deployment of non-primary swift proxies"
      deploy_piece(proxy_nodes, attrs)

      Astute.logger.info "Starting deployment of swift storages"
      deploy_piece(storage_nodes, attrs)

      Astute.logger.info "Starting deployment of primary controller"
      deploy_piece(primary_ctrl_nodes, attrs)

      Astute.logger.info "Starting deployment of all controllers one by one"
      ctrl_nodes.each {|n| deploy_piece([n], attrs)}

      Astute.logger.info "Starting deployment of other nodes"
      deploy_piece(other_nodes, attrs)
      return
    end

    def deploy_ha_compact(nodes, attrs)
      primary_ctrl_nodes = nodes.select {|n| n['role'] == 'primary-controller'}
      ctrl_nodes = nodes.select {|n| n['role'] == 'controller'}
      compute_nodes = nodes.select {|n| n['role'] == 'compute'}
      quantum_nodes = nodes.select {|n| n['role'] == 'quantum'}
      storage_nodes = nodes.select {|n| n['role'] == 'storage'}
      proxy_nodes = nodes.select {|n| n['role'] == 'swift-proxy'}
      primary_proxy_nodes = nodes.select {|n| n['role'] == 'primary-swift-proxy'}
      other_nodes = nodes - ctrl_nodes - primary_ctrl_nodes - \
        primary_proxy_nodes - quantum_nodes

      #FIXME: add last_controller attribute to attributes hash in order to determine
      #if we are the last controller in deployment sequence and it is safe to
      #upload test virtual machine image

      last_controller = ctrl_nodes.last
      if last_controller['name']
        attrs['last_controller'] = last_controller['name']
      elsif last_controller['fqdn']
        attrs['last_controller'] = last_controller['fqdn'].split(/\./)[0]
      end

      Astute.logger.info "Starting deployment of primary controller"
      deploy_piece(primary_ctrl_nodes, attrs)

      Astute.logger.info "Starting deployment of all controllers one by one"
      ctrl_nodes.each {|n| deploy_piece([n], attrs)}

      Astute.logger.info "Starting deployment of other nodes"
      deploy_piece(other_nodes, attrs)
      return
    end

    alias :deploy_ha :deploy_ha_compact

    def attrs_rpmcache(nodes, attrs)
      attrs
    end

    def deploy_rpmcache(nodes, attrs)
      Astute.logger.info "Starting release downloading"
      deploy_piece(nodes, attrs, 0)
    end

    private
    def select_ifaces(var,name)
        result = false
        if var.is_a?(Array)
            result = true if var.include?(name)
        elsif var.is_a?(String)
            result = true if var == name
        end
    end

    def nodes_status(nodes, status, data_to_merge)
      {'nodes' => nodes.map { |n| {'uid' => n['uid'], 'status' => status}.merge(data_to_merge) }}
    end

    def validate_nodes(nodes)
      if nodes.empty?
        Astute.logger.info "#{@ctx.task_id}: Nodes to deploy are not provided. Do nothing."
        return false
      end
      return true
    end

    def calculate_networks(data, hwinterfaces)
      interfaces = {}
      data ||= []
      Astute.logger.info "calculate_networks function was provided with #{data.size} interfaces"
      data.each do |net|
        Astute.logger.debug "Calculating network for #{net.inspect}"
        if net['vlan'] && net['vlan'] != 0
          name = [net['dev'], net['vlan']].join('.')
        else
          name = net['dev']
        end
        unless interfaces.has_key?(name)
          interfaces[name] = {'interface' => name, 'ipaddr' => []}
        end
        iface = interfaces[name]
        if net['name'] == 'admin'
          if iface['ipaddr'].size > 0
            Astute.logger.error "Admin network interferes with openstack nets"
          end
          iface['ipaddr'] += ['dhcp']
        else
          if iface['ipaddr'].any?{|x| x == 'dhcp'}
            Astute.logger.error "Admin network interferes with openstack nets"
          end
          if net['ip']
            iface['ipaddr'] += [net['ip']]
          end
          if net['gateway'] && net['name'] =~ /^public$/i
            iface['gateway'] = net['gateway']
          end
        end
        Astute.logger.debug "Calculated network for interface: #{name}, data: #{iface.inspect}"
      end
      interfaces['lo'] = {'interface'=>'lo', 'ipaddr'=>['127.0.0.1/8']} unless interfaces.has_key?('lo')
      hwinterfaces.each do |i|
        unless interfaces.has_key?(i['name'])
          interfaces[i['name']] = {'interface' => i['name'], 'ipaddr' => []}
        end
      end
      interfaces.keys.each do |i|
        interfaces[i]['ipaddr'] = 'none' if interfaces[i]['ipaddr'].size == 0
        interfaces[i]['ipaddr'] = 'dhcp' if interfaces[i]['ipaddr'] == ['dhcp']
      end
      interfaces
    end
  end
end
