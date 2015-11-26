#    Copyright 2015 Mirantis, Inc.
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
  class Sync < NailgunTask

    RSYNC_OPTIONS = '-c -r --delete'

    private

    def process
      @shell_task = Puppet.new(
        generate_shell_hook,
        @ctx
      ).run
    end

    def calculate_status
      status = @shell_task.status
    end

    def pre_validation
      validate_presence(@hook, 'uids')
      validate_presence(@hook['parameters'], 'dst')
      validate_presence(@hook['parameters'], 'src')
    end

    def setup_default
      @hook['parameters']['timeout'] ||= 300
      @hook['parameters']['retries'] ||= 10
    end

    def generate_shell_hook
      path = @hook['parameters']['dst']
      rsync_cmd = "mkdir -p #{path} && rsync #{RSYNC_OPTIONS} " \
                  "#{@hook['parameters']['src']} #{path}"
      {
        "uids" =>  @hook['uids'],
        "id" => @hook['id'] + '_shell'
        "parameters" =>  {
          "cmd" =>  rsync_cmd,
          "cwd" =>  "/",
          "timeout" => @hook['parameters']['timeout'],
          "retries" => @hook['parameters']['retries']
        }
      }
    end

  end
end
