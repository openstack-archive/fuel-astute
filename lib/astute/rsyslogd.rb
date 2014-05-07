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
  class Rsyslogd

    def self.send_sighup(master_ip)
        shell = MClient.new(ctx, 'execute_shell_command', ['master'],
                            check_result=true, timeout=timeout, retries=1)
        cmd = "ssh root@#{master_ip} 'for pids in $(pidof rsyslogd); do echo kill -HUP $pids; done'"
        result = shell.execute(:cmd => cmd).first.results
    end
  end
end
