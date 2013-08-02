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
require 'json'

module Astute
  class Enviroment
    
    def self.load_file(file)
      env = YAML.load_file(file)
      expand_data(env)
    end
    
    def self.expand_data(env)
      

      
      env['nodes'].each do |node|
        net_data = node['interfaces'].values.select { |value| value if value['use_for_provision'] } rescue []
        id = api_data.find{ |v| v['id'] if v['mac'] ==  net_data[0]['mac_address'] }['id']
        if net_data.size == 1
          node.merge!({
            'ip' =>  net_data[0]['ip_address'],
            'power_address' => net_data[0]['ip_address'],
            'fqdn' => net_data[0]['dns_name'],
            'mac' => net_data[0]['mac_address'],
            'id' => id,
            'uid' => id
          })
          p "== 123 ==="
          p node['ip']
          p node['mac']
          p "=== end ==="
        else
          Astute.logger.error "Not find use_for_provision in #{node[:name]}"
        end
        
      end
      env
    end
    
    def get_data_from_nailgun
      # Get additional data from FuelWeb
      begin
        response = RestClient.get 'http://localhost:8000/api/nodes'
      rescue => e
        e.response
      end
      
      if response.
        api_data = JSON.parse(response)
    end
    
    
    def set_param(env, param, new)
      env[param] 
    end
    
    
  end
end