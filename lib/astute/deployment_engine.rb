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
  class DeploymentEngine

    def initialize(context)
      if self.class.superclass.name == 'Object'
        raise "Instantiation of this superclass is not allowed. Please subclass from #{self.class.name}."
      end
      @ctx = context
    end

    def deploy(deployment_info, pre_deployment=[], post_deployment=[])
      raise "Deployment info are not provided!" if deployment_info.blank?

      @ctx.deploy_log_parser.deploy_type = deployment_info.first['deployment_mode']
      Astute.logger.info "Deployment mode #{@ctx.deploy_log_parser.deploy_type}"

      begin
        PreDeploymentActions.new(deployment_info, @ctx).process
      rescue => e
        Astute.logger.error("Unexpected error #{e.message} traceback #{e.format_backtrace}")
        raise e
      end

      run_nailgun_hooks(pre_deployment)

      pre_node_actions = PreNodeActions.new(@ctx)

      fail_deploy = false
      # Sort by priority (the lower the number, the higher the priority)
      # and send groups to deploy
      deployment_info.sort_by { |f| f['priority'] }.group_by{ |f| f['priority'] }.each do |_, nodes|
        # Prevent attempts to run several deploy on a single node.
        # This is possible because one node
        # can perform multiple roles.
        group_by_uniq_values(nodes).each do |nodes_group|
          # Prevent deploy too many nodes at once
          nodes_group.each_slice(Astute.config[:MAX_NODES_PER_CALL]) do |part|
            if !fail_deploy

              # Pre deploy hooks
              pre_node_actions.process(part)
              PreDeployActions.new(part, @ctx).process

              deploy_piece(part)

              # Post deploy hook
              PostDeployActions.new(part, @ctx).process

              fail_deploy = fail_critical_node?(part)
            else
              nodes_to_report = part.map do |n|
                {
                  'uid' => n['uid'],
                  'role' => n['role']
                }
              end
              Astute.logger.warn "This nodes: #{nodes_to_report} will " \
                "not deploy because at least one critical node deployment fail"
            end
          end
        end
      end

      # Post deployment hooks
      PostDeploymentActions.new(deployment_info, @ctx).process

      run_nailgun_hooks(post_deployment)
    end

    protected

    def validate_nodes(nodes)
      return true unless nodes.empty?

      Astute.logger.info "#{@ctx.task_id}: Nodes to deploy are not provided. Do nothing."
      false
    end

    private

    # Transform nodes source array to array of nodes arrays where subarray
    # contain only uniq elements from source
    # Source: [
    #   {'uid' => 1, 'role' => 'cinder'},
    #   {'uid' => 2, 'role' => 'cinder'},
    #   {'uid' => 2, 'role' => 'compute'}]
    # Result: [
    #   [{'uid' =>1, 'role' => 'cinder'},
    #    {'uid' => 2, 'role' => 'cinder'}],
    #   [{'uid' => 2, 'role' => 'compute'}]]
    def group_by_uniq_values(nodes_array)
      nodes_array = deep_copy(nodes_array)
      sub_arrays = []
      while !nodes_array.empty?
        sub_arrays << uniq_nodes(nodes_array)
        uniq_nodes(nodes_array).clone.each {|e| nodes_array.slice!(nodes_array.index(e)) }
      end
      sub_arrays
    end

    def uniq_nodes(nodes_array)
      nodes_array.inject([]) { |result, node| result << node unless include_node?(result, node); result }
    end

    def include_node?(nodes_array, node)
      nodes_array.find { |n| node['uid'] == n['uid'] }
    end

    def nodes_status(nodes, status, data_to_merge)
      {
        'nodes' => nodes.map do |n|
          {'uid' => n['uid'], 'status' => status, 'role' => n['role']}.merge(data_to_merge)
        end
      }
    end

    def fail_critical_node?(part)
      nodes_status = @ctx.status
      return false unless nodes_status.has_value?('error')

      stop_uids = part.select{ |n| n['fail_if_error'] }.map{ |n| n['uid'] } &
                  nodes_status.select { |k, v| v == 'error' }.keys
      return false if stop_uids.empty?

      Astute.logger.warn "#{@ctx.task_id}: Critical nodes with uids: #{stop_uids.join(', ')} " \
                         "fail to deploy. Stop deployment"
      true
    end

    def run_nailgun_hooks(nailgun_hooks)
      nailgun_hooks.sort_by { |f| f['priority'] }.each do |hook|
        Astute.logger.info "Run hook #{hook.to_yaml}"

        case hook['type']
        when 'sync' then sync_hook(hook)
        when 'shell' then shell_hook(hook)
        when 'upload_file' then upload_file_hook(hook)
        when 'puppet' then puppet_hook(hook)
        else raise "Unknown hook type #{hook['type']}"
        end
      end
    end

    def puppet_hook(hook)
      validate_presence(hook, 'uids')
      validate_presence(hook['parameters'], 'puppet_manifest')
      validate_presence(hook['parameters'], 'puppet_modules')

      timeout = hook['parameters']['timeout'] || 300
      cwd = hook['parameters']['cwd'] || "~/"

      shell_command =  <<-PUPPET_CMD
        cd #{cwd} &&
        puppet apply --debug --verbose --logdest syslog
        --modulepath=#{hook['parameters']['puppet_modules']}
        #{hook['parameters']['puppet_manifest']}
      PUPPET_CMD
      shell_command.tr!("\n"," ")

      perform_with_limit(hook['uids']).each do |node_uids|
        response = run_shell_command(
          @ctx,
          node_uids,
          shell_command,
          timeout
        )
        if response[:data][:exit_code] != 0
          Astute.logger.warn("Puppet run failed. Check puppet logs for details")
        end
      end
    end #puppet_hook

    def upload_file_hook(hook)
      validate_presence(hook, 'uids')
      validate_presence(hook['parameters'], 'path')
      validate_presence(hook['parameters'], 'data')

      overwrite = true if hook['parameters']['overwrite'].nil?
      parents = true if hook['parameters']['parents'].nil?
      permissions = hook['parameters']['permissions'] || '0644'
      user_owner = hook['parameters']['user_owner'] || 'root'
      group_owner = hook['parameters']['group_owner'] || 'root'
      dir_permissions = hook['parameters']['dir_permissions'] || '0755'

      perform_with_limit(hook['uids']).each do |node_uids|
        upload_mclient = Astute::MClient.new(@ctx, "uploadfile", node_uids)
        upload_mclient.upload(
          :path => hook['parameters']['path'],
          :content => hook['parameters']['data'],
          :overwrite => overwrite,
          :parents => parents,
          :permissions => permissions,
          :user_owner => user_owner,
          :group_owner => group_owner,
          :dir_permissions => dir_permissions
        )
      end
    end

    def shell_hook(hook)
      validate_presence(hook, 'uids')
      validate_presence(hook['parameters'], 'cmd')


      timeout = hook['parameters']['timeout'] || 300
      cwd = hook['parameters']['cwd'] || "~/"

      shell_command = "cd #{cwd} && #{hook['cmd']}"

      perform_with_limit(hook['uids']).each do |node_uids|
        response = run_shell_command(
          @ctx,
          node_uids,
          shell_command,
          timeout
        )
        if response[:data][:exit_code] != 0
          Astute.logger.warn("Shell command failed. Check debug output for details")
        end
      end
    end # shell_hook


    def sync_hook(hook)
      validate_presence(hook, 'uids')
      validate_presence(hook['parameters'], 'dst')
      validate_presence(hook['parameters'], 'src')

      path = hook['parameters']['dst']
      source = hook['parameters']['src']

      timeout = hook['parameters']['timeout'] || 300

      rsync_options = '-c -r --delete'
      rsync_cmd = "mkdir -p #{path} && rsync #{rsync_options} #{source} #{path}"

      perform_with_limit(hook['uids']).each do |node_uids|
        sync_retries = 0
        while sync_retries < 10
          sync_retries += 1
          response = run_shell_command(
            @ctx,
            node_uids,
            rsync_cmd,
            timeout
          )
          break if response[:data][:exit_code] == 0
          Astute.logger.warn("Rsync problem. Try to repeat: #{sync_retries} attempt")
        end
      end
    end # sync_hook

    def validate_presence(data, key)
      raise "Missing a required parameter #{key}" unless data[key].present?
    end

    def run_shell_command(context, node_uids, cmd, timeout=60)
      shell = MClient.new(context,
                          'execute_shell_command',
                          node_uids,
                          check_result=true,
                          timeout=timeout,
                          retries=1)

      #TODO: return result for all nodes not only for first
      response = shell.execute(:cmd => cmd).first
      Astute.logger.debug("#{context.task_id}: cmd: #{cmd}
                                               stdout: #{response[:data][:stdout]}
                                               stderr: #{response[:data][:stderr]}
                                               exit code: #{response[:data][:exit_code]}")
      response
    rescue MClientTimeout, MClientError => e
      Astute.logger.error("#{context.task_id}: cmd: #{cmd}
                                               mcollective error: #{e.message}")
      {:data => {}}
    end

    def perform_with_limit(nodes, &block)
      nodes.each_slice(Astute.config[:MAX_NODES_PER_CALL]) do |part|
        block.call(part)
      end
    end

  end
end
