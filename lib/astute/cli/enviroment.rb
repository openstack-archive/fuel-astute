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
require 'rest-client'
require 'astute/ext/hash'
require 'astute/cli/enviroment'
require 'astute/cli/yaml_validator'

module Astute
  module Cli
    
    class Enviroment
      
      POWER_INFO_KEYS       = ['power_type', 'power_user', 'power_pass', 'netboot_enabled']
      ID_KEYS               = ['id', 'uid']
      COMMON_NODE_KEYS      = ['name_servers', 'profile']
      KS_META_KEYS          = ['mco_enable', 'mco_vhost', 'mco_pskey', 'mco_user', 'puppet_enable',
                               'install_log_2_syslog', 'mco_password', 'puppet_auto_setup', 'puppet_master',
                               'mco_auto_setup', 'auth_key', 'puppet_version', 'mco_connector', 'mco_host']
      NETWORK_KEYS          = ['ip', 'mac', 'fqdn']
      PROVISIONING_NET_KEYS = ['power_address']
      PROVISION_OPERATIONS  = [:provision]
      
      CIDR_REGEXP = '^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|
                    2[0-4][0-9]|25[0-5])(\/(\d|[1-2]\d|3[0-2]))$'
      
      def initialize(file, operation)
        @config = YAML.load_file(file)
        validate_enviroment(operation)
        to_full_config(operation)
      end
      
      def [](key)
        @config[key]
      end
  
      private
      
      def to_full_config(operation)
        @config['nodes'].each do |node|
        
          # Common section
          define_id_and_uid(node)
        
          # Provision section
          if PROVISION_OPERATIONS.include? operation
            node['meta'] ||= {}
            define_network_ids(node)
            define_power_address(node)
            define_interfaces_and_interfaces_extra(node)
            define_ks_spaces(node)
            define_power_info(node)
            define_ks_meta(node)
            define_node_settings(node)
            define_disks_section(node)
          end
        end
      end
      
      def validate_enviroment(operation)
        validator = YamlValidator.new(operation)
        errors = validator.validate(@config)
      
        errors.each do |e|
          if e.message.include?("is undefined")
            Astute.logger.warn "[#{e.path}] #{e.message}"
          else
            Astute.logger.error "[#{e.path}] #{e.message}"
            $stderr.puts "[#{e.path}] #{e.message}"
          end
        end
        
        if errors.select {|e| !e.message.include?("is undefined") }.size > 0
          raise Enviroment::ValidationError, "Environment validation failed"
        end
      end
      
      # Get data about discovered nodes using FuelWeb API 
      def find_node_api_data(node)
        @api_data ||= begin
          response = RestClient.get 'http://localhost:8000/api/nodes'
          @api_data = JSON.parse(response).freeze
        end
        if node['mac']
         api_node = @api_data.find{ |n| n['mac'].upcase == node['mac'].upcase }
         return api_node if api_node
        end
        raise Enviroment::ValidationError, "Node #{node['name']} with mac address #{node['mac']}
                                            not find among discovered nodes"
      end
      
      # Set uniq id and uid for node from Nailgun using FuelWeb API
      def define_id_and_uid(node)
        id = find_node_api_data(node)['id']
        
        # This params set for node by Nailgun and should not be edit by user
        node.merge!(
          'id'  => id,
          'uid' => id
        )
      end
      
      # Set meta/disks section for node. This data used in provision to calculate the percentage 
      # completion of the installation process.
      # Example result for node['meta']
      # "disks": [
      #   {
      #     "model": "VBOX HARDDISK", 
      #     "disk": "disk/by-path/pci-0000:00:0d.0-scsi-0:0:0:0", 
      #     "name": "sda", 
      #     "size": 17179869184
      #   }...
      # ]
      def define_disks_section(node)
        node['meta']['disks'] = find_node_api_data(node)['meta']['disks']
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
      
      # Add duplicates network params to node: ip, mac, fqdn
      def define_network_ids(node)
        network_eth = node['interfaces'].find {|eth| eth['use_for_provision'] } rescue nil

        if network_eth
          if network_eth['ip_address'].blank?
            node['mac'] = network_eth['mac_address']
            api_node = find_node_api_data(node)
            api_provision_eth = api_node['meta']['interfaces'].find { |n| n['mac'].to_s.upcase == network_eth['mac_address'].to_s.upcase }
            network_eth['ip_address'] = api_provision_eth['ip'] 
            network_eth['netmask'] = api_provision_eth['netmask']
          end
          
          node.reverse_merge!(
            'ip'            => network_eth['ip_address'],
            'mac'           => network_eth['mac_address'],
            'fqdn'          => network_eth['dns_name']
          )
          network_eth.delete('use_for_provision')
        end
        
        absent_keys = node.absent_keys(NETWORK_KEYS)
        if !absent_keys.empty?
          raise Enviroment::ValidationError, "Please set 'use_for_provision' parameter 
                for #{node['name']} or set manually #{absent_keys.each {|k| p k}}"
        end
      end
      
       # Add duplicates network params to node: power_address
      def define_power_address(node)
        node['power_address'] = node['ip'] or raise Enviroment::ValidationError, "Please 
                                set 'power_address' parameter for #{node['name']}"
      end
    
      # Extend blocks interfaces and interfaces_extra to old formats:
      # interfaces:
      #   eth0:
      #     ip_address: 10.20.0.188
      #     netmask: 255.255.255.0
      #     dns_name: controller-22.domain.tld
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
          formated_interfaces[eth['name']].delete('name')
          interfaces_extra_interfaces[eth['name']] = {
            'onboot'  => eth['onboot'], 
            'peerdns' => eth['onboot']
          }
        end
        node['interfaces'] = formated_interfaces
        node['extra_interfaces'] = interfaces_extra_interfaces  
      end
      
      # Add duplicate param 'fqdn' to node if it is not specified
      def define_fqdn(node)
        node['fqdn'] ||= find_node_api_data(node)['meta']['system']['fqdn']
      end
      
      # Add meta/interfaces section for node:
      # meta:
      #   interfaces:
      #   - name: eth0
      #     ip: 10.20.0.95
      #     netmask: 255.255.255.0
      #     mac: 08:00:27:C2:06:DE
      #     max_speed: 100
      #     current_speed: 100
      def define_meta_interfaces(node)   
        node['meta']['interfaces'] = find_node_api_data(node)['meta']['interfaces']
      end
      
      # Add network_data section for node:
      # network_data:
      #   - dev: eth1
      #     ip: 10.108.1.8
      #     name: public
      #     netmask: 255.255.255.0
      #   - dev: eth0
      #     ip: 10.108.0.8
      #     name:
      #     - management
      #     - storage
      def define_network_data(node)
        return if node['network_data'].is_a?(Array) && !node['network_data'].empty?
        
        node['network_data'] = []
        
        # If define_interfaces_and_interfaces_extra was call or format of config is full
        if node['interfaces'].is_a?(Hash)
          node['interfaces'].each do |key, value|
            node['network_data'] << {
                'dev'     => key,
                'ip'      => value['ip_address'],
                'name'    => value['network_name'],
                'netmask' => value['netmask']
            }
          end
        else
          node['interfaces'].each do |eth|
            node['network_data'] << {
                'dev'     => eth['name'],
                'ip'      => eth['ip_address'],
                'name'    => eth['network_name'],
                'netmask' => eth['netmask']
            }
          end
        end
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
        if node['ks_meta']['ks_spaces'].present?
          node['ks_meta'].delete('ks_disks')
          return
        end
    
        if node['ks_meta']['ks_disks'].blank?
          raise Enviroment::ValidationError, "Please set 'ks_disks' or 'ks_spaces' parameter 
                in section ks_meta for #{node['name']}"
        end
    
        node['ks_meta']['ks_spaces'] = '"' + node['ks_meta']['ks_disks'].to_json.gsub("\"", "\\\"") + '"'
        node['ks_meta'].delete('ks_disks')
      end
      
      def is_cidr_notation?(value)
        cidr = Regexp.new(CIDR_REGEXP)
        !cidr.match(value).nil?
      end
      
    end # class end
    
    class Enviroment::ValidationError < StandardError; end
    
  end # module Cli
end
