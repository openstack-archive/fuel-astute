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
  class NodesRemover

    def initialize(ctx, nodes, reboot=true)
      @ctx = ctx
      @nodes = NodesHash.build(nodes)
      @reboot = reboot
    end

    def remove
      # TODO(mihgen):  1. Nailgun should process node error message
      #   2. Should we rename nodes -> removed_nodes array?
      #   3. If exception is raised here, we should not fully fall into error, but only failed node
      erased_nodes, error_nodes, inaccessible_nodes = remove_nodes(@nodes)
      retry_remove_nodes(error_nodes, erased_nodes,
                         Astute.config[:mc_retries], Astute.config[:mc_retry_interval])

      retry_remove_nodes(inaccessible_nodes, erased_nodes,
                         Astute.config[:mc_retries], Astute.config[:mc_retry_interval])

      answer = {'nodes' => serialize_nodes(erased_nodes)}

      if inaccessible_nodes.present?
        serialized_inaccessible_nodes = serialize_nodes(inaccessible_nodes)
        answer.merge!({'inaccessible_nodes' => serialized_inaccessible_nodes})

        Astute.logger.warn "#{@ctx.task_id}: Removing of nodes\n#{@nodes.uids.pretty_inspect} finished " \
                           "with errors. Nodes\n#{serialized_inaccessible_nodes.pretty_inspect} are inaccessible"
      end

      if error_nodes.present?
        serialized_error_nodes = serialize_nodes(error_nodes)
        answer.merge!({'status' => 'error', 'error_nodes' => serialized_error_nodes})

        Astute.logger.error "#{@ctx.task_id}: Removing of nodes\n#{@nodes.uids.pretty_inspect} finished " \
                            "with errors:\n#{serialized_error_nodes.pretty_inspect}"
      end
      Astute.logger.info "#{@ctx.task_id}: Finished removing of nodes:\n#{@nodes.uids.pretty_inspect}"

      answer
    end

    private

    def serialize_nodes(nodes)
      nodes.nodes.map(&:to_hash)
    end

    # When :mclient_remove property is true (the default behavior), we send
    # the node to mclient for removal (MBR, restarting etc), if it's false
    # the node is skipped from mclient
    def skipped_unskipped_mclient_nodes(nodes)
      mclient_skipped_nodes = NodesHash.build(
        nodes.values.select { |node| not node.fetch(:mclient_remove, true) }
      )
      mclient_nodes = NodesHash.build(
        nodes.values.select { |node| node.fetch(:mclient_remove, true) }
      )

      Astute.logger.debug "#{@ctx.task_id}: Split nodes: #{mclient_skipped_nodes}, #{mclient_nodes}"

      [mclient_skipped_nodes, mclient_nodes]
    end

    def fetch_already_removed_nodes(nodes, erased_nodes)
      nodes.each do |uid, node|
        if node.boot_time && node.boot_time > 0
          boot_time = get_boot_time(uid)
          if boot_time && boot_time > 0 && boot_time != node.boot_time
            erased_node = Node.new('uid' => uid)
            nodes.delete uid
            erased_nodes << erased_node
            Astute.logger.info "#{@ctx.task_id}: Node #{uid} is removed already, skipping"
          end
        else
          boot_time = get_boot_time(uid)
          node.boot_time = boot_time if boot_time && boot_time > 0
        end
      end
    end

    def remove_nodes(nodes)
      if nodes.empty?
        Astute.logger.info "#{@ctx.task_id}: Nodes to remove are not provided. Do nothing."
        return Array.new(3){ NodesHash.new }
      end

      erased_nodes, mclient_nodes = skipped_unskipped_mclient_nodes(nodes)
      fetch_already_removed_nodes(mclient_nodes, erased_nodes)
      responses = mclient_remove_nodes(mclient_nodes)
      inaccessible_uids = mclient_nodes.uids - responses.map { |response| response[:sender] }
      inaccessible_nodes = NodesHash.build(inaccessible_uids.map do |uid|
        {'uid' => uid, 'error' => 'Node not answered by RPC.', 'boot_time' => mclient_nodes[uid][:boot_time]}
      end)
      error_nodes = NodesHash.new

      responses.each do |response|
        node = Node.new('uid' => response[:sender])
        if response[:statuscode] != 0
          node['error'] = "RPC agent 'erase_node' failed. Result:\n#{response.pretty_inspect}"
          error_nodes << node
        elsif @reboot && !response[:data][:rebooted]
          node['error'] = "RPC method 'erase_node' failed with message: #{response[:data][:error_msg]}"
          error_nodes << node
        else
          erased_nodes << node
        end
      end
      [erased_nodes, error_nodes, inaccessible_nodes]
    end

    def retry_remove_nodes(error_nodes, erased_nodes, retries=3, interval=1)
      retries.times do
        retried_erased_nodes = remove_nodes(error_nodes)[0]
        retried_erased_nodes.each do |uid, node|
          error_nodes.delete uid
          erased_nodes << node
        end
        return if error_nodes.empty?
        sleep(interval) if interval > 0
      end
    end

    def mclient_remove_nodes(nodes)
      Astute.logger.info "#{@ctx.task_id}: Starting removing of nodes:\n#{nodes.uids.pretty_inspect}"
      results = []

      nodes.uids.sort.each_slice(Astute.config[:max_nodes_per_remove_call]).with_index do |part, i|
        sleep Astute.config[:nodes_remove_interval] if i != 0
        results += mclient_remove_piece_nodes(part)
      end
      results
    end

    def mclient_remove_piece_nodes(nodes)
      remover = MClient.new(@ctx, "erase_node", nodes, check_result=false)
      responses = remover.erase_node(:reboot => @reboot)
      Astute.logger.debug "#{@ctx.task_id}: Data received from nodes:\n#{responses.pretty_inspect}"
      responses.map(&:results)
    end

    def run_shell_without_check(node_uid, cmd, timeout=2)
      shell = MClient.new(
        @ctx,
        'execute_shell_command',
        Array(node_uid),
        check_result=false,
        timeout=timeout
      )
      results = shell.execute(:cmd => cmd)
      Astute.logger.debug("Mcollective shell result: #{results}")
      if results && !results.empty?
        result = results.first
        Astute.logger.debug(
          "#{@ctx.task_id}: cmd: #{cmd}\n" \
          "stdout: #{result.results[:data][:stdout]}\n" \
          "stderr: #{result.results[:data][:stderr]}\n" \
          "exit code: #{result.results[:data][:exit_code]}")
        {
          :stdout =>result.results[:data][:stdout].chomp,
          :stderr => result.results[:data][:stderr].chomp,
          :exit_code => result.results[:data][:exit_code]
        }
      else
        Astute.logger.warn("#{@ctx.task_id}: Failed to run shell #{cmd} on " \
          "node #{node_uid}. Error will not raise because shell was run " \
          "without check")
        {}
      end
    end

    def get_boot_time(node_uid)
      run_shell_without_check(
        node_uid,
        "stat --printf='%Y' /proc/1",
        timeout=2
      )[:stdout].to_i
    rescue Astute::MClientTimeout, Astute::MClientError => e
      Astute.logger.debug("#{@ctx.task_id}: mcollective " \
        "get boot time command failed with error #{e.message}")
      return 0
    end

  end
end
