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
        echo "1" > /proc/sys/kernel/panic_on_oops

        STORAGE_DEVICE_NUMBERS="3, 8, 65, 66, 67, 68, 69, 70, 71, 104, 105, 106, 107, 108, 109, 110, 111, 202, 252, 253"
        BLOCK_DEVICES=$(sed -nr 's#^.*[0-9]\s+([a-z]+|cciss\/c[0-9]+d[0-9]+)$#\\1#p' /proc/partitions)

        erase_data() {
          echo "Run erase_data with dev= /dev/$1 length = $2 offset = $3 bs = $4"
          dd if=/dev/zero of="/dev/$1" count="$2" seek="$3" bs="$4"
          blockdev --flushbufs "/dev/$1"
        }

        erase_partitions() {
          for PART in $(sed -nr 's#^.*[0-9]\s+('"$1"'p?[0-9]+)$#\\1#p' /proc/partitions)
          do
            erase_data "$PART" "$2" "$3" "$4"
          done
        }

        erase_boot_devices() {
          for DEVICE in $BLOCK_DEVICES
          do
            MAJOR=$(sed -nr 's#^\s+([0-9]+)\s.*\s'"$DEVICE"'$#\\1#p' /proc/partitions)
            SIZE=$(($(sed -nr 's#^(\s+[0-9]+){2}\s+([0-9]+)\s+'"$DEVICE"'$#\\2#p' /proc/partitions) * 2))
            echo "$STORAGE_DEVICE_NUMBERS" | grep -wq "$MAJOR" || continue
            grep -wq 0 "/sys/block/$(echo $DEVICE | sed 's#/#!#')/removable" || continue

            erase_data "$DEVICE" 1 0 512
            erase_data "$DEVICE" 1 $(($SIZE-1)) 512
            erase_partitions "$DEVICE" 1 0 512
          done
        }

        if [ -r /etc/nailgun_systemtype ]; then
          NODE_TYPE=$(cat /etc/nailgun_systemtype)
        else
          NODE_TYPE="provisioning"
        fi

        # Check what was mounted to '/': drive (provisioned node)
        # or init ramdisk (bootsrapped/provisioning node)
        if grep -Eq 'root=[^[:blank:]]+' /proc/cmdline; then
          echo "Do not erase $NODE_TYPE node using shell"
        else
          echo "Run erase command on ${NODE_TYPE} node"
          erase_boot_devices
        fi
      ERASE_COMMAND
    end
  end
end
