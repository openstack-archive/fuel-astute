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
    class Syncstuff < RPC::Agent

      action 'rsync' do
        # Rsync depend of presence or absence of /
        source = request.data[:source].chomp('/').concat('/')
        path = request.data[:path].chomp('/').concat('/')
        cmd = "rsync #{request.data[:rsync_options]} #{source} #{path}"
        run_and_respond(cmd)
        reply[:msg] = "Stuff was synced!"
      end

      private

      def run_and_respond(cmd)
        exit_code = run(
          cmd,
          :stdout => :stdout,
          :stderr => :stderr
        )

        if exit_code != 0
          reply.fail! "Fail to upload folder using command #{cmd}." \
                      "Exit code: #{exit_code}, stderr: #{reply[:stderr]}" \
                      "stdout: #{reply[:stdout]}"
        end
      end

    end
  end
end