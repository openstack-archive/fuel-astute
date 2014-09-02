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
  class PrePatching < PreDeployAction

    def process(deployment_info, context)
      old_env=deployment_info.first['openstack_version_prev']
      return unless old_env == 'null' 

      #TODO(aglarendil): stop services before packages removal. 
      #We should stop services with SIGTERM or even SIGKILL.
      
      remove_cmd=getremovepackage_cmd(deployment_info)

      Astute.logger.info "Starting removal of error-prone packages"
      Astute.logger.info "Executing command #{cmd}"

      response = run_shell_command(context, deployment_info.first['nodes'], remove_cmd)

      if response[:data][:exit_code] != 0
        Astute.logger.warn "#{context.task_id}: Fail to remove packages, "\
                             "check the debugging output for details"
      end



      Astute.logger.info "#{context.task_id}: Finished pre-patching hook"
    end #process

    def getremovepackage_cmd(deployment_info,services_list)
      case deployment_info.first['cobbler']['profile']
      when /centos/i
        then
        packages_list
        return "yum -y remove python-oslo-messaging python-oslo-config openstack-heat-common python-nova python-routes python-routes1.12 python-neutron python-django-horizon murano-api sahara sahara-dashboard python-ceilometer openstack-swift openstack-utils python-glance python-glanceclient python-cinder"
      when /ubuntu/i
        then
        #write down script for ubuntu here
        return "apt-get -y remove python-oslo.messaging python-oslo.config python-heat python-nova python-routes python-routes1.13 python-neutron python-django-horizon murano-common murano-api sahara sahara-dashboard python-ceilometer python-swift python-cinder python-keystoneclient python-neutronclient python-novaclient python-swiftclient python-troveclient"
      end
    end

  end #class
end
