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

SYNC_RETRIES = 10

module Astute
  class SyncTasks < PreDeploymentAction

    # Sync puppet manifests and modules to every node
    def process(deployment_info, context)
      return unless deployment_info.first['tasks_source']

      # URI to Tasklib tasks at the master node set by Nailgun
      master_ip = deployment_info.first['master_ip']
      tasks_source = deployment_info.first['tasks_source'] || "rsync://#{master_ip}:/puppet/tasks/"
      source = tasks_source.chomp('/').concat('/')

      nodes_uids = only_uniq_nodes(deployment_info).map{ |n| n['uid'] }

      perform_with_limit(nodes_uids) do |part|
        rsync_tasks(context, source, part)
      end
    end

    private

    def rsync_tasks(context, source, nodes_uids)
      path = '/etc/puppet/tasks/'
      rsync_options = '-c -r --delete'
      rsync_cmd = "mkdir -p #{path} && rsync #{rsync_options} #{source} #{path}"

      sync_retries = 0
      while sync_retries < SYNC_RETRIES
        sync_retries += 1
        response = run_shell_command(
          context,
          nodes_uids,
          rsync_cmd,
          300
        )
        break if response[:data][:exit_code] == 0
        Astute.logger.warn("Rsync problem. Try to repeat: #{sync_retries} attempt")
      end
    end #rsync_tasks

  end #class
end
