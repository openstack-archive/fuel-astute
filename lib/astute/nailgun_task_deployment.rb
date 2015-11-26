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
require 'fuel-deployment'

module Astute

  class NailgunNode < Deployment::Node
    def context=(context)
      @ctx = context
    end

    def run(task)
      self.task = task
      @task_engine = select_task_engine(task.data, @ctx)
      @task_engine.run
      task.set_status_running
      set_status_busy
    end

    def poll
      if busy?
        task.status = @task_engine.status
        if task.running?
          @ctx.report({
            'uid' => id,
            'status' => 'deploying',
            'task' => task.name,
            'progress' => current_progress_bar
          })
        else
          set_status_online

          deploy_status = if !finished?
            'deploying'
          elsif successful?
            'ready'
          else
            'error'
          end
          report_status = {
            'uid' => id,
            'status' => deploy_status,
            'task' => task.name,
            'task_status' => task.status,
            'progress' => current_progress_bar
          }
          report_status.merge('error_type' => 'deploy') if
            deploy_status == 'error'
          @ctx.report(report_status)
        end
      end
    end

    private

    def current_progress_bar
      100 * tasks_finished_count / tasks_total_count
    end

    def select_task_engine(data)
      # TODO: replace by Object.const_get(type.split('_').collect(&:capitalize).join)
      case data['type']
      when 'shell' then Shell.new(data, @ctx)
      when 'puppet' then Puppet.new(data, @ctx)
      when 'upload_file' then UploadFile.new(data, @ctx)
      when 'reboot' then Reboot.new(data, @ctx)
      when 'sync' then Sync.new(data, @ctx)
      when 'cobbler_sync' then CobblerSync.new(data, @ctx)
      when 'copy_files' then CopyFiles.new(data, @ctx)
      when 'copy_file' then CopyFile.new(data, @ctx)
      when 'noop' then Noop.new(data, @ctx)
      #FIXME: remove it after Nailgun changes: stage -> noop
      when 'stage' then Noop.new(data,@ctx)
      else raise TaskValidationError, "Unknown task type #{data['type']}"
      end
    end
  end


  class NailgunTaskDeployment

    def initialize(context)
      @ctx = context
      Deployment::Log.logger = Astute.logger
    end

    def deploy(deployment_info, deployment_tasks)
      raise "Deployment info are not provided!" if
        deployment_info.blank? || deployment_tasks.blank?

      deployment_info, offline_uids = remove_failed_nodes(deployment_info)
      Astute::TaskPreDeploymentActions.new(deployment_info, @ctx).process

      nodes = deployment_tasks.keys.inject({}) do |nodes, node_id|
        node = NailgunNode.new(node_id)
        node.context = @ctx
        node.set_critical if critical_node_uids(deployment_info).include? node_id
        node.set_status_failed if offline_uids.include? node_id
        nodes.merge(node_id => node)
      end

      #TODO: Support remote node depends
      deployment_tasks.each do |node_id, tasks|
        tasks.each do |task|
          nodes[node_id].graph.create_task task['id'], task
        end
      end

      deployment = Deployment::Process.new(nodes.values)
      deployment.run
    end

    private

    def critical_node_uids(deployment_info)
      @critcial_nodes ||= deployment_info.select{ |n| n['fail_if_error'] }
                                         .map{ |n| n['uid'] }.uniq
    end

    # Removes nodes which failed to provision
    def remove_failed_nodes(deployment_info)
      uids = get_uids_from_deployment_info deployment_info
      required_uids = critical_node_uids(deployment_info)

      available_uids = detect_available_nodes(uids)
      offline_uids = uids - available_uids
      if offline_uids.present?
        # set status for all failed nodes to error
        nodes = (uids - available_uids).map do |uid|
          {'uid' => uid,
           'status' => 'error',
           'error_type' => 'provision',
           'error_msg' => 'Node is not ready for deployment: '\
                          'mcollective has not answered'
          }
        end

        @ctx.report_and_update_status(
          'nodes' => nodes,
          'error' => 'Node is not ready for deployment'
        )

        # check if all required nodes are online
        # if not, raise error
        missing_required = required_uids - available_uids
        if missing_required.present?
          error_message = "Critical nodes are not available for deployment: " \
                          "#{missing_required}"
          raise Astute::DeploymentEngineError, error_message
        end
      end

      return remove_offline_nodes(
        uids,
        available_uids,
        deployment_info,
        offline_uids)
    end

    def remove_offline_nodes(uids, available_uids, deployment_info, offline_uids)
      if offline_uids.blank?
        return [deployment_info, offline_uids]
      end

      Astute.logger.info "Removing nodes which failed to provision: " \
                         "#{offline_uids}"
      deployment_info = cleanup_nodes_block(deployment_info, offline_uids)
      deployment_info = deployment_info.select do |node|
        available_uids.include? node['uid']
      end

      [deployment_info, offline_uids]
    end

    def cleanup_nodes_block(deployment_info, offline_uids)
      return deployment_info if offline_uids.blank?

      nodes = deployment_info.first['nodes']

      # In case of deploy in already existing cluster in nodes block
      # we will have all cluster nodes. We should remove only missing
      # nodes instead of stay only avaliable.
      # Example: deploy 3 nodes, after it deploy 2 nodes.
      # In 1 of 2 seconds nodes missing, in nodes block we should
      # contain only 4 nodes.
      nodes_wthout_missing = nodes.select do |node|
        !offline_uids.include?(node['uid'])
      end
      deployment_info.each { |node| node['nodes'] = nodes_wthout_missing }
      deployment_info
    end

    def detect_available_nodes(uids)
      all_uids = uids.clone
      available_uids = []

      # In case of big amount of nodes we should do several calls to be sure
      # about node status
      Astute.config[:mc_retries].times.each do
        systemtype = Astute::MClient.new(
          @ctx,
          "systemtype",
          all_uids,
          check_result=false,
          10
        )
        available_nodes = systemtype.get_type.select do |node|
          node.results[:data][:node_type].chomp == "target"
        end

        available_uids += available_nodes.map { |node| node.results[:sender] }
        all_uids -= available_uids
        break if all_uids.empty?

        sleep Astute.config[:mc_retry_interval]
      end

      available_uids
    end

    def get_uids_from_deployment_info(deployment_info)
      top_level_uids = deployment_info.map{ |node| node["uid"] }

      inside_uids = deployment_info.inject([]) do |uids, node|
        uids += node.fetch('nodes', []).map{ |n| n['uid'] }
      end
      top_level_uids | inside_uids
    end
  end
end
