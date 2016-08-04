#    Copyright 2016 Mirantis, Inc.
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
require 'erb'

module Astute
  class NoopShell < Shell

    def summary
      @puppet_task.summary
    rescue
      {}
    end

    private

    def process
      run_shell_without_check(
        @task['node_id'],
        "mkdir -p #{SHELL_MANIFEST_DIR}",
        timeout=2
      )
      upload_shell_manifest
      @puppet_task = NoopPuppet.new(
        generate_puppet_hook,
        @ctx
      )
      @puppet_task.run
    end

  end
end
