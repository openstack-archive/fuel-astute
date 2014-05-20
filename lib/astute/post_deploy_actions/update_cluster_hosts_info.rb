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

  class UpdateClusterHostsInfo < PostDeployAction

    def process(deployment_info, context)
      Astute.logger.info "Updating /etc/hosts in all cluster nodes"
      return if deployment_info.empty?

      response = nil
      deployment_info.first['nodes'].each do |node|
        upload_file(node['uid'],
                    deployment_info.first['nodes'].to_yaml,
                    context)

        cmd = <<-UPDATE_HOSTS
          ruby -r 'yaml' -e 'y = YAML.load_file("/etc/astute.yaml");
                             y["nodes"] = YAML.load_file("/tmp/astute.yaml");
                             File.open("/etc/astute.yaml", "w") { |f| f.write y.to_yaml }';
          puppet apply --logdest syslog --debug -e '$settings=parseyaml($::astute_settings_yaml)
                                $nodes_hash=$settings["nodes"]
                                class {"l23network::hosts_file": nodes => $nodes_hash }'
        UPDATE_HOSTS
        cmd.tr!("\n"," ")

        response = run_shell_command(context, Array(node['uid']), cmd)
        if response[:data][:exit_code] != 0
          Astute.logger.warn "#{context.task_id}: Fail to update /etc/hosts, "\
                             "check the debugging output for node "\
                             "#{node['uid']} for details"
        end
      end

      Astute.logger.info "#{context.task_id}: Updating /etc/hosts is done"
    end

    private

    def upload_file(node_uid, content, context)
        upload_mclient = Astute::MClient.new(context, "uploadfile", Array(node_uid))
        upload_mclient.upload(:path => "/tmp/astute.yaml",
                              :content => content,
                              :overwrite => true,
                              :parents => true,
                              :permissions => '0600'
                             )
    rescue MClientTimeout, MClientError => e
      Astute.logger.error("#{context.task_id}: mcollective upload_file agent error: #{e.message}")
    end

  end #class
end
