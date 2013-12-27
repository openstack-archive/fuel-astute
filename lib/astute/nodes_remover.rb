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
                         Astute.config[:MC_RETRIES], Astute.config[:MC_RETRY_INTERVAL])

      retry_remove_nodes(inaccessible_nodes, erased_nodes,
                         Astute.config[:MC_RETRIES], Astute.config[:MC_RETRY_INTERVAL])

      answer = {'nodes' => serialize_nodes(erased_nodes)}

      if inaccessible_nodes.present?
        serialized_inaccessible_nodes = serialize_nodes(inaccessible_nodes)
        answer.merge!({'inaccessible_nodes' => serialized_inaccessible_nodes})

        Astute.logger.warn "#{@ctx.task_id}: Removing of nodes #{@nodes.uids.inspect} finished " \
                           "with errors. Nodes #{serialized_inaccessible_nodes.inspect} are inaccessible"
      end

      if error_nodes.present?
        serialized_error_nodes = serialize_nodes(error_nodes)
        answer.merge!({'status' => 'error', 'error_nodes' => serialized_error_nodes})

        Astute.logger.error "#{@ctx.task_id}: Removing of nodes #{@nodes.uids.inspect} finished " \
                            "with errors: #{serialized_error_nodes.inspect}"
      end
      Astute.logger.info "#{@ctx.task_id}: Finished removing of nodes: #{@nodes.uids.inspect}"

      answer
    end

    private

    def serialize_nodes(nodes)
      nodes.nodes.map(&:to_hash)
    end

    def remove_nodes(nodes)
      if nodes.empty?
        Astute.logger.info "#{@ctx.task_id}: Nodes to remove are not provided. Do nothing."
        return Array.new(3){ NodesHash.new }
      end

      responses = mclient_remove_nodes(nodes)
      inaccessible_uids = nodes.uids - responses.map { |response| response[:sender] }
      inaccessible_nodes = NodesHash.build(inaccessible_uids.map do |uid|
        {'uid' => uid, 'error' => 'Node not answered by RPC.'}
      end)
      error_nodes = NodesHash.new
      erased_nodes = NodesHash.new
      responses.each do |response|
        node = Node.new('uid' => response[:sender])
        if response[:statuscode] != 0
          node['error'] = "RPC agent 'erase_node' failed. Result: #{response.inspect}"
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
      Astute.logger.info "#{@ctx.task_id}: Starting removing of nodes: #{nodes.uids.inspect}"
      remover = MClient.new(@ctx, "erase_node", nodes.uids.sort, check_result=false)
      responses = remover.erase_node(:reboot => @reboot)
      Astute.logger.debug "#{@ctx.task_id}: Data received from nodes: #{responses.inspect}"
      responses.map(&:results)
    end

  end
end
