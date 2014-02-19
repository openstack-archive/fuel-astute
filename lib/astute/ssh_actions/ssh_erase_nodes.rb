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
  class SshEraseNodes

    def self.command
      <<-ERASE_COMMAND
        killall -STOP anaconda
        killall -STOP debootstrap dpkg
        echo "5" > /proc/sys/kernel/panic
        echo "1" > /proc/sys/kernel/sysrq

        storages_codes="3, 8, 65, 66, 67, 68, 69, 70, 71, 104, 105, 106, 107, 108, 109, 110, 111, 202, 252, 253"

        reboot_with_sleep() {
          sleep 5
          echo "1" > /proc/sys/kernel/panic_on_oops
          echo "10" > /proc/sys/kernel/panic
          echo "b" > /proc/sysrq-trigger
        }

        erase_data() {
          echo "Run erase_node with dev= $1 length = $2 offset = $3 bs = $4"
          dd if=/dev/zero of=/dev/$1 bs=$2 count=$3 seek=$4 oflag=direct
        }

        erase_boot_devices() {
          for d in /sys/block/*
          do
            basename_dir=$(basename $d)
            major_raw=$(udevadm info --query=property --name=$basename_dir | grep MAJOR | sed 's/ *$//g')
            major=$(echo ${major_raw##*=})

            echo $storages_codes | grep -o "\b$major\b"
            if [ $? -ne 0 ]; then continue; fi

            removable=$(grep -o '[[:digit:]]' /sys/block/$basename_dir/removable)
            if [ $removable -ne 0 ]; then continue; fi

            size=$(cat /sys/block/$basename_dir/size)

            erase_data $basename_dir 1 0 '1M'
            erase_data $basename_dir 1 $size '512'
          done
        }

        echo "Run erase node command"
        erase_boot_devices

        # Avoid shell hang using nohup and stdout/stderr redirections
        # nohup reboot_with_sleep > /dev/null 2>&1 &
      ERASE_COMMAND
    end
  end
end