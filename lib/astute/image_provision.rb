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
      begin
        nodes.each { |node| upload_provision(ctx, node) }
        results = run_provision(ctx, nodes)
        failed_nodes = []
        results.each do |node|
          unless node.results[:data][:exit_code] == 0
            Astute.logger.error("#{ctx.task_id}: Provision command returned non zero exit code on node: #{failed_name}")
            failed_node = nodes.select {|n| n['uid'].to_i == node.results[:sender].to_i}.first
            failed_nodes << failed_node
          end
        end
        if failed_nodes.empty?
          report_success(ctx)
        else
          failed_uids = failed_nodes.map{ |fn| fn['uid'].to_s }.join(' ')
          report_error(ctx, 'Provision failed on nodes: #{failed_uids}')
        end
      rescue => e
        msg = "Error while provisioning: message: #{e.message} \
trace: #{e.backtrace.inspect}"
        Astute.logger.error("#{ctx.task_id}: #{msg}")
        report_error(ctx, msg)
      end
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
      uids = nodes.map { |node| node['uid'].to_s }
      Astute.logger.debug "#{ctx.task_id}: running provision script: #{uids.join(' ')}"
      client = MClient.new(ctx, 'execute_shell_command', uids, check_result=true, retries=1)
      client.execute(:cmd => '/usr/bin/provision')
    end

    def self.report_success(ctx, msg=nil)
      success_msg = {'status' => 'ready', 'progress' => 100}
      success_msg.merge!({'msg' => msg}) if msg
      ctx.reporter.report(success_msg)
    end

    def self.report_error(ctx, msg)
      ctx.reporter.report({'status' => 'error', 'error' => msg, 'progress' => 100})
    end

  end
end
