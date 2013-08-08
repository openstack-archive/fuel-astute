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
require 'astute/ext/hash'
require 'astute/cli/enviroment'
require 'astute/cli/yaml_validator'

module Astute
  module Cli
    
    class Enviroment
      
      def initialize(file)
        @config = YAML.load_file(file)
        validate_env
        convert_to_full_conf
      end
      
      def [](key)
        @config[key]
      end
    
      def validate_env
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
      
      def convert_to_full_conf
        # Provision section
        @config['nodes'].each_with_index do |node, index|
          node.reverse_merge!(
            'id'  => index,
            'uid' => index
          )
        
          define_provision_network(node)
          define_interfaces_and_interfaces_extra(node)
          define_ks_spaces(node)
          define_power_info(node)
          define_ks_meta(node)
          define_node_settings(node)
        end
        # Deploy section
      end
  
      private
      
      # Add common params from common_node_settings to every node. Already certain parameters will not be changed.
      def define_node_settings(node)
        if @config['common_node_settings']
          meta = @config['common_node_settings']
          params = ['name_servers']
            
          params.each {|param| node.reverse_merge!(param => meta[param]) } 
        end
        
        absent_keys = node.absent_keys(params)
        if !absent_keys.empty?
          raise Enviroment::ValidationError, "Please set 'common_node_settings' block or 
                set params for #{node['name']} manually #{absent_keys.each {|k| p k}}"
        end
        @config.delete('common_node_settings')
      end
      
      
      # Add common params from common_power_info to every node. Already certain parameters will not be changed.
      def define_power_info(node)
        if @config['common_power_info']
          power_info = @config['common_power_info']
          node.reverse_merge!(
            'power_type'      => power_info['power_type'],
            'power_user'      => power_info['power_user'],
            'power_pass'      => power_info['power_pass'],
            'netboot_enabled' => power_info['netboot_enabled']
          )
        end
        
        absent_keys = node.absent_keys(['power_type', 'power_user', 'power_pass', 'netboot_enabled'])
        if !absent_keys.empty?
          raise Enviroment::ValidationError, "Please set 'common_power_info' block or 
                set params for #{node['name']} manually #{absent_keys.each {|k| p k}}"
        end
        @config.delete('common_power_info')
      end
      
      # Add common params from common_ks_meta to every node. Already certain parameters will not be changed.
      def define_ks_meta(node)
        if @config['common_ks_meta']
          ks_meta = @config['common_ks_meta']
          params = ['mco_enable', 'mco_vhost', 'mco_pskey', 'mco_user', 'puppet_enable',
            'install_log_2_syslog', 'mco_password', 'puppet_auto_setup', 'puppet_master',
            'mco_auto_setup', 'auth_key', 'puppet_version', 'mco_connector', 'mco_host']
            
          params.each {|param| node['ks_meta'].reverse_merge!(param => ks_meta[param]) } 
        end
        
        absent_keys = node['ks_meta'].absent_keys(params)
        if !absent_keys.empty?
          raise Enviroment::ValidationError, "Please set 'common_ks_meta' block or 
                set params for #{node['name']} manually #{absent_keys.each {|k| p k}}"
        end
        @config.delete('common_ks_meta')
      end
      
      # Add duplicates params to node: ip, power_address, mac, fqdn
      def define_provision_network(node)
        provision_eth = node['interfaces'].find {|eth| eth['use_for_provision'] } rescue nil
    
        if provision_eth
          node.reverse_merge!(
            'ip'            => provision_eth['ip_address'],
            'power_address' => provision_eth['ip_address'],
            'mac'           => provision_eth['mac_address'],
            'fqdn'          => provision_eth['dns_name']
          )
          provision_eth.delete('use_for_provision')
        end
      
        absent_keys = node.absent_keys(['ip', 'power_address', 'mac', 'fqdn'])
        if provision_eth.nil? && !absent_keys.empty?
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