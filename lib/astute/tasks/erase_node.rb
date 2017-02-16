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

module Astute
  class EraseNode < Task

    def summary
      {'task_summary' => "Node #{task['node_id']} was erased without reboot"\
                         " with result #{@status}"}
    end

    private

    def process
      erase_node
    end

    def calculate_status
      succeed!
    end

    def validation
      validate_presence(task, 'node_id')
    end

    def erase_node
      remover = MClient.new(
        ctx,
        "erase_node",
        Array(task['node_id']),
        _check_result=false)
      response = remover.erase_node(:reboot => false)
      Astute.logger.debug "#{ctx.task_id}: Data received from node "\
                          "#{task['node_id']} :\n#{response.pretty_inspect}"
    rescue Astute::MClientTimeout, Astute::MClientError => e
      Astute.logger.error("#{ctx.task_id}: #{task_name} mcollective " \
        "erase node command failed with error #{e.message}")
        failed!
    end

  end
end
