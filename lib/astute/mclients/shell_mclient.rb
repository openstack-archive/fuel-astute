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
  class ShellMClient

    def initialize(ctx, node_id)
      @ctx = ctx
      @node_id = node_id
    end

    def run_without_check(cmd, timeout=2)
      Astute.logger.debug("Executing shell command without check: "\
        "#{details_for_log(cmd, timeout)}")

      results = shell(_check_result=false, timeout).execute(:cmd => cmd)
      Astute.logger.debug("Mcollective shell #{details_for_log(cmd, timeout)}"\
        " result: #{results.pretty_inspect}")
      if results.present?
        result = results.first
        log_result(result)
        {
          :stdout =>result.results[:data][:stdout].chomp,
          :stderr => result.results[:data][:stderr].chomp,
          :exit_code => result.results[:data][:exit_code]
        }
      else
        Astute.logger.warn("#{@ctx.task_id}: Failed to run shell "\
          "#{details_for_log(cmd, timeout)} node #{@node_id}. "\
          "Error will not raise because shell was run without check")
        {}
      end
    end

    def shell(check_result=false, timeout=2)
      MClient.new(
        @ctx,
        'execute_shell_command',
        [@node_id],
        check_result,
        timeout
      )
    end

    def details_for_log(cmd, timeout)
      "command '#{cmd}' on node #{@node_id} with timeout #{timeout}"
    end

    def log_result(result)
      Astute.logger.debug(
        "#{@ctx.task_id}: cmd: #{cmd}\n" \
        "stdout: #{result.results[:data][:stdout]}\n" \
        "stderr: #{result.results[:data][:stderr]}\n" \
        "exit code: #{result.results[:data][:exit_code]}")
    end

  end
end
