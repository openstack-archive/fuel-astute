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

require 'uri'
SYNC_RETRIES = 10

module Astute
  class SyncPuppetStuff < PreDeploymentAction

    # Sync puppet manifests and modules to every node
    def process(deployment_info, context)
      master_ip = deployment_info.first['master_ip']
      modules_source = deployment_info.first['puppet_modules_source'] || "rsync://#{master_ip}:/puppet/modules/"
      manifests_source = deployment_info.first['puppet_manifests_source'] || "rsync://#{master_ip}:/puppet/manifests/"
      # Paths to Puppet modules and manifests at the master node set by Nailgun
      # Check fuel source code /deployment/puppet/nailgun/manifests/puppetsync.pp
      schemas = [modules_source, manifests_source].map do |url|
        begin
          URI.parse(url).scheme
        rescue URI::InvalidURIError => e
          raise DeploymentEngineError, e.message
        end
      end

      if schemas.select{ |x| x != schemas.first }.present?
        raise DeploymentEngineError, "Scheme for puppet_modules_source '#{schemas.first}' and" \
                                     " puppet_manifests_source '#{schemas.last}' not equivalent!"
      end

      nodes_uids = only_uniq_nodes(deployment_info).map{ |n| n['uid'] }

      perform_with_limit(nodes_uids) do |part|
        sync_puppet_stuff(context, part, schemas, modules_source, manifests_source)
      end

    end # process

    private

    def sync_puppet_stuff(context, node_uids, schemas, modules_source, manifests_source)
      sync_mclient = MClient.new(context, "puppetsync", node_uids)

      case schemas.first
      when 'rsync'
        begin
          sync_mclient.rsync(:modules_source => modules_source,
                             :manifests_source => manifests_source
                            )
        rescue MClientError => e
          sync_retries ||= 0
          sync_retries += 1
          if sync_retries < SYNC_RETRIES
            Astute.logger.warn("Rsync problem. Try to repeat: #{sync_retries} attempt")
            retry
          end
          raise e
        end
      else
        raise DeploymentEngineError, "Unknown scheme '#{schemas.first}' in #{modules_source}"
      end
    end #process
  end #class
end
