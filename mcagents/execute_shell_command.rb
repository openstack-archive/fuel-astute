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
        require 'open3'
        require 'tempfile'

        # In ruby 1.8 we cannot retrive exit code with open3
        exit_code_file = Tempfile.new('mco_exec_exit_code')

        exit_code, stdout, stderr = nil
        begin
          Timeout.timeout(timeout) do
            exec_and_save_exit_code = "#{command}; echo $? > #{exit_code_file.path}"
            _, _stdout, _stderr = Open3.popen3(exec_and_save_exit_code)

            exit_code = exit_code_file.read.to_i
            stdout = _stdout.read()
            stderr = _stderr.read()
          end
        rescue Timeout::Error
          exit_code = 124
          stderr = "Command '#{command}' times out with timeout=#{timeout}"
        end

        exit_code_file.unlink

        [stdout, stderr, exit_code]
      end

    end
  end
end
