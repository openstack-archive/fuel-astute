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

require 'net/ssh/multi'
require 'timeout'

module Astute
  class Ssh

    SSH_RETRY_TIMEOUT = 30

    def self.execute(ctx, nodes, cmd, timeout=60, retries=Astute.config.MC_RETRIES)
      nodes_to_process = nodes.map { |n| n['slave_name'] }

      Astute.logger.debug "Run shell command '#{cmd}' using ssh"
      ready_nodes = []
      error_nodes = []

      retries.times do |i|
        Astute.logger.debug "Run shell command using ssh. Retry #{i}"
        Astute.logger.debug "Affected nodes: #{nodes_to_process}"

        new_ready_nodes, new_error_nodes, nodes_to_process = run_remote_command(nodes_to_process, cmd, timeout)
        Astute.logger.debug "Retry result: "\
          "success nodes: #{new_ready_nodes}, "\
          "error nodes: #{new_error_nodes}, "\
          "inaccessible nodes: #{nodes_to_process}"

        ready_nodes += new_ready_nodes
        error_nodes += new_error_nodes

        break if nodes_to_process.empty?
        sleep SSH_RETRY_TIMEOUT
      end

      inaccessible_nodes = nodes_to_process
      nodes_uids = nodes.map { |n| n['uid'] }

      answer = {'nodes' => to_report_format(ready_nodes, nodes)}
      if inaccessible_nodes.present?
        answer.merge!({'inaccessible_nodes' => to_report_format(inaccessible_nodes, nodes)})
        Astute.logger.warn "#{ctx.task_id}: Running shell command on nodes #{nodes_uids.inspect} finished " \
                           "with errors. Nodes #{answer['inaccessible_nodes'].inspect} are inaccessible"
      end

      if error_nodes.present?
        answer.merge!({'status' => 'error', 'error_nodes' => to_report_format(error_nodes, nodes)})

        Astute.logger.error "#{ctx.task_id}: Running shell command on nodes #{nodes_uids.inspect} finished " \
                            "with errors: #{answer['error_nodes'].inspect}"
      end
      Astute.logger.info "#{ctx.task_id}: Finished running shell command: #{nodes_uids.inspect}"

      answer
    end


    private

    def self.to_report_format(slave_names, nodes)
      result_nodes = nodes.select { |n| slave_names.include?(n['slave_name']) }
      result_nodes.inject([]) do |result, node|
        result << {'uid' => node['uid']} if node['uid']
        result
      end
    end

    def self.run_remote_command(nodes, cmd, timeout)
      servers = []
      channel = nil

      Net::SSH::Multi.start(:concurrent_connections => Astute.config.MAX_NODES_PER_CALL,
                            :on_error => :warn) do |session|

        # Require env['HOME']
        nodes.each do |name|
          session.use name,
                      :user => 'root',
                      :host_key => 'ssh-rsa',
                      :keys => ['~/.ssh/id_rsa']
        end
        servers = session.servers_for

        # execute commands on all servers
        # FIXME: debug not show a messages if command contain a several
        # strings
        channel = session.exec cmd do |ch, stream, data|
          Astute.logger.debug "[#{ch[:host]} : #{stream}] #{data}"
        end

        # run the aggregated event loop
        Timeout::timeout(timeout) { session.loop }
      end

      erased_nodes = []
      inaccessible_nodes = []
      servers.each do |s|
        s.failed? ? inaccessible_nodes << s.host : erased_nodes << s.host
      end

      # if channel.each do |s| { |c| c[:exit_status] != 0 }
      #   s[:exit_status] == 0 ?
      # end

      # TODO: support exit code from shell command
      [erased_nodes, [], inaccessible_nodes]
    rescue Timeout::Error
      Astute.logger.debug "SSH session is closed due to the achievement of a timeout"
      [[], [], nodes]
    end
  end
end
