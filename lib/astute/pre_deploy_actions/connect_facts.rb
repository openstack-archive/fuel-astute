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
  class ConnectFacts < PreDeployAction

    def process(deployment_info, context)
      deployment_info.each{ |node| connect_facts(context, node) }
      Astute.logger.info "#{context.task_id}: Connect role facts for nodes"
    end

    private

    def connect_facts(context, node)
      run_shell_command(
        context,
        [node['uid']],
        "ln -s -f /etc/#{node['role']}.yaml /etc/astute.yaml"
      )
    end

  end #class
end
