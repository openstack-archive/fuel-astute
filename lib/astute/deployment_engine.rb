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

KEY_DIR = "/var/lib/astute"

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

          # Sync puppet manifests and modules to every node (emulate puppet master)
          sync_puppet_manifests(part)
        end
      rescue => e
        Astute.logger.error("Unexpected error #{e.message} traceback #{e.format_backtrace}")
        raise e
      end

      # Sort by priority (the lower the number, the higher the priority)
      # and send groups to deploy
      deployment_info.sort_by { |f| f['priority'] }.group_by{ |f| f['priority'] }.each do |_, nodes|
        # Prevent attempts to run several deploy on a single node.
        # This is possible because one node
        # can perform multiple roles.
        group_by_uniq_values(nodes).each do |nodes_group|
          # Prevent deploy too many nodes at once
          nodes_group.each_slice(Astute.config[:MAX_NODES_PER_CALL]) { |part| deploy_piece(part) }
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
      sync_mclient = MClient.new(@ctx, "puppetsync", deployment_info.map{ |n| n['uid'] }.uniq)
      master_ip = deployment_info.first['master_ip']
      # Paths /puppet/modules and /puppet/manifests/ in master node set by FUEL
      # Check fuel source code /deployment/puppet/nailgun/manifests/puppetsync.pp
      sync_mclient.rsync(:modules_source => "rsync://#{master_ip}:/puppet/modules/",
                         :manifests_source => "rsync://#{master_ip}:/puppet/manifests/"
                        )
    end

    def generate_ssh_keys(deployment_id, overwrite=false)
      raise "Deployment_id is missing" unless deployment_id
      Astute.config.PUPPET_SSH_KEYS.each do |key_name|
        dir_path = File.join(KEY_DIR, deployment_id.to_s, key_name)
        key_path = File.join(dir_path, key_name)
        FileUtils.mkdir_p dir_path
        return if File.exist?(key_path) && !overwrite

        # Generate 2 keys(<name> and <name>.pub) and save it to <KEY_DIR>/<name>/
        File.delete key_path if File.exist? key_path
        result = system("ssh-keygen -b 2048 -t rsa -N '' -f #{key_path}")
        raise "Could not generate ssh key!" unless result
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

    def nodes_status(nodes, status, data_to_merge)
      {
        'nodes' => nodes.map do |n|
          {'uid' => n['uid'], 'status' => status, 'role' => n['role']}.merge(data_to_merge)
        end
      }
    end

  end
end
