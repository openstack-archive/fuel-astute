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
    def self.dump_environment(ctx, settings)
      shell = MClient.new(
        ctx,
        'execute_shell_command',
        ['master'],
        check_result=true,
        settings['timeout'] || Astute.config.dump_timeout,
        retries=0,
        enable_result_logging=false
      )

      begin
        log_file = "/var/log/timmy.log"
        snapshot = File.basename(settings['target'])
        if settings['timestamp']
          snapshot = DateTime.now.strftime("#{snapshot}-%Y-%m-%d_%H-%M-%S")
        end
        base_dir = File.dirname(settings['target'])
        dest_dir = File.join(base_dir, snapshot)
        dest_file = File.join(dest_dir, "config.tar.gz")
        token = settings['auth-token']
        dump_cmd = "mkdir -p #{dest_dir} && "\
                   "timmy --logs --days 3 --dest-file #{dest_file}"\
                   " --fuel-token #{token} --log-file #{log_file} && "\
                   "tar --directory=#{base_dir} -cf #{dest_dir}.tar #{snapshot} && "\
                   "echo #{dest_dir}.tar > #{settings['lastdump']} && "\
                   "rm -rf #{dest_dir}"
        Astute.logger.debug("Try to execute command: #{dump_cmd.sub(token, '***')}")
        result = shell.execute(:cmd => dump_cmd).first.results

        Astute.logger.debug("#{ctx.task_id}: exit code: #{result[:data][:exit_code]}")

        if result[:data][:exit_code] == 0
          Astute.logger.info("#{ctx.task_id}: Snapshot is done.")
          report_success(ctx, "#{dest_dir}.tar")
        elsif result[:data][:exit_code] == 28
          Astute.logger.error("#{ctx.task_id}: Disk space for creating snapshot exceeded.")
          report_error(ctx, "Timmy exit code: #{result[:data][:exit_code]}. Disk space for creating snapshot exceeded.")
        else
          Astute.logger.error("#{ctx.task_id}: Dump command returned non zero exit code. For details see #{log_file}")
          report_error(ctx, "Timmy exit code: #{result[:data][:exit_code]}")
        end
      rescue Timeout::Error
        msg = "Dump is timed out"
        Astute.logger.error("#{ctx.task_id}: #{msg}")
        report_error(ctx, msg)
      rescue => e
        msg = "Exception occured during dump task: message: #{e.message} \
trace:\n#{e.backtrace.pretty_inspect}"
        Astute.logger.error("#{ctx.task_id}: #{msg}")
        report_error(ctx, msg)
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
