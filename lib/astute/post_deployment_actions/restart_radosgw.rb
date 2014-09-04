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
  class RestartRadosgw < PostDeploymentAction

    def process(deployment_info, context)
      ceph_node = deployment_info.find { |n| n['role'] == 'ceph-osd' }
      objects_ceph = ceph_node && ceph_node.fetch('storage', {}).fetch('objects_ceph')

      return unless objects_ceph
      Astute.logger.info "Start restarting radosgw on controller nodes"

      cmd = <<-RESTART_RADOSGW
        (test -f /etc/init.d/ceph-radosgw && /etc/init.d/ceph-radosgw restart) ||
        (test -f /etc/init.d/radosgw && /etc/init.d/radosgw restart);
      RESTART_RADOSGW
      cmd.tr!("\n"," ")

      controller_nodes = deployment_info.first['nodes'].inject([]) do |c_n, n|
        c_n << n['uid'] if ['controller', 'primary-controller'].include? n['role']
        c_n
      end

      response = run_shell_command(context, controller_nodes, cmd)
      if response[:data][:exit_code] != 0
        Astute.logger.warn "#{context.task_id}: Fail to restart radosgw, "\
                             "check the debugging output for details"
      end
      Astute.logger.info "#{context.task_id}: Finish restarting radosgw on controller nodes"
    end #process
  end #class
end
