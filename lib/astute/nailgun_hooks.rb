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

    def initialize(nailgun_hooks, context, type='deploy')
      @nailgun_hooks = nailgun_hooks
      @ctx = context
      @type = type
    end

    def process
      @nailgun_hooks.sort_by { |f| f['priority'] }.each do |hook|
        Astute.logger.info "Run hook #{hook.to_yaml}"

        hook_return = case hook['type']
        when 'copy_files' then copy_files_hook(hook)
        when 'upload_files' then upload_files_hook(hook)
        when 'sync' then sync_hook(hook)
        when 'shell' then shell_hook(hook)
        when 'upload_file' then upload_file_hook(hook)
        when 'puppet' then puppet_hook(hook)
        when 'reboot' then reboot_hook(hook)
        else raise "Unknown hook type #{hook['type']}"
        end

        is_raise_on_error = hook.fetch('fail_on_error', true)
        hook_name = hook['id'] || hook['diagnostic_name'] || hook['type']

        if hook_return['error'] && is_raise_on_error
          nodes = hook['uids'].map do |uid|
            { 'uid' => uid,
              'status' => 'error',
              'error_type' => @type,
              'role' => 'hook',
              'hook' => hook_name,
              'error_msg' => hook_return['error']
            }
          end
          error_message = 'Failed to execute hook'
          error_message += " '#{hook_name}'" if hook_name
          error_message += " #{hook_return['error']}"
          @ctx.report_and_update_status('nodes' => nodes, 'error' => error_message)
          error_message += "\n\n#{hook.to_yaml}"

          raise Astute::DeploymentEngineError, error_message

        end
      end
    end

    private

    def copy_files_hook(hook)
      validate_presence(hook, 'uids')
      validate_presence(hook['parameters'], 'files')

      ret = {'error' => nil}
      hook['parameters']['files'].each do |file|
        if File.file?(file['src']) && File.readable?(file['src'])
          parameters = {
            'content' => File.binread(file['src']),
            'path' => file['dst'],
            'permissions' => file['permissions'] || hook['parameters']['permissions'],
            'dir_permissions' => file['dir_permissions'] || hook['parameters']['dir_permissions'],
          }
          perform_with_limit(hook['uids']) do |node_uids|
            status = upload_file(@ctx, node_uids, parameters)
            if !status
              ret['error'] = 'Upload not successful'
            end
          end
        else
          ret['error'] = "File does not exist or is not readable #{file['src']}"
          Astute.logger.warn(ret['error'])
        end
      end
      ret
    end #copy_file_hook

    def puppet_hook(hook)
      validate_presence(hook, 'uids')
      validate_presence(hook['parameters'], 'puppet_manifest')
      validate_presence(hook['parameters'], 'puppet_modules')
      validate_presence(hook['parameters'], 'cwd')

      timeout = hook['parameters']['timeout'] || 300
      retries = hook['parameters']['retries'] || Astute.config.puppet_retries

      ret = {'error' => nil}
      perform_with_limit(hook['uids']) do |node_uids|
        result = run_puppet(
          @ctx,
          node_uids,
          hook['parameters']['puppet_manifest'],
          hook['parameters']['puppet_modules'],
          hook['parameters']['cwd'],
          timeout,
          retries
        )
        unless result
          ret['error'] = "Puppet run failed. Check puppet logs for details"
          Astute.logger.warn(ret['error'])
        end
      end

      ret
    end #puppet_hook

    def upload_file_hook(hook)
      validate_presence(hook, 'uids')
      validate_presence(hook['parameters'], 'path')
      validate_presence(hook['parameters'], 'data')

      hook['parameters']['content'] = hook['parameters']['data']

      ret = {'error' => nil}
      perform_with_limit(hook['uids']) do |node_uids|
        status = upload_file(@ctx, node_uids, hook['parameters'])
        if status == false
          ret['error'] = 'File upload failed'
        end
      end

      ret
    end

    def upload_files_hook(hook)
      validate_presence(hook['parameters'], 'nodes')
      ret = {'error' => nil}
      hook['parameters']['nodes'].each do |node|
        node['files'].each do |file|
          parameters = {
                  'content' => file['data'],
                  'path' => file['dst'],
                  'permissions' => file['permissions'] || '0644',
                  'dir_permissions' => file['dir_permissions'] || '0755',
                }
          status = upload_file(@ctx, node['uid'], parameters)
          if !status
            ret['error'] = 'File upload failed'
          end
        end
      end

      ret
    end

    def shell_hook(hook)
      validate_presence(hook, 'uids')
      validate_presence(hook['parameters'], 'cmd')


      timeout = hook['parameters']['timeout'] || 300
      cwd = hook['parameters']['cwd'] || "/"
      retries = hook['parameters']['retries'] || Astute.config.mc_retries
      interval = hook['parameters']['interval'] || Astute.config.mc_retry_interval
      shell_command = "cd #{cwd} && #{hook['parameters']['cmd']}"

      ret = {'error' => nil}

      perform_with_limit(hook['uids']) do |node_uids|
        Timeout::timeout(timeout) do
          succeed = run_shell_command(
            @ctx,
            node_uids,
            shell_command,
            retries,
            interval,
            timeout,
            cwd
          )

          ret['error'] = "Failed to run command #{shell_command}" unless succeed
        end
      end

      ret
    rescue Astute::MClientTimeout, Astute::MClientError, Timeout::Error => e
      ret['error']  = "command: #{shell_command}" \
                      "\n\nTask: #{@ctx.task_id}: " \
                      "shell timeout error: #{e.message}\n" \
                      "Task timeout: #{timeout}, " \
                      "Retries: #{hook['parameters']['retries']}"
      Astute.logger.error(ret['error'])

      ret
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

      ret = {'error' => nil}

      perform_with_limit(hook['uids']) do |node_uids|
        succeed = run_shell_command(
          @ctx,
          node_uids,
          rsync_cmd,
          10,
          Astute.config.mc_retry_interval,
          timeout
        )

        ret = {'error' => "Failed to perform sync from #{source} to #{path}"} unless succeed
      end

      ret
    end # sync_hook

    def reboot_hook(hook)
      validate_presence(hook, 'uids')
      hook_timeout = hook['parameters']['timeout'] || 300

      control_time = {}

      perform_with_limit(hook['uids']) do |node_uids|
        control_time.merge!(boot_time(node_uids))
      end

      #TODO(vsharshov): will be enough for safe reboot without exceptions?
      perform_with_limit(hook['uids']) do |node_uids|
        run_shell_without_check(@ctx, node_uids, 'reboot', timeout=10)
      end

      already_rebooted = Hash[hook['uids'].collect { |uid| [uid, false] }]

      ret = {'error' => nil}

      begin
        Timeout::timeout(hook_timeout) do
          while already_rebooted.values.include?(false)
            sleep hook_timeout/10

            results = boot_time(already_rebooted.select { |k, v| !v }.keys)
            results.each do |node_id, time|
              next if already_rebooted[node_id]
              already_rebooted[node_id] = (time.to_i != control_time[node_id].to_i)
            end
          end
        end
      rescue Timeout::Error => e
        Astute.logger.warn("Time detection (#{hook_timeout} sec) for node reboot has expired")
      end

      if already_rebooted.values.include?(false)
        fail_nodes = already_rebooted.select {|k, v| !v }.keys
        ret['error'] = "Reboot command failed for nodes #{fail_nodes}. Check debug output for details"
        Astute.logger.warn(ret['error'])
      end

      ret
    end # reboot_hook

    def validate_presence(data, key)
      raise "Missing a required parameter #{key}" unless data[key].present?
    end

    def run_puppet(context, node_uids, puppet_manifest, puppet_modules, cwd, timeout, retries)
      # Prevent send report status to Nailgun
      hook_context = Context.new(context.task_id, HookReporter.new, LogParser::NoParsing.new)
      nodes = node_uids.map { |node_id| {'uid' => node_id.to_s, 'role' => 'hook'} }

      Timeout::timeout(timeout) {
        PuppetdDeployer.deploy(
          hook_context,
          nodes,
          retries=retries,
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

    def run_shell_command(context, node_uids, cmd, retries, interval, timeout=60, cwd="/tmp")
      (retries + 1).times.each do |retry_number|
        shell = MClient.new(context,
                            'execute_shell_command',
                            node_uids,
                            check_result=true,
                            timeout=timeout,
                            retries=1)

        begin
          responses = shell.execute(:cmd => cmd, :cwd => cwd)
        rescue MClientTimeout, MClientError => e
          Astute.logger.error "#{context.task_id}: cmd: #{cmd} \n" \
            "mcollective error: #{e.message}"
          next
        end
        responses.each do |response|
          Astute.logger.debug(
            "#{context.task_id}: cmd: #{cmd}\n" \
            "cwd: #{cwd}\n" \
            "stdout: #{response[:data][:stdout]}\n" \
            "stderr: #{response[:data][:stderr]}\n" \
            "exit code: #{response[:data][:exit_code]}")
        end

        node_uids -= responses.select { |response| response[:data][:exit_code] == 0 }
                              .map { |response| response[:sender] }
        return true if node_uids.empty?
        Astute.logger.warn "Problem while performing cmd on nodes: #{node_uids}. " \
          "Retrying... Attempt #{retry_number} of #{retries}"
        sleep interval
      end

      false
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
      nodes.each_slice(Astute.config[:max_nodes_per_call]) do |part|
        block.call(part)
      end
    end

    def run_shell_without_check(context, node_uids, cmd, timeout=10)
      shell = MClient.new(
        context,
        'execute_shell_command',
        node_uids,
        check_result=false,
        timeout=timeout
      )
      results = shell.execute(:cmd => cmd)
      results.inject({}) do |h, res|
        Astute.logger.debug(
          "#{context.task_id}: cmd: #{cmd}\n" \
          "stdout: #{res.results[:data][:stdout]}\n" \
          "stderr: #{res.results[:data][:stderr]}\n" \
          "exit code: #{res.results[:data][:exit_code]}")
        h.merge({res.results[:sender] => res.results[:data][:stdout].chomp})
      end
    end

    def boot_time(uids)
      run_shell_without_check(
        @ctx,
        uids,
        "stat --printf='%Y' /proc/1",
        timeout=10
      )
    end

  end # class

  class HookReporter
    def report(msg)
      Astute.logger.debug msg
    end
  end

end # module
