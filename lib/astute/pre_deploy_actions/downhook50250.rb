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
  class DownHook50250 < PreDeployAction

    def process(deployment_info, context)
      new_env=deployment_info.first['openstack_version']
      old_env=deployment_info.first['openstack_version_prev']
      return unless old_env == '2014.1.1-5.0.2' and new_env == '2014.1'
      services_list=[
            'openstack-keystone',
            'openstack-nova-api',
            'openstack-nova-conductor',
            'openstack-nova-console',
            'openstack-nova-cert',
            'openstack-nova-objectstore',
            'openstack-nova-scheduler',
            'openstack-nova-novncproxy'
       ]
 
      cmd=getdownpackage_cmd(deployment_info,services_list)

      Astute.logger.info "Starting downgrade of error-prone packages"
      Astute.logger.info "Executing command #{cmd}"

      response = run_shell_command(context, deployment_info.first['nodes'], cmd)

      if response[:data][:exit_code] != 0
        Astute.logger.warn "#{context.task_id}: Fail to downgrade packages, "\
                             "check the debugging output for details"
      end


      #TODO(aglarendil): restart services after packages update. 
      #We should restart services with SIGTERM or even SIGKILL.

      Astute.logger.info "#{context.task_id}: Finished downgrade hook for rollback from 5.0.2 to 5.0 release"
    end #process

    def getdownpackage_cmd(deployment_info,services_list)
      case deployment_info.first['cobbler']['profile']
      when /centos/i
        then
        down_packages_list=[
            'python-nova',
            'python-keystone',
            'python-routes'
       ]
        return "yum -y " + down_packages_list.join(' ') + " " + services_list.join(' ') 
      when /ubuntu/i
        then
        #write down script for ubuntu here
        return '/bin/true'
      end
    end

  end #class
end
