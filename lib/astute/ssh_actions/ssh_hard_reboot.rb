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
  class SshHardReboot

    def self.command
     <<-REBOOT_COMMAND
        # Need more robust mechanizm to detect provisining or provisined node
        node_type=$(cat /etc/nailgun_systemtype)
        if [ "$node_type" == "target" ] || [ "$node_type" == "bootstrap" ]; then
          echo "Do not affect $node_type node"
          exit
        fi
        echo "Run node rebooting command using 'SB' to sysrq-trigger"
        echo "1" > /proc/sys/kernel/panic_on_oops
        echo "10" > /proc/sys/kernel/panic
        echo "b" > /proc/sysrq-trigger
      REBOOT_COMMAND
    end
  end
end