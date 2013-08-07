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
          puts "[#{e.path}] #{e.message}"
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
        end
        # Deploy section
      end
  
      private
      
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
                 or set manually #{missing_keys.each {|k| p k}}"
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
      #       "type"=>"partition", 
      #       "mount"=>"/boot", 
      #       "size"=>200
      #     }, 
      #     {
      #       "type"=>"pv", 
      #       "size"=>16174, 
      #       "vg"=>"os"
      #     }
      #   ]
      # }]
      # Example result for 'ks_spaces' param: [{\\\"type\":\"disk\",\"id\":\"disk/by-path/pci-0000:00:0d.0-scsi-0:0:0:0\",\"size\":16384,\"volumes\":[{\"type\":\"partition\",\"mount\":\"/boot\",\"size\":200},{\"type\":\"pv\",\"size\":16174,\"vg\":\"os\"}]}]
      def define_ks_spaces(node)
        if node['ks_meta'].present? 'ks_spaces'
          node['ks_meta'].delete('ks_disks')
          return
        end
    
        if node['ks_meta'].absent? 'ks_disks'
          raise "Please set 'ks_disks' or 'ks_spaces' parameter in section ks_meta for #{node['name']}"
        end
    
        node['ks_meta']['ks_spaces'] = node['ks_meta']['ks_disks'].to_json.gsub("\"", "\\\"")
        node['ks_meta'].delete('ks_disks')
      end
    end # class end
  end # module Cli
end