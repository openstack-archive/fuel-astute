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
  class SyncTime < PreDeploymentAction

    # Sync time
    def process(deployment_info, context)
      nodes_uids = only_uniq_nodes(deployment_info).map{ |n| n['uid'] }
      cmd = "ntpdate -u $(egrep '^server' /etc/ntp.conf | sed '/^#/d' | awk '{print $2}')"
      succeeded = false

      Astute.config.MC_RETRIES.times.each do
        succeeded = run_shell_command_remotely(context, nodes_uids, cmd)
        return if succeeded
        sleep Astute.config.MC_RETRY_INTERVAL
      end

      if !succeeded
        Astute.logger.warn "Run command: '#{cmd}' in nodes: #{nodes_uids} fail. " \
                           "Check debug output for more information. You can try "\
                           "to fix it problem manually."
      end
    end #process

    private

    def run_shell_command_remotely(context, nodes_uids, cmd)
      response = run_shell_command(context, nodes_uids, cmd)
      response.fetch(:data, {})[:exit_code] == 0
    end

  end #class
end
