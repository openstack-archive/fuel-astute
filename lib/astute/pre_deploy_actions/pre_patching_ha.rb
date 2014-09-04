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
  class PrePatchingHa < PreDeployAction

    def process(deployment_info, context)
      old_env=deployment_info.first['openstack_version_prev']
      return if old_env.nil? and
          deployment_info.first['deployment_mode'] !~ /ha/i
      
      controller_nodes = deployment_info.inject([]) do
        |_cn, cn|
        _cn << cn['uid'] if cn['role'] =~ /controller/i
        _cn
      end

      pacemaker_services_list=get_pacemaker_services_list(deployment_info)

      Astute.logger.info "Starting migration of pacemaker services from"
      Astute.logger.info "nodes #{controller_nodes.inspect}"

      pacemaker_services_list.each do
        |pacemaker_service|

        if deployment_info.select {|n|
          ['controller', 'primary-controller'].include? n['role']
          }.size < 3
          pcmk_ban_cmd="crm resource stop #{pacemaker_service} && sleep 3"
        else
          pcmk_ban_cmd="pcs resource ban #{pacemaker_service} `crm_node -n` && sleep 3"
        end
        Astute.logger.info "Banning pacemaker service #{pacemaker_service}"

        response = run_shell_command(context, controller_nodes, pcmk_ban_cmd)

        if response[:data][:exit_code] != 0
          Astute.logger.warn "#{context.task_id}: Failed to ban service #{pacemaker_service}, "\
                             "check the debugging output for details"
        end
      end

      Astute.logger.info "#{context.task_id}: Finished pre-patching-ha hook"
    end #process

    def get_pacemaker_services_list(deployment_info)
      services_list||=[]
      #Heat engine service is present everywhere
      services_list << get_heat_service_name(deployment_info)

      if deployment_info.first['quantum'].to_s == 'true'
        services_list << 'p_neutron-openvswitch-agent'
        services_list << 'p_neutron-metadata-agent'
        services_list << 'p_neutron-l3-agent'
        services_list << 'p_neutron-dhcp-agent'
      end

      #FIXME(aglarendil): I know, this is ugly, but I am not sure
      #that data sent by Nailgun is deserialized into FalseClass
      #anyway, it is better then if a.to_s.length > 4 then a=false :)

      if deployment_info.first['ceilometer']['enabled'].to_s == 'true'
        services_list = services_list + get_ceilometer_service_names(deployment_info)
      end
      return services_list
    end

    def get_ceilometer_service_names(deployment_info)
      case deployment_info.first['cobbler']['profile']
      when /centos/i
        then
        return ['p_openstack-ceilometer-compute','p_openstack-ceilometer-central'] 
      when /ubuntu/i
        then
        return ['p_ceilometer-agent-central','p_ceilometer-agent-compute'] 
      end
    end

    def get_heat_service_name(deployment_info)
      case deployment_info.first['cobbler']['profile']
      when /centos/i
        then
        return 'openstack-heat-engine'
      when /ubuntu/i
        then
        return 'heat-engine' 
      end
    end


  end #class
end
