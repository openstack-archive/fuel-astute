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
        reply[:stdout], reply[:stderr], reply[:exit_code] = runcommand(request[:cmd])
      end

      private
      def runcommand(cmd)
        # We cannot use Shell from puppet because
        # version 2.3.1 has bug, with returning wrong exit
        # code in some cases, in newer version mcollective
        # it was fixed
        # https://github.com/puppetlabs/marionette-collective
        #        /commit/10f163550bc6395f1594dacb9f15a86d4a3fde27
        # So, it's just fixed code from Shell#runcommand
        thread = Thread.current
        stdout = ''
        stderr = ''
        status = systemu(cmd, {'stdout' => stdout, 'stderr' => stderr}) do |cid|
          begin
            while(thread.alive?)
              sleep 0.1
            end
            Process.waitpid(cid) if Process.getpgid(cid)
          rescue SystemExit
          rescue Errno::ESRCH
          rescue Errno::ECHILD
          rescue Exception => e
            Log.info("Unexpected exception received while waiting for child process: #{e.class}: #{e}")
          end
        end

        [stdout, stderr, status.exitstatus]
      end

    end
  end
end
