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
      return unless deployment_info.first['openstack_version_prev']

      stop_cmd=getstop_cmd(deployment_info, 'nova|cinder|glance|keystone|neutron|sahara|murano|ceilometer|heat|swift')

      Astute.logger.info "Stopping all Openstack services gracefully"
      Astute.logger.info "Executing command #{stop_cmd}"

      response = run_shell_command(context, deployment_info.map {|n| n['uid']}, stop_cmd)

      if response[:data][:exit_code] != 0
        Astute.logger.warn "#{context.task_id}: Failed to stop services, "\
                             "check the debugging output for details"
      end

      Astute.logger.info "#{context.task_id}: Finished pre-patching hook"
    end #process

    def getstop_cmd(deployment_info, services_list)
      case deployment_info.first['cobbler']['profile']
      when /centos/i
        delimiter = "running"
        pos = "$1"
      when /ubuntu/i
        delimiter = "+"
        pos = "$4"
      end
      cmd = <<-CMD
        echo "1st, try to stop given services gracefully";
        service --status-all 2>&1|egrep '#{services_list}'|awk '/#{delimiter}/ {print #{pos}}'|
        xargs -n1 -I {} service {} stop >/dev/null 2>&1;

        echo "2nd, check for related running python processes, if any left";
        pids=$(ps aux|egrep '#{services_list}'|awk '/python/ {print $2}');

        echo "for every pid discovered, find all its childs";
        for p in `echo $pids`; do pids_to_kill=$(pstree -Alp $p|
        perl -e \"while(<>){ push @r, /((\\d+))/sg};
        print join(\\\"\\n\\\",@r), \\\"\\n\\\"\"|uniq);

        echo "and send SIGKILL";
        for pid in `echo $pids_to_kill`; do [ $pid -gt 1 ] && kill -9 $pid; done; done||true
        CMD
      cmd.tr!("\n"," ")
    end
  end #class
end
