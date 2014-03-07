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

require "json"
require "tempfile"
require "socket"
require "timeout"

module MCollective
  module Agent
    class Net_probe<RPC::Agent
      def startup_hook
        @pattern = "/var/tmp/net-probe-dump*"
      end

      action "multicast_listen" do
        config = JSON.parse(request[:nodes])[get_uid]
        cmd = "fuel-netcheck multicast serve listen --config='#{config.to_json}'"
        reply[:status] = run(cmd, :stdout => :out, :stderr => :err)
      end

      action "multicast_send" do
        cmd = "fuel-netcheck multicast send"
        reply[:status] = run(cmd, :stdout => :out, :stderr => :err)
      end

      action "multicast_info" do
        reply[:status] = run("fuel-netcheck multicast info",
                              :stdout => :out, :stderr => :err)
        run("fuel-netcheck multicast clean")
      end

      action "start_frame_listeners" do
        cleanup_netprobe
        start_frame_listeners
      end

      action "send_probing_frames" do
        send_probing_frames
      end

      action "get_probing_info" do
        get_probing_info
      end

      action "stop_frame_listeners" do
        stop_frame_listeners
      end

      action "dhcp_discover" do
        interfaces = request[:interfaces][get_uid]
        format = request.data[:format] || "json"
        timeout = request.data[:timeout] || 2
        repeat = request.data[:repeat] || 1
        cmd = "dhcpcheck vlans '#{interfaces}' --timeout=#{timeout} --format=#{format} --repeat=#{repeat} "
        reply[:status] = run(cmd, :stdout => :out, :stderr => :err)
      end

      private

      def get_uid
        File.open('/etc/nailgun_uid') do |fo|
          uid = fo.gets.chomp
          return uid
        end
      end

      def cleanup_netprobe
        status = run("pkill net_probe.py && sleep 2 && pgrep net_probe.py")
        reply.fail! "Cant stop net_probe.py execution." unless status == 1
      end

      def start_frame_listeners
        validate :interfaces, String
        config = {
          "action" => "listen",
          "interfaces" => JSON.parse(request[:interfaces]),
          "dump_file" => "/var/tmp/net-probe-dump",
          "ready_address" => "127.0.0.1",
          "ready_port" => 31338,
        }

        if request.data.key?('config')
          config.merge!(JSON.parse(request[:config]))
        end

        # we want to be sure that there is no frame listeners running
        stop_frame_listeners

        # wipe out old stuff before start
        Dir.glob(@pattern).each do |file|
          File.delete file
        end

        begin
          socket = Socket.new( Socket::AF_INET, Socket::SOCK_STREAM, 0)
          sockaddr = Socket.pack_sockaddr_in(config['ready_port'], config['ready_address'])
          socket.bind(sockaddr)
          socket.listen(1)
        rescue => e
          reply.fail! "Socket error: #{e.to_s}"
        else
          config_file = net_probe_config(config)
          cmd = "net_probe.py -c #{config_file.path}"
          pid = fork { `#{cmd}` }
          Process.detach(pid)

          # It raises Errno::ESRCH if there is no process, so we check that it runs
          sleep 1
          begin
            Process.kill(0, pid)
          rescue Errno::ESRCH
            reply.fail! "Failed to run '#{cmd}'"
          end

          begin
            Timeout::timeout(120) do
              client, clientaddr = socket.accept
              status = client.read
              client.close
              reply.fail! "Wrong listener status: '#{status}'" unless status =~ /READY/
            end
          rescue Timeout::Error
            stop_frame_listeners
            reply.fail! "Listener did not reported status"
          end
        ensure
          begin
            socket.shutdown
          rescue Errno::ENOTCONN
          end
          socket.close
        end
      end

      def send_probing_frames
        validate :interfaces, String
        config = { "action" => "generate", "uid" => get_uid,
                   "interfaces" => JSON.parse(request[:interfaces]) }
        if request.data.key?('config')
          config.merge!(JSON.parse(request[:config]))
        end

        config_file = net_probe_config(config)

        cmd = "net_probe.py -c #{config_file.path}"
        status = run(cmd, :stdout => :out, :stderr => :error)
        config_file.unlink

        reply.fail "Failed to send probing frames, cmd='#{cmd}' failed, config: #{config.inspect}" if status != 0
      end

      def get_probing_info
        stop_frame_listeners
        neighbours = Hash.new
        Dir.glob(@pattern).each do |file|
          p = JSON.load(File.read(file))
          neighbours.merge!(p)
        end
        reply[:neighbours] = neighbours
        reply[:uid] = get_uid
      end

      def net_probe_config(config)
        f = Tempfile.new "net_probe"
        f.write config.to_json
        f.close
        f
      end

      def stop_frame_listeners
        piddir = "/var/run/net_probe"
        pidfiles = Dir.glob(File.join(piddir, '*'))
        # Send SIGINT to all PIDs in piddir.
        pidfiles.each do |f|
          begin
            Process.kill("INT", File.basename(f).to_i)
          rescue Errno::ESRCH
            # Unlink pidfile if no such process.
            File.unlink(f)
          end
        end
        # Wait while all processes dump data and exit.
        while not pidfiles.empty? do
          pidfiles.each do |f|
            begin
              Process.getpgid(File.basename(f).to_i)
            rescue Errno::ESRCH
              begin
                File.unlink(f)
              rescue Errno::ENOENT
              end
            end
          end
          pidfiles = Dir.glob(File.join(piddir, '*'))
        end
      end
    end
  end
end

