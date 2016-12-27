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

      failed_uids += run_shell_task(
        ctx,
        uids,
        'flock -n /var/lock/provision.lock provision',
        Astute.config.provisioning_timeout
      )

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

    def self.run_shell_task(ctx, node_uids, cmd, timeout=3600)
      shell_tasks = node_uids.inject([]) do |tasks, node_id|
        tasks << Shell.new(generate_shell_hook(node_id, cmd, timeout), ctx)
      end

      shell_tasks.each(&:run)

      while shell_tasks.any? { |t| !t.finished? } do
        shell_tasks.select { |t| !t.finished? }.each(&:status)
        sleep 1
      end

      failed_uids = shell_tasks.select{ |t| t.failed? }.inject([]) do |task|
        Astute.logger.error("#{ctx.task_id}: Provision command returned " \
          "non zero exit code on node: #{task.node_id}")
        failed_uids << task.node_id
      end

      failed_uids
    rescue => e
      Astute.logger.error("#{ctx.task_id}: cmd: #{cmd} " \
        "error: #{e.message}, trace #{e.backtrace}")
      node_uids
    end

    def self.generate_shell_hook(node_id, cmd, timeout)
      {
        "node_id" => node_id,
        "id" => "provision_#{node_id}",
        "parameters" =>  {
          "cmd" =>  cmd,
          "cwd" =>  "/",
          "timeout" => timeout,
          "retries" => 0
        }
      }
    end

  end
end
