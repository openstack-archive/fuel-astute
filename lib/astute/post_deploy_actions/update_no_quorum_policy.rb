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
  class UpdateNoQuorumPolicy < PostDeployAction

    def process(deployment_info, context)
      # NOTE(bogdando) use 'suicide' if fencing is enabled in corosync
      cmd = '/usr/sbin/crm configure property no-quorum-policy=stop'

      controllers_count = Array(deployment_info.select { |n| ['controller',
                            'primary-controller'].include? n['role'] }).size
      if controllers_count > 2
        Astute.logger.info "Start updating no quorum policy for corosync cluster"
        primary_controller = deployment_info.find { |n| n['role'] == 'primary-controller' }

        response = run_shell_command(context, Array(primary_controller['uid']), cmd)
        if response[:data][:exit_code] != 0
          Astute.logger.warn "#{context.task_id}: Failed to update no "\
                               "quorum policy for corosync cluster,"
        end
        Astute.logger.info "#{context.task_id}: Finish updating no quorum policy "\
                           "for corosync cluster"
      else
        Astute.logger.info "No need to update quorum policy for corosync cluster"
      end
    end #process
  end #class
end
