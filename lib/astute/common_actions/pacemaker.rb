#    Copyright 2014 Mirantis, Inc.
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
  class Pacemaker

    def self.commands(behavior, deployment_info)
      return [] if deployment_info.first['deployment_mode'] !~ /ha/i

      controller_nodes = deployment_info.select{ |n| n['role'] =~ /controller/i }.map{ |n| n['uid'] }
      return [] if controller_nodes.empty?

      ha_size = deployment_info.first['nodes'].count { |n|
        ['controller', 'primary-controller'].include? n['role']
      }

      action = if ha_size < 3
        case behavior
        when 'stop' then 'stop'
        when 'start' then 'start'
        end
      else
        case behavior
        when 'stop' then 'ban'
        when 'start' then 'clear'
        end
      end

      cmds = pacemaker_services_list(deployment_info).inject([]) do |cmds, pacemaker_service|
        if ha_size < 3
          cmds << "crm resource #{action} #{pacemaker_service} && sleep 3"
        else
          cmds << "pcs resource #{action} #{pacemaker_service} `crm_node -n` && sleep 3"
        end
      end

      cmds
    end

    private

    def self.pacemaker_services_list(deployment_info)
      services_list = []
      #Heat engine service is present everywhere
      services_list += heat_service_name(deployment_info)

      if deployment_info.first['quantum']
        services_list << 'p_neutron-openvswitch-agent'
        services_list << 'p_neutron-metadata-agent'
        services_list << 'p_neutron-l3-agent'
        services_list << 'p_neutron-dhcp-agent'
      end

      if deployment_info.first.fetch('ceilometer', {})['enabled']
        services_list += ceilometer_service_names(deployment_info)
      end
      return services_list
    end

    def self.ceilometer_service_names(deployment_info)
      case deployment_info.first['cobbler']['profile']
      when /centos/i
        ['p_openstack-ceilometer-compute','p_openstack-ceilometer-central']
      when /ubuntu/i
        ['p_ceilometer-agent-central','p_ceilometer-agent-compute']
      end
    end

    def self.heat_service_name(deployment_info)
      case deployment_info.first['cobbler']['profile']
      when /centos/i
        ['openstack-heat-engine', 'p_openstack-heat-engine']
      when /ubuntu/i
        ['heat-engine', 'p_heat-engine']
      end
    end

  end #class
end
