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

require 'fileutils'
require 'popen4'
require 'uri'

KEY_DIR = "/var/lib/astute"
SYNC_RETRIES = 10

module Astute
  class DeploymentEngine

    def initialize(context)
      if self.class.superclass.name == 'Object'
        raise "Instantiation of this superclass is not allowed. Please subclass from #{self.class.name}."
      end
      @ctx = context
    end

    def deploy(deployment_info)
      raise "Deployment info are not provided!" if deployment_info.blank?

      @ctx.deploy_log_parser.deploy_type = deployment_info.first['deployment_mode']
      Astute.logger.info "Deployment mode #{@ctx.deploy_log_parser.deploy_type}"

      begin
        # Generate ssh keys to future uploading to all cluster nodes
        generate_ssh_keys(deployment_info.first['deployment_id'])

        # Prevent to prepare too many nodes at once
        deployment_info.uniq { |n| n['uid'] }.each_slice(Astute.config[:MAX_NODES_PER_CALL]) do |part|
          # Upload ssh keys from master node to all cluster nodes.
          # Will be used by puppet after to connect nodes between themselves.
          upload_ssh_keys(part.map{ |n| n['uid'] }, part.first['deployment_id'])

          # Update packages source list
          update_repo_sources(part) if part.first['repo_metadata']

          # Sync puppet manifests and modules to every node (emulate puppet master)
          sync_puppet_manifests(part)

          # Unlock puppet (can be lock if puppet was killed by user)
          enable_puppet_deploy(part.map{ |n| n['uid'] })

          # Sync time
          sync_time(part.map{ |n| n['uid'] })
        end
      rescue => e
        Astute.logger.error("Unexpected error #{e.message} traceback #{e.format_backtrace}")
        raise e
      end

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

    # Sync puppet manifests and modules to every node
    def sync_puppet_manifests(deployment_info)
      master_ip = deployment_info.first['master_ip']
      modules_source = deployment_info.first['puppet_modules_source'] || "rsync://#{master_ip}:/puppet/modules/"
      manifests_source = deployment_info.first['puppet_manifests_source'] || "rsync://#{master_ip}:/puppet/manifests/"
      # Paths to Puppet modules and manifests at the master node set by Nailgun
      # Check fuel source code /deployment/puppet/nailgun/manifests/puppetsync.pp
      schemas = [modules_source, manifests_source].map do |url|
        begin
          URI.parse(url).scheme
        rescue URI::InvalidURIError => e
          raise DeploymentEngineError, e.message
        end
      end

      if schemas.select{ |x| x != schemas.first }.present?
        raise DeploymentEngineError, "Scheme for puppet_modules_source '#{schemas.first}' and" \
                                     " puppet_manifests_source '#{schemas.last}' not equivalent!"
      end

      sync_mclient = MClient.new(@ctx, "puppetsync", deployment_info.map{ |n| n['uid'] }.uniq)
      case schemas.first
      when 'rsync'
        begin
          sync_mclient.rsync(:modules_source => modules_source,
                             :manifests_source => manifests_source
                            )
        rescue MClientError => e
          sync_retries ||= 0
          sync_retries += 1
          if sync_retries < SYNC_RETRIES
            Astute.logger.warn("Rsync problem. Try to repeat: #{sync_retries} attempt")
            retry
          end
          raise e
        end
      else
        raise DeploymentEngineError, "Unknown scheme '#{schemas.first}' in #{modules_source}"
      end
    end

    def generate_ssh_keys(deployment_id, overwrite=false)
      raise "Deployment_id is missing" unless deployment_id
      Astute.config.PUPPET_SSH_KEYS.each do |key_name|
        dir_path = File.join(KEY_DIR, deployment_id.to_s, key_name)
        key_path = File.join(dir_path, key_name)

        FileUtils.mkdir_p dir_path
        raise DeploymentEngineError, "Could not create directory #{dir_path}" unless File.directory?(dir_path)

        next if File.exist?(key_path) && !overwrite

        # Generate 2 keys(<name> and <name>.pub) and save it to <KEY_DIR>/<name>/
        File.delete key_path if File.exist? key_path

        cmd = "ssh-keygen -b 2048 -t rsa -N '' -f #{key_path} 2>&1"
        status, stdout, _ = run_system_command cmd

        error_msg = "Could not generate ssh key! Command: #{cmd}, output: #{stdout}, exit code: #{status}"
        raise DeploymentEngineError, error_msg if status != 0
      end
    end

    def upload_ssh_keys(node_uids, deployment_id, overwrite=false)
      Astute.config.PUPPET_SSH_KEYS.each do |key_name|
        upload_mclient = MClient.new(@ctx, "uploadfile", node_uids)
        [key_name, key_name + ".pub"].each do |ssh_key|
          source_path = File.join(KEY_DIR, deployment_id.to_s, key_name, ssh_key)
          destination_path = File.join(KEY_DIR, key_name, ssh_key)
          content = File.read(source_path)
          upload_mclient.upload(:path => destination_path,
                                :content => content,
                                :user_owner => 'root',
                                :group_owner => 'root',
                                :permissions => '0600',
                                :dir_permissions => '0700',
                                :overwrite => true,
                                :parents => true
                               )
        end
      end
    end

    def update_repo_sources(deployment_info)
      content = generate_repo_source(deployment_info)
      upload_repo_source(deployment_info, content)
      regenerate_metadata(deployment_info)
    end

    def generate_repo_source(deployment_info)
      ubuntu_source = -> (name, url) { "deb #{url}" }
      centos_source = -> (name, url) do
        ["[#{name.downcase}]", "name=#{name}", "baseurl=#{url}", "gpgcheck=0"].join("\n")
      end

      formatter = case target_os(deployment_info)
                  when 'centos' then centos_source
                  when 'ubuntu' then ubuntu_source
                  end

      content = []
      deployment_info.first['repo_metadata'].each do |name, url|
        content << formatter.call(name,url)
      end
      content.join("\n")
    end

    def upload_repo_source(deployment_info, content)
      upload_mclient = MClient.new(@ctx, "uploadfile", deployment_info.map{ |n| n['uid'] }.uniq)
      destination_path = case target_os(deployment_info)
                         when 'centos' then '/etc/yum.repos.d/nailgun.repo'
                         when 'ubuntu' then '/etc/apt/sources.list'
                         end
      upload_mclient.upload(:path => destination_path,
                      :content => content,
                      :user_owner => 'root',
                      :group_owner => 'root',
                      :permissions => '0644',
                      :dir_permissions => '0755',
                      :overwrite => true,
                      :parents => true
                     )
    end

    def regenerate_metadata(deployment_info)
      cmd = case target_os(deployment_info)
            when 'centos' then "yum clean all"
            when 'ubuntu' then "apt-get clean; apt-get update"
            end

      succeeded = false
      nodes_uids = deployment_info.map{ |n| n['uid'] }.uniq
      Astute.config.MC_RETRIES.times.each do
        succeeded = run_shell_command_remotely(nodes_uids, cmd)
        return if succeeded
        sleep Astute.config.MC_RETRY_INTERVAL
      end

      if !succeeded
        raise DeploymentEngineError, "Run command: '#{cmd}' in nodes: #{nodes_uids} fail." \
                                     " Check debug output for more information"
      end
    end

    def target_os(deployment_info)
      os = deployment_info.first['cobbler']['profile']
      case os
      when 'centos-x86_64' then 'centos'
      when 'ubuntu_1204_x86_64' then 'ubuntu'
      else
        raise DeploymentEngineError, "Unknown system #{os}"
      end
    end


    def sync_time(nodes_uids)
      cmd = "ntpdate -u $(egrep '^server' /etc/ntp.conf | sed '/^#/d' | awk '{print $2}')"
      succeeded = false

      Astute.config.MC_RETRIES.times.each do
        succeeded = run_shell_command_remotely(nodes_uids, cmd)
        return if succeeded
        sleep Astute.config.MC_RETRY_INTERVAL
      end

      if !succeeded
        Astute.logger.warn "Run command: '#{cmd}' in nodes: #{nodes_uids} fail. " \
                           "Check debug output for more information. You can try "\
                           "to fix it problem manually."
      end
    end

    def run_system_command(cmd)
      pid, _, stdout, stderr = Open4::popen4 cmd
      _, status = Process::waitpid2 pid
      return status.exitstatus, stdout, stderr
    end

    def run_shell_command_remotely(node_uids, cmd)
      shell = MClient.new(@ctx,
                          'execute_shell_command',
                          node_uids,
                          check_result=true,
                          timeout=60,
                          retries=1)

      #TODO: return result for all nodes not only for first
      response = shell.execute(:cmd => cmd).first
      Astute.logger.debug("#{@ctx.task_id}: cmd: #{cmd}
                                            stdout: #{response[:data][:stdout]}
                                            stderr: #{response[:data][:stderr]}
                                            exit code: #{response[:data][:exit_code]}")
      response.fetch(:data, {})[:exit_code] == 0
    end

    def enable_puppet_deploy(node_uids)
      puppetd = MClient.new(@ctx, "puppetd", node_uids)
      puppetd.enable
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

  end
end
