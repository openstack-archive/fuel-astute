# -*- coding: utf-8 -*-

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


module MCollective
  module Agent
    class Execute_shell_command < RPC::Agent

      action 'execute' do
        timeout = request[:timeout] || 600
        reply[:stdout], reply[:stderr], reply[:exit_code] = \
          run_shell_command(request[:cmd], timeout)
      end

      private
      def run_shell_command(command, timeout)
        require 'timeout'

        exit_code, stdout, stderr = nil
        begin
          Timeout.timeout(timeout) do
            shell = Shell.new(command)
            shell.runcommand

            stdout = shell.stdout
            stderr = shell.stderr
            exit_code = shell.status.exitstatus
          end
        rescue Timeout::Error
          exit_code = 124
          stderr = "Command '#{command}' times out with timeout=#{timeout}"
        end

        [stdout, stderr, exit_code]
      end

    end
  end
end
