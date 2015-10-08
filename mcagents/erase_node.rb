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
require 'pathname'

module MCollective
  module Agent
    class Erase_node < RPC::Agent

      # Look at https://github.com/torvalds/linux/blob/master/Documentation/devices.txt
      # Please also update the device codes here
      # https://github.com/stackforge/fuel-web/blob/master/bin/agent#L43
      STORAGE_CODES = [3, 8, 65, 66, 67, 68, 69, 70, 71, 104, 105, 106, 107, 108, 109, 110, 111, 202, 252, 253, 259]

      AGENT_NODISCOVER_FILE = '/etc/nailgun-agent/nodiscover'

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

        begin
        prevent_discover unless dry_run
        rescue Exception => e
          msg = "Can't prevent discover. Reason: #{e.message}"
          Log.warn(msg)
        end

        begin
          reboot if !dry_run && request_reboot
          reply[:rebooted] = request_reboot
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

      def get_devices(type='all')
        raise "Path /sys/block does not exist" unless File.exists?("/sys/block")
        Dir["/sys/block/*"].inject([]) do |blocks, block_device_dir|
          basename_dir = File.basename(block_device_dir)
          dev_name = basename_dir.gsub(/!/, '/')
          dev_info = {}
          # Query device info from udev
          `udevadm info --query=property --name=#{dev_name}`.strip.split.each do |line|
            key, value = line.chomp.split(/\=/)
            dev_info[key.to_sym] = value
          end
          if File.exists?("/sys/block/#{basename_dir}/removable")
            removable = File.open("/sys/block/#{basename_dir}/removable") { |f| f.read_nonblock(1024).strip }
          end
          if File.exists?("/sys/block/#{basename_dir}/size")
            size = File.open("/sys/block/#{basename_dir}/size") { |f| f.read_nonblock(1024).strip }
          else
            size = 0
            debug_msg("Can not define device size. File /sys/block/#{basename_dir}/size not found.")
          end

          # Check device major number against our storage code list and exclude
          # removable devices
          if STORAGE_CODES.include?(dev_info[:MAJOR].to_i) && removable =~ /^0$/
            device_root_count = `lsblk -n -r "#{dev_info[:DEVNAME]}" | grep -c '\ /$'`.to_i
            # determine if the block device should be returned basked on the
            # requested type
            if (type.eql? 'all') or (type.eql? 'root' and device_root_count > 0) or (type.eql? 'data' and device_root_count == 0)
              debug_msg("get_devices(type=#{type}): adding #{dev_name}")
              blocks << {:name => dev_name, :size => size}
            end
          end
          blocks
        end
      end

      def reboot
        debug_msg("Beginning drive erase process")
        File.open('/proc/sys/kernel/sysrq','w') { |file| file.write("1\n") }
        # turning panic on oops and setting panic timeout to 10
        File.open('/proc/sys/kernel/panic_on_oops', 'w') {|file| file.write("1\n")}
        File.open('/proc/sys/kernel/panic','w') {|file| file.write("10\n")}

        begin
          # Delete data disks first, then OS drive to address bug #1437511
          (get_devices(type='data') + get_devices(type='root')).each do |dev|
            debug_msg("erasing #{dev[:name]}")
            # try an make sure any ext2/3/4 paritions won't cause a panic
            # when the file system gets erased
            suppress_fs_panic(dev[:name])
            # clear out the partitions of the device
            erase_partitions(dev[:name])
            # attempt to clear our the file system data on the device partitions
            # to ensure that we aren't left with extra filesystem data when we
            # reparition the devices next time.
            erase_data(dev[:name])
            erase_data(dev[:name], 1, dev[:size], '512')
          end

          reply[:erased] = true
        rescue Exception => e
          reply[:erased] = false
          reply[:status] += 1
          msg = "MBR can't be erased. Reason: #{e.message};"
          Log.error(msg)
          error_msg << msg
        end

        debug_msg("Drives erased, rebooting in 5 seconds.")
        # It should be noted that this is here so that astute will get a reply
        # from the deletion task. If it does not get a reply, the deletion may
        # fail. LP#1279720
        pid = fork do
          # sleep to let parent send response back to server
          sleep 5
          # Reboot the system
          File.open('/proc/sysrq-trigger','w') { |file| file.write("b\n")}
        end
        Process.detach(pid)
      end

      def suppress_fs_panic(dev)
        Dir["/dev/#{dev}{p,}[0-9]*"].each do |part|
          # if the partition has ext2/3/4, make sure error action is set to
          # continue and not panic so that we can erase it correctly.
          if system("blkid -p -n ext2,ext3,ext4 #{part}") == true && system("findmnt -ln -S #{part}") == true
            system("mount -o remount,ro,errors=continue #{part}")
          end
        end
      end

      def erase_partitions(dev)
        Dir["/dev/#{dev}{p,}[0-9]*"].each do |part|
          system("dd if=/dev/zero of=#{part} bs=1M count=10 oflag=direct")
        end
      end

      def erase_data(dev, length=1, offset=0, bs='1M')
        cmd = "dd if=/dev/zero of=/dev/#{dev} bs=#{bs} count=#{length} seek=#{offset} oflag=direct"
        status = system(cmd)
        debug_msg("Run device erasing command '#{cmd}' returned '#{status}'")

        status
      end

      # Prevent discover by agent while node rebooting
      def prevent_discover
        lock_path = AGENT_NODISCOVER_FILE
        debug_msg("Create file for discovery preventing #{lock_path}")
        FileUtils.mkdir_p(Pathname.new(lock_path).dirname)
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
