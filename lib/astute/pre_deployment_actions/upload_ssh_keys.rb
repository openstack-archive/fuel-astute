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
  class UploadSshKeys < PreDeploymentAction

    # Upload ssh keys from master node to all cluster nodes
    def process(deployment_info, context)
      deployment_id = deployment_info.first['deployment_id'].to_s
      nodes_ids = only_uniq_nodes(deployment_info).map{ |n| n['uid'] }
      perform_with_limit(nodes_ids) do |ids|
        upload_keys(context, ids, deployment_id)
      end
    end

    private

    def upload_keys(context, node_uids, deployment_id)
      Astute.config.PUPPET_SSH_KEYS.each do |key_name|
        upload_mclient = MClient.new(context, "uploadfile", node_uids)
        [key_name, key_name + ".pub"].each do |ssh_key|
          source_path = File.join(
            Astute.config.PUPPET_SSH_KEYS_DIR,
            deployment_id,
            key_name,
            ssh_key)
          destination_path = File.join(
            Astute.config.PUPPET_SSH_KEYS_DIR,
            key_name,
            ssh_key)
          content = File.read(source_path)
          upload_mclient.upload(:path => destination_path,
                                :content => content,
                                :user_owner => 'root',
                                :group_owner => 'root',
                                :permissions => '0600',
                                :dir_permissions => '0700',
                                :overwrite => true,
                                :parents => true
                               )
        end
      end
    end #upload_keys

  end #class
end
