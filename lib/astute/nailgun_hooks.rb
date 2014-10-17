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

        case hook['type']
        when 'sync' then sync_hook(hook)
        when 'shell' then shell_hook(hook)
        when 'upload_file' then upload_file_hook(hook)
        when 'puppet' then puppet_hook(hook)
        else raise "Unknown hook type #{hook['type']}"
        end
      end
    end

    private

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

      perform_with_limit(hook['uids']) do |node_uids|
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

      hook['parameters']['content'] = hook['parameters']['data']

      perform_with_limit(hook['uids']) do |node_uids|
        upload_file(@ctx, node_uids, hook['parameters'])
      end
    end

    def shell_hook(hook)
      validate_presence(hook, 'uids')
      validate_presence(hook['parameters'], 'cmd')


      timeout = hook['parameters']['timeout'] || 300
      cwd = hook['parameters']['cwd'] || "~/"

      shell_command = "cd #{cwd} && #{hook['parameters']['cmd']}"

      perform_with_limit(hook['uids']) do |node_uids|
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

      perform_with_limit(hook['uids']) do |node_uids|
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

    def upload_file(context, node_uids, mco_params={})
      upload_mclient = Astute::MClient.new(context, "uploadfile", Array(node_uids))

      mco_params['overwrite'] = false if mco_params['overwrite'].nil?
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
    rescue MClientTimeout, MClientError => e
      Astute.logger.error("#{context.task_id}: mcollective upload_file agent error: #{e.message}")
    end

    def perform_with_limit(nodes, &block)
      nodes.each_slice(Astute.config[:MAX_NODES_PER_CALL]) do |part|
        block.call(part)
      end
    end

  end # class
end # module
