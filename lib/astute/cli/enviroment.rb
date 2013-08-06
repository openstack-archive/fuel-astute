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
require 'astute/ext/hash'
require 'astute/cli/yaml_validator'

module Astute
  class Cli::Enviroment
    
    def self.load_file(file)
      @config = YAML.load_file(file)
      validate_env
      convert_to_full_conf
    end
    
    def self.validate_env
      validator = Cli::YamlValidator.new()
      errors = validator.validate(@config)
      
      errors.each do |e|
        puts "[#{e.path}] #{e.message}"
      end
    end
    
    def self.convert_to_full_conf
      # Provision
      @config['nodes'].each_with_index do |node, index|
        provision_eth = node['interfaces'].find {|eth| eth['use_for_provision'] }
        if provision_eth
          node.reverse_merge!(
            'ip'            => provision_eth['ip_address'],
            'power_address' => provision_eth['ip_address'],
            'mac'           => provision_eth['mac_address'],
            'fqdn'          => provision_eth['dns_name']
            )
        end
        missing_keys = node.find_missing_keys(['ip', 'power_address', 'mac', 'fqdn'])
        if provision_eth.nil? && !missing_keys.empty?
          raise "Please set 'use_for_provision' parameter for #{node['name']}
                 or set manually #{missing_keys.each {|k| p k}}"
        end
        node.reverse_merge!(
          'id'  => index,
          'uid' => index
          )
        
        # Extend blocks interfaces and interfaces_extra to old formats
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
      @config
    end    
  end
end