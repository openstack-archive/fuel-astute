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

    def self.execute(ctx, nodes, cmd, timeout=60, retries=Astute.config.SSH_RETRIES)
      nodes_to_process = nodes.map { |n| n['admin_ip'] }

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

        sleep Astute.config.SSH_RETRY_TIMEOUT
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
      result_nodes = nodes.select { |n| slave_names.include?(n['admin_ip']) }
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
        nodes.each do |name|
          session.use name,
                      :user => 'root',
                      :host_key => 'ssh-rsa',
                      :keys => ['/root/.ssh/id_rsa']
        end
        servers = session.servers_for

        # execute commands on all servers
        # FIXME: debug not show a messages if command contain a several
        # strings
        channel = session.exec cmd do |ch, success|

          ch.on_data do |ichannel, data|
            Astute.logger.debug "[#{ch[:host]} : #{ichannel}] #{data}"
          end

          ch.on_request "exit-status" do |_ichannel, data|
            exit_status = data.read_long
          end
        end

        Timeout::timeout(timeout) { session.loop }
      end

      detect_status(servers)
    rescue Timeout::Error
      Astute.logger.debug "SSH session is closed due to the achievement of a timeout"
      return [[], [], nodes] unless servers
      exception_process(servers)
    rescue Net::SSH::Disconnect
      Astute.logger.debug "SSH connection closed by remote host"
      exception_process(servers)
    end

    def self.exception_process(servers)
      servers.each do |s|
        if s.busy?
          # Pending connection could not be shutdown, but always return busy as true
          s.session.shutdown! if s.session.channels.present?
          s.fail!
        end
      end
      detect_status(servers)
    end

    # TODO: support exit code from shell command
    def self.detect_status(servers)
      executed_nodes = []
      inaccessible_nodes = []
      servers.each do |s|
        s.failed? ? inaccessible_nodes << s.host : executed_nodes << s.host
      end
      [executed_nodes, [], inaccessible_nodes]
    end

  end
end
