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
      uids_to_provision, failed_uids = upload_provision(ctx, nodes)
      run_provision(ctx, uids_to_provision, failed_uids)
    rescue => e
      msg = "Error while provisioning: message: #{e.message}" \
        " trace\n: #{e.format_backtrace}"
      Astute.logger.error("#{ctx.task_id}: #{msg}")
      report_error(ctx, msg)
      failed_uids
    end

    def self.upload_provision(ctx, nodes)
      failed_uids = []
      nodes.each do |node|
        succees = upload_provision_data(ctx, node)
        next if succees

        failed_uids << node['uid']
        Astute.logger.error("#{ctx.task_id}: Upload provisioning data " \
          "failed on node #{node['uid']}. Provision on such node will " \
          "not start")
      end

      uids_to_provision = nodes.select { |n| !failed_uids.include?(n['uid']) }
                               .map { |n| n['uid'] }
      [uids_to_provision, failed_uids]
    end

    def self.upload_provision_data(ctx, node)
      Astute.logger.debug("#{ctx.task_id}: uploading provision " \
        "data on node #{node['uid']}: #{node.to_json}")

      upload_task = Astute::UploadFile.new(
        generate_upload_provision_task(node),
        ctx
      )

      upload_task.sync_run
    end

    def self.generate_upload_provision_task(node)
      {
        "id" => 'upload_provision_data',
        "node_id" =>  node['uid'],
        "parameters" =>  {
          "path" => '/tmp/provision.json',
          "data" => node.to_json,
          "user_owner" => 'root',
          "group_owner" => 'root',
          "overwrite" => true
        }
      }
    end

    def self.run_provision(ctx, uids, failed_uids)
      Astute.logger.debug("#{ctx.task_id}: running provision script: " \
        "#{uids.join(', ')}")

      results = run_shell_command(
        ctx,
        uids,
        'flock -n /var/lock/provision.lock /usr/bin/provision',
        Astute.config.provisioning_timeout
      )

      results.each do |node|
        next if node.results[:data][:exit_code] == 0

        failed_uids << node.results[:sender]
        Astute.logger.error("#{ctx.task_id}: Provision command returned " \
          "non zero exit code on node: #{node.results[:sender]}")
      end

      failed_uids
    end

    def self.report_error(ctx, msg)
      ctx.reporter.report({
        'status' => 'error',
        'error' => msg,
        'progress' => 100
      })
    end

    def self.reboot(ctx, node_ids, task_id="reboot_provisioned_nodes")
      if node_ids.empty?
        Astute.logger.warn("No nodes were sent to reboot for " \
          "task: #{task_id}")
        return
      end

      Astute::NailgunHooks.new(
        [{
          "priority" =>  100,
          "type" => "reboot",
          "fail_on_error" => false,
          "id" => task_id,
          "uids" =>  node_ids,
          "parameters" =>  {
            "timeout" =>  Astute.config.reboot_timeout
          }
        }],
        ctx,
        'provision'
      ).process
    end

    def self.run_shell_command(context, node_uids, cmd, timeout=3600)
      shell = MClient.new(
        context,
        'execute_shell_command',
        node_uids,
        check_result=true,
        timeout=timeout,
        retries=1
      )

      shell.execute(:cmd => cmd)
    rescue MClientTimeout, MClientError => e
      Astute.logger.error("#{context.task_id}: cmd: #{cmd} " \
        "mcollective error: #{e.message}")
      [{:data => {}}]
    end

  end
end
