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
require "base64"
require 'fileutils'

module MCollective
  module Agent
    class Erase_node < RPC::Agent

      action "erase_node" do
        erase_node
      end

      action "reboot_node" do
        reboot
      end

      private

      def erase_node
        request_reboot = request.data[:reboot]
        dry_run = request.data[:dry_run]
        error_msg = []
        reply[:status] = 0  # Shell exitcode behaviour

        prevent_discover unless dry_run

        begin
          get_boot_devices.each do |dev|
            erase_data(dev) unless dry_run
          end

          reply[:erased] = true
        rescue Exception => e
          reply[:erased] = false
          reply[:status] += 1
          msg = "MBR can't be erased. Reason: #{e.message};"
          Log.error(msg)
          error_msg << msg
        end

        begin
          reboot if not dry_run and request_reboot
          reply[:rebooted] = true
        rescue Exception => e
          reply[:rebooted] = false
          reply[:status] += 1
          msg = "Can't reboot node. Reason: #{e.message};"
          Log.error(msg)
          error_msg << "Can't reboot node. Reason: #{e.message};"
        end

        unless error_msg.empty?
          reply[:error_msg] = error_msg.join(' ')
        end
      end

      def get_boot_devices
        raise "Path /sys/block does not exist" unless File.exists?("/sys/block")
        Dir["/sys/block/*"].inject([]) do |blocks, block_device_dir|
          basename_dir = File.basename(block_device_dir)
          major = `udevadm info --query=property --name=#{basename_dir} | grep MAJOR`.strip.split(/\=/)[-1]
          if File.exists?("/sys/block/#{basename_dir}/removable")
            removable = File.open("/sys/block/#{basename_dir}/removable") { |f| f.read_nonblock(1024).strip }
          end
          # Look at https://github.com/torvalds/linux/blob/master/Documentation/devices.txt
          # Please also update the device codes here
          # https://github.com/stackforge/fuel-web/blob/master/bin/agent#L274
          if major =~ /^(3|8|104|105|106|107|108|109|110|111|202|252|253)$/ && removable =~ /^0$/
            blocks << basename_dir
          end
          blocks
        end
      end

      def reboot
        cmd = '/bin/sleep 5; sysctl -w kernel.sysrq=1; echo u > /proc/sysrq-trigger; echo s > /proc/sysrq-trigger; echo b > /proc/sysrq-trigger'
        debug_msg("Run node rebooting command '#{cmd}'")
        pid = fork { system(cmd) }
        Process.detach(pid)
      end

      def erase_data(dev, length=1, offset=0)
        cmd = "dd if=/dev/zero of=/dev/#{dev} bs=1M count=#{length} skip=#{offset} oflag=direct"
        status = system(cmd)
        debug_msg("Run device erasing command '#{cmd}' returned '#{status}'")

        status
      end

      # Prevent discover by agent while node rebooting
      def prevent_discover
        lock_path = '/var/run/nodiscover'
        debug_msg("Create file for discovery preventing #{lock_path}")
        FileUtils.touch(lock_path)
      end

      # In case of node erasing we can lose all
      # debug messages, lets send them to orchestrator
      def debug_msg(msg)
        reply[:debug_msg] = [] unless reply[:debug_msg]
        Log.debug(msg)
        reply[:debug_msg] << msg
      end

    end
  end
end
