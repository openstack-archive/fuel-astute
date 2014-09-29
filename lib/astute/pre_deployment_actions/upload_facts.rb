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
  class UploadFacts < PreDeploymentAction

    def process(deployment_info, context)
      deployment_info.each{ |node| upload_facts(context, node) }
      Astute.logger.info "#{context.task_id}: Required attrs/metadata passed via facts extension"
    end

    private

    def upload_facts(context, node)
      Astute.logger.info  "#{context.task_id}: storing metadata for node uid=#{node['uid']} "\
        "role=#{node['role']}"
      Astute.logger.debug "#{context.task_id}: stores metadata: #{node.to_yaml}"

      # This is synchronious RPC call, so we are sure that data were sent and processed remotely
      upload_mclient = Astute::MClient.new(context, "uploadfile", [node['uid']])
      upload_mclient.upload(
        :path => "/etc/#{node['role']}.yaml",
        :content => node.to_yaml,
        :overwrite => true,
        :parents => true,
        :permissions => '0600'
      )
    end

  end #class
end
