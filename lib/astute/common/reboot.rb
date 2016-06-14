#    Copyright 2014 Mirantis, Inc.
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
  module RebootCommand
    # Reboot immediately if we're in a bootstrap. Wait until system boots
    # completely in case of provisioned node. We check it by existense
    # of /run/cloud-init/status.json (it's located on tmpfs, so no stale
    # file from previous boot can be found). If this file hasn't appeared
    # after 60 seconds - reboot as is.
    CMD = <<-REBOOT_COMMAND
      if [ $(hostname) = bootstrap ]; then
         reboot;
      fi;
      t=0;
      while true; do
         if [ -f /run/cloud-init/status.json -o $t -gt 60 ]; then
             reboot;
         else
             sleep 1;
             t=$((t + 1));
         fi;
      done
    REBOOT_COMMAND
  end
end
