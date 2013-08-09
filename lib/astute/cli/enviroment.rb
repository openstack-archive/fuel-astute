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

require 'yaml'
require 'json'
require 'rest-client'
require 'astute/ext/hash'
require 'astute/cli/enviroment'
require 'astute/cli/yaml_validator'

module Astute
  module Cli
    
    class Enviroment
      
      POWER_INFO_KEYS       = ['power_type', 'power_user', 'power_pass', 'netboot_enabled']
      ID_KEYS               = ['id', 'uid']
      COMMON_NODE_KEYS      = ['name_servers']
      KS_META_KEYS          = ['mco_enable', 'mco_vhost', 'mco_pskey', 'mco_user', 'puppet_enable',
                               'install_log_2_syslog', 'mco_password', 'puppet_auto_setup', 'puppet_master',
                               'mco_auto_setup', 'auth_key', 'puppet_version', 'mco_connector', 'mco_host']
      PROVISIONING_NET_KEYS = ['ip', 'power_address', 'mac', 'fqdn']
      
      def initialize(file)
        @config = YAML.load_file(file)
        response = RestClient.get 'http://localhost:8000/api/nodes'
        @api_data = JSON.parse(response).freeze
        to_full_config
      end
      
      def [](key)
        @config[key]
      end
  
      private
      
      def to_full_config
        validate_enviroment
        
        # Provision section
        @config['nodes'].each do |node|
          define_provisioning_network(node)
          define_id_and_uid(node)
          define_interfaces_and_interfaces_extra(node)
          define_ks_spaces(node)
          define_power_info(node)
          define_ks_meta(node)
          define_node_settings(node)
        end
        # Deploy section
      end
      
      
      def validate_enviroment
        validator = YamlValidator.new
        errors = validator.validate(@config)
      
        errors.each do |e|
          title = e.message.include?("is undefined") ? "WARNING" : "ERROR"
          puts "#{title}: [#{e.path}] #{e.message}"
        end
        
        if errors.select {|e| !e.message.include?("is undefined") }.size > 0
          raise Enviroment::ValidationError, "Environment validation failed"
        end
      end
      
      # Set for node uniq id and uid from Nailgun
      def define_id_and_uid(node)
        begin
          id = @api_data.find{ |n| n['mac'].upcase == node['mac'].upcase }['id']
        rescue
          raise Enviroment::ValidationError, "Node #{node['name']} with mac adress #{node['mac']}
                                              not find among discovered nodes"
        end
        
        # This params set for node by Nailgun and should not be edit by user
        node.merge!(
          'id'  => id,
          'uid' => id
        )
      end
      
      def define_parameters(node, config_group_name, keys, position=nil)
        position ||= node
        if @config[config_group_name]
          config_group = @config[config_group_name]
          keys.each do |key|
            position.reverse_merge!(key => config_group[key])
          end
        end
        
        absent_keys = position.absent_keys(keys)
        if !absent_keys.empty?
          raise Enviroment::ValidationError, "Please set #{config_group_name} block or 
                set params for #{node['name']} manually #{absent_keys.each {|k| p k}}"
        end
        @config.delete(config_group)
      end
      
      # Add common params from common_node_settings to every node. Already certain parameters will not be changed.
      def define_node_settings(node)
        define_parameters(node, 'common_node_settings', COMMON_NODE_KEYS)
      end
      
      # Add common params from common_power_info to every node. Already certain parameters will not be changed.
      def define_power_info(node)
        define_parameters(node, 'common_power_info', POWER_INFO_KEYS)
      end
      
      # Add common params from common_ks_meta to every node. Already certain parameters will not be changed.
      def define_ks_meta(node)
        define_parameters(node, 'common_ks_meta', KS_META_KEYS, node['ks_meta'])
      end
      
      # Add duplicates params to node: ip, power_address, mac, fqdn
      def define_provisioning_network(node)
        provision_eth = node['interfaces'].find {|eth| eth['use_for_provision'] } rescue nil
        
        if provision_eth
          if provision_eth.absent?('ip_address')
            api_node = @api_data.find{ |n| n['mac'].upcase == provision_eth['mac_address'].upcase }
            api_provision_eth = api_node['meta']['interfaces'].find { |n| n['mac'].upcase == provision_eth['mac_address'].upcase }
            provision_eth['ip_address'] = api_provision_eth['ip'] 
            provision_eth['netmask'] = api_provision_eth['netmask']
          end

          #define_parameters(node, 'use_for_provision', PROVISIONING_NET_KEYS)
          
          node.reverse_merge!(
            'ip'            => provision_eth['ip_address'],
            'power_address' => provision_eth['ip_address'],
            'mac'           => provision_eth['mac_address'],
            'fqdn'          => provision_eth['dns_name']
          )
          provision_eth.delete('use_for_provision')
        end
          
      
        absent_keys = node.absent_keys(PROVISIONING_NET_KEYS)
        if !absent_keys.empty?
          raise "Please set 'use_for_provision' parameter for #{node['name']}
                 or set manually #{absent_keys.each {|k| p k}}"
        end
      end
    
      # Extend blocks interfaces and interfaces_extra to old formats:
      # interfaces:
      #   eth0:
      #     ip_address: 10.20.0.188
      #     netmask: 255.255.255.0
      #     dns_name: *fqdn
      #     static: '0'
      #     mac_address: 08:00:27:C2:06:DE
      # interfaces_extra:
      #   eth0:
      #     onboot: 'yes'
      #     peerdns: 'no'
      def define_interfaces_and_interfaces_extra(node)
        return if [node['interfaces'], node['extra_interfaces']].all? {|i| i.is_a?(Hash)}
      
        formated_interfaces = {}
        interfaces_extra_interfaces = {}
        node['interfaces'].each do |eth|
          formated_interfaces[eth['name']] = eth
          interfaces_extra_interfaces[eth['name']] = {
            'onboot'  => eth['onboot'], 
            'peerdns' => eth['onboot']
          }
        end
        node['interfaces'] = formated_interfaces
        node['extra_interfaces'] = interfaces_extra_interfaces  
      end
  
      # Generate 'ks_spaces' param from 'ks_disks' param in section 'ks_meta' 
      # Example input for 'ks_disks' param: 
      # [{
      #   "type"=>"disk", 
      #   "id"=>"disk/by-path/pci-0000:00:0d.0-scsi-0:0:0:0",
      #   "size"=>16384, 
      #   "volumes"=>[
      #     {
      #       "type"=>"boot", 
      #       "size"=>300
      #     }, 
      #     {
      #       "type"=>"pv", 
      #       "size"=>16174, 
      #       "vg"=>"os"
      #     }
      #   ]
      # }]
      # Example result for 'ks_spaces' param: "[{"type": "disk", "id": "disk/by-path/pci-0000:00:0d.0-scsi-0:0:0:0", "volumes": [{"type": "boot", "size": 300}, {"mount": "/boot", "type": "raid", "size": 200}, {"type": "lvm_meta", "name": "os", "size": 64}, {"size": 11264, "type": "pv", "vg": "os"}, {"type": "lvm_meta", "name": "image", "size": 64}, {"size": 4492, "type": "pv", "vg": "image"}], "size": 16384}]"
      def define_ks_spaces(node)
        if node['ks_meta'].present? 'ks_spaces'
          node['ks_meta'].delete('ks_disks')
          return
        end
    
        if node['ks_meta'].absent? 'ks_disks'
          raise "Please set 'ks_disks' or 'ks_spaces' parameter in section ks_meta for #{node['name']}"
        end
    
        node['ks_meta']['ks_spaces'] = '"' + node['ks_meta']['ks_disks'].to_json.gsub("\"", "\\\"") + '"'
        node['ks_meta'].delete('ks_disks')
      end
    end # class end
    
    class Enviroment::ValidationError < StandardError; end
    
  end # module Cli
end