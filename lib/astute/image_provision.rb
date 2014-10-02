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
  module ImageProvision
    def self.provision(ctx, nodes)
      failed_uids = []
      begin
        # uploading provisioning data "/tmp/provision.json"
        nodes.each { |node| upload_provision(ctx, node) }

        # running provisioning script
        results = run_provision(ctx, nodes)

        results.each do |node|
          unless node.results[:data][:exit_code] == 0
            failed = node.results[:sender].to_i
            Astute.logger.error("#{ctx.task_id}: Provision command returned non zero exit code on node: #{failed}")
            failed_uids << failed
          end
        end

      rescue => e
        msg = "Error while provisioning: message: #{e.message} trace: #{e.format_backtrace}"
        Astute.logger.error("#{ctx.task_id}: #{msg}")
        report_error(ctx, msg)
      end
      failed_uids
    end

    def self.upload_provision(ctx, node)
      Astute.logger.debug "#{ctx.task_id}: uploading provision data: #{node.to_json}"
      client = MClient.new(ctx, "uploadfile", [node['uid']])
      client.upload(:path => '/tmp/provision.json',
                    :content => node.to_json,
                    :user_owner => 'root',
                    :group_owner => 'root',
                    :overwrite => true)
    end

    def self.run_provision(ctx, nodes)
      uids = nodes.map { |node| node['uid'] }
      Astute.logger.debug "#{ctx.task_id}: running provision script: #{uids.join(', ')}"
      shell = MClient.new(ctx, 'execute_shell_command', uids, check_result=true, timeout=3600, retries=1)
      shell.execute(:cmd => 'flock -n /var/lock/provision.lock /usr/bin/provision')
    end

    def self.report_error(ctx, msg)
      ctx.reporter.report({'status' => 'error', 'error' => msg, 'progress' => 100})
    end

  end
end
