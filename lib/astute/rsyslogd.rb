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

    def self.send_sighup(ctx, master_ip)
        timeout = Astute.config.SSH_RETRY_TIMEOUT
        shell = MClient.new(ctx, 'execute_shell_command', ['master'],
                            check_result=true, timeout=timeout, retries=1)
        cmd = "ssh root@#{master_ip} 'pkill -HUP rsyslogd'"

        begin
            result = shell.execute(:cmd => cmd).first.results

            Astute.logger.info("#{ctx.task_id}: \
    stdout: #{result[:data][:stdout]} stderr: #{result[:data][:stderr]} \
    exit code: #{result[:data][:exit_code]}")
        rescue Timeout::Error
            msg = "Sending SIGHUP to rsyslogd is timed out."
            Astute.logger.error("#{ctx.task_id}: #{msg}")
        rescue => e
            msg = "Exception occured during sending SIGHUP to rsyslogd, message: #{e.message} \
    trace: #{e.backtrace.inspect}"
            Astute.logger.error("#{ctx.task_id}: #{msg}")
        end
    end
  end
end
