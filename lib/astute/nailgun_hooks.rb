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
  class NailgunHooks

    def initialize(nailgun_hooks, context)
      @nailgun_hooks = nailgun_hooks
      @ctx = context
    end

    def process
      @nailgun_hooks.sort_by { |f| f['priority'] }.each do |hook|
        Astute.logger.info "Run hook #{hook.to_yaml}"

        success = case hook['type']
        when 'sync' then sync_hook(hook)
        when 'shell' then shell_hook(hook)
        when 'upload_file' then upload_file_hook(hook)
        when 'puppet' then puppet_hook(hook)
        else raise "Unknown hook type #{hook['type']}"
        end

        is_raise_on_error = hook.fetch('fail_on_error', true)

        if !success && is_raise_on_error
          nodes = hook['uids'].map do |uid|
            { 'uid' => uid,
              'status' => 'error',
              'error_type' => 'deploy',
              'role' => 'hook',
              'hook' => hook['diagnostic_name']
            }
          end
          @ctx.report_and_update_status('nodes' => nodes)
          raise Astute::DeploymentEngineError,
            "Failed to deploy plugin #{hook['diagnostic_name']}"
        end
      end
    end

    private

    def puppet_hook(hook)
      validate_presence(hook, 'uids')
      validate_presence(hook['parameters'], 'puppet_manifest')
      validate_presence(hook['parameters'], 'puppet_modules')
      validate_presence(hook['parameters'], 'cwd')

      timeout = hook['parameters']['timeout'] || 300

      is_success = true
      perform_with_limit(hook['uids']) do |node_uids|
        result = run_puppet(
          @ctx,
          node_uids,
          hook['parameters']['puppet_manifest'],
          hook['parameters']['puppet_modules'],
          hook['parameters']['cwd'],
          timeout
        )
        unless result
          Astute.logger.warn("Puppet run failed. Check puppet logs for details")
          is_success = false
        end
      end

      is_success
    end #puppet_hook

    def upload_file_hook(hook)
      validate_presence(hook, 'uids')
      validate_presence(hook['parameters'], 'path')
      validate_presence(hook['parameters'], 'data')

      hook['parameters']['content'] = hook['parameters']['data']

      is_success = true
      perform_with_limit(hook['uids']) do |node_uids|
        status = upload_file(@ctx, node_uids, hook['parameters'])
        is_success = false if status == false
      end

      is_success
    end

    def shell_hook(hook)
      validate_presence(hook, 'uids')
      validate_presence(hook['parameters'], 'cmd')


      timeout = hook['parameters']['timeout'] || 300
      cwd = hook['parameters']['cwd'] || "~/"

      shell_command = "cd #{cwd} && #{hook['parameters']['cmd']}"

      is_success = true
      perform_with_limit(hook['uids']) do |node_uids|
        response = run_shell_command(
          @ctx,
          node_uids,
          shell_command,
          timeout,
          cwd
        )
        if response[:data][:exit_code] != 0
          Astute.logger.warn("Shell command failed. Check debug output for details")
          is_success = false
        end
      end

      is_success
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

      is_success = false

      perform_with_limit(hook['uids']) do |node_uids|
        10.times do |sync_retries|
          response = run_shell_command(
            @ctx,
            node_uids,
            rsync_cmd,
            timeout
          )
          if response[:data][:exit_code] == 0
            is_success = true
            break
          end
          Astute.logger.warn("Rsync problem. Try to repeat: #{sync_retries} attempt")
        end
      end

      is_success
    end # sync_hook

    def validate_presence(data, key)
      raise "Missing a required parameter #{key}" unless data[key].present?
    end

    def run_puppet(context, node_uids, puppet_manifest, puppet_modules, cwd, timeout)
      # Prevent send report status to Nailgun
      hook_context = Context.new(context.task_id, HookReporter.new, LogParser::NoParsing.new)
      nodes = node_uids.map { |node_id| {'uid' => node_id.to_s, 'role' => 'hook'} }

      Timeout::timeout(timeout) {
        PuppetdDeployer.deploy(
          hook_context,
          nodes,
          retries=2,
          puppet_manifest,
          puppet_modules,
          cwd
        )
      }

      !hook_context.status.has_value?('error')
    rescue Astute::MClientTimeout, Astute::MClientError, Timeout::Error => e
      Astute.logger.error("#{context.task_id}: puppet timeout error: #{e.message}")
      false
    end

    def run_shell_command(context, node_uids, cmd, timeout=60, cwd="/tmp")
      shell = MClient.new(context,
                          'execute_shell_command',
                          node_uids,
                          check_result=true,
                          timeout=timeout,
                          retries=1)

      #TODO: return result for all nodes not only for first
      response = shell.execute(:cmd => cmd, :cwd => cwd).first
      Astute.logger.debug(
        "#{context.task_id}: cmd: #{cmd}\n" \
        "cwd: #{cwd}\n" \
        "stdout: #{response[:data][:stdout]}\n" \
        "stderr: #{response[:data][:stderr]}\n" \
        "exit code: #{response[:data][:exit_code]}")
      response
    rescue MClientTimeout, MClientError => e
      Astute.logger.error(
        "#{context.task_id}: cmd: #{cmd} \n" \
        "mcollective error: #{e.message}")
      {:data => {}}
    end

    def upload_file(context, node_uids, mco_params={})
      upload_mclient = Astute::MClient.new(context, "uploadfile", Array(node_uids))

      mco_params['overwrite'] = true if mco_params['overwrite'].nil?
      mco_params['parents'] = true if mco_params['parents'].nil?
      mco_params['permissions'] ||= '0644'
      mco_params['user_owner']  ||= 'root'
      mco_params['group_owner'] ||= 'root'
      mco_params['dir_permissions'] ||= '0755'

      upload_mclient.upload(
        :path => mco_params['path'],
        :content => mco_params['content'],
        :overwrite => mco_params['overwrite'],
        :parents => mco_params['parents'],
        :permissions => mco_params['permissions'],
        :user_owner => mco_params['user_owner'],
        :group_owner => mco_params['group_owner'],
        :dir_permissions => mco_params['dir_permissions']
      )

      true
    rescue MClientTimeout, MClientError => e
      Astute.logger.error("#{context.task_id}: mcollective upload_file agent error: #{e.message}")
      false
    end

    def perform_with_limit(nodes, &block)
      nodes.each_slice(Astute.config[:MAX_NODES_PER_CALL]) do |part|
        block.call(part)
      end
    end

  end # class

  class HookReporter
    def report(msg)
      Astute.logger.debug msg
    end
  end

end # module
