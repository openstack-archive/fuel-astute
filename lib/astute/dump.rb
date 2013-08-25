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
  module Dump
    def self.dump_environment(ctx)
      timeout = 500
      shell = MClient.new(ctx, 'execute_shell_command', ['master'])
      begin
        Timeout.timeout(timeout) do
          response = shell.execute(:cmd => "/opt/nailgun/bin/nailgun_dump").first
          report_error("Error while dumping environment") unless response
          return response
        end
      rescue Timeout::Error
        Astute.logger.warn("Dump is timed out")
        report_error("Dump is timed out")
      end
    end

    def self.report_success(ctx, msg=nil)
      success_msg = {'status' => 'ready', 'progress' => 100}
      success_msg.merge!({'msg' => msg}) if msg
      ctx.reporter.report(success_msg)
    end

    def self.report_error(ctx, msg)
      ctx.reporter.report({'status' => 'error', 'error' => msg, 'progress' => 100})
    end

  end
end
