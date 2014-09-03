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
  class StopOSTServices < PreNodeAction

    def process(deployment_info, context)
      old_env=deployment_info.first['openstack_version_prev']
      return if old_env.nil?

      stop_cmd=getstop_cmd(deployment_info, 'nova|cinder|glance|keystone|neutron|sahara|murano|ceilometer|heat|swift')

      Astute.logger.info "Stopping all Openstack services gracefully"
      Astute.logger.info "Executing command #{getstop_cmd}"

      response = run_shell_command(context, deployment_info.first['nodes'], stop_cmd)

      if response[:data][:exit_code] != 0
        Astute.logger.warn "#{context.task_id}: Failed to stop services, "\
                             "check the debugging output for details"
      end



      Astute.logger.info "#{context.task_id}: Finished pre-patching hook"
    end #process

    def getstop_cmd(deployment_info, services_list)
      case deployment_info.first['cobbler']['profile']
      when /centos/i
        then
        delimiter = "running"
        pos = "$1"
      when /ubuntu/i
        then
        delimiter = "+"
        pos = "$4"
      end
      result = ""
      # 1st, try to stop given services gracefully
      result += "service --status-all 2>&1|egrep '#{services_list}'|awk '/#{delimiter}/ {print #{pos}}'|"
      result += "xargs -n1 -I {} service {} stop >/dev/null 2>&1;"
      # 2nd, check for related running python processes, if any left
      result += "pids=$(ps aux|egrep '#{services_list}'|awk '/python/ {print $2}');"
      # for every pid discovered, find all its childs
      result += "for p in `echo $pids`; do pids_to_kill=$(pstree -Alp $p|"
      result += "perl -e \"while(<>){ push @r, /((\\d+))/sg};"
      result += "print join(\\\"\\n\\\",@r), \\\"\\n\\\"\"|uniq);"
      # and send SIGKILL
      result += "for pid in `echo $pids_to_kill`; do [ $pid -gt 1 ] && kill -9 $pid; done; done||true"
      return result
    end
  end #class
end
