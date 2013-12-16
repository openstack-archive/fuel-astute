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
    # An agent to manage the Puppet Daemon
    #
    # Configuration Options:
    #    puppetd.splaytime - Number of seconds within which to splay; no splay
    #                        by default
    #    puppetd.statefile - Where to find the state.yaml file; defaults to
    #                        /var/lib/puppet/state/state.yaml
    #    puppetd.lockfile  - Where to find the lock file; defaults to
    #                        /var/lib/puppet/state/puppetdlock
    #    puppetd.puppetd   - Where to find the puppet binary; defaults to
    #                        /usr/bin/puppet apply
    #    puppetd.summary   - Where to find the summary file written by Puppet
    #                        2.6.8 and newer; defaults to
    #                        /var/lib/puppet/state/last_run_summary.yaml
    #    puppetd.pidfile   - Where to find puppet agent's pid file; defaults to
    #                        /var/run/puppet/agent.pid
    class Puppetd<RPC::Agent
      def startup_hook
        @splaytime = @config.pluginconf["puppetd.splaytime"].to_i || 0
        @lockfile = @config.pluginconf["puppetd.lockfile"] || "/tmp/puppetd.lock"
        @statefile = @config.pluginconf["puppetd.statefile"] || "/var/lib/puppet/state/state.yaml"
        @pidfile = @config.pluginconf["puppet.pidfile"] || "/var/run/puppet/agent.pid"
        @puppetd = @config.pluginconf["puppetd.puppetd"] || "/usr/sbin/daemonize -a -e /var/log/puppet/puppet.err \
                                                                                 -o /var/log/puppet/puppet.log \
                                                                                 -l #{@lockfile} \
                                                                                 -p #{@lockfile} \
                                                                                 /usr/bin/puppet apply /etc/puppet/manifests/site.pp"
        @last_summary = @config.pluginconf["puppet.summary"] || "/var/lib/puppet/state/last_run_summary.yaml"
      end

      action "last_run_summary" do
        last_run_summary
        set_status
      end

      action "enable" do
        enable
      end

      action "disable" do
        disable
      end

      action "runonce" do
        runonce
      end

      action "status" do
        set_status
      end

      private

      def last_run_summary
        # wrap into begin..rescue: fixes PRD-252
        begin
          summary = YAML.load_file(@last_summary)
        rescue
          summary = {}
        end

        # It should be empty hash, if 'resources' key is not defined, because otherwise merge will fail with TypeError
        summary["resources"] ||= {}
        # Astute relies on last_run, so we must set last_run
        summary["time"] ||= {}
        summary["time"]["last_run"] ||= 0
        # if 'failed' is not provided, it means something is wrong. So default value is 1.
        reply[:resources] = {"failed"=>1, "changed"=>0, "total"=>0, "restarted"=>0, "out_of_sync"=>0}.merge(summary["resources"])

        ["time", "events", "changes", "version"].each do |dat|
          reply[dat.to_sym] = summary[dat]
        end
      end

      def set_status
        reply[:status]  = puppet_daemon_status
        reply[:running] = reply[:status] == 'running'  ? 1 : 0
        reply[:enabled] = reply[:status] == 'disabled' ? 0 : 1
        reply[:idling]  = reply[:status] == 'idling'   ? 1 : 0
        reply[:stopped] = reply[:status] == 'stopped'  ? 1 : 0
        reply[:lastrun] = 0
        reply[:lastrun] = File.stat(@statefile).mtime.to_i if File.exists?(@statefile)
        reply[:runtime] = Time.now.to_i - reply[:lastrun]
        reply[:output]  = "Currently #{reply[:status]}; last completed run #{reply[:runtime]} seconds ago"
      end

      def rm_file file
        begin
          File.unlink(file)
          return true
        rescue
          return false
        end
      end

      def puppet_daemon_status
        err_msg = ""
        alive = !!puppet_agent_pid
        locked = File.exists?(@lockfile)
        disabled = locked && File::Stat.new(@lockfile).zero?

        if locked && !disabled && !alive
          err_msg << "Process not running but not empty lockfile is present. Trying to remove lockfile..."
          err_msg << (rm_file(@lockfile) ? "ok." : "failed.")
        end

        reply[:err_msg] = err_msg if err_msg.any?

        if disabled && !alive
          'disabled'
        elsif disabled && alive
          'running'
        elsif alive && locked
          'running'
        elsif alive && !locked
          'idling'
        elsif !alive
          'stopped'
        end
      end

      def runonce
        set_status
        case (reply[:status])
        when 'disabled' then     # can't run
          reply.fail "Empty Lock file exists; puppet is disabled."

        when 'running' then      # can't run two simultaniously
          reply.fail "Lock file and PID file exist; puppet is running."

        when 'idling' then       # signal daemon
          pid = puppet_agent_pid
          begin
            ::Process.kill('INT', pid)
          rescue Errno::ESRCH => e
            reply[:err_msg] = "Failed to signal the puppet apply daemon (process #{pid}): #{e}"
          ensure
            runonce_background
            reply[:output] = "Kill old idling puppet process #{pid})." + (reply[:output] || '')
          end

        when 'stopped' then      # just run
          runonce_background

        else
          reply.fail "Unknown puppet status: #{reply[:status]}"
        end
      end

      def runonce_background
        cmd = [@puppetd, "--logdest", 'syslog', '--trace']
        unless request[:forcerun]
          if @splaytime && @splaytime > 0
            cmd << "--splaylimit" << @splaytime << "--splay"
          end
        end

        cmd << '--debug' if request[:puppet_debug]

        cmd = cmd.join(" ")

        output = reply[:output] || ''
        run(cmd, :stdout => :output, :chomp => true)
        reply[:output] = "Called #{cmd}, " + output + (reply[:output] || '')
      end

      def enable
        if File.exists?(@lockfile)
          stat = File::Stat.new(@lockfile)

          if stat.zero?
            File.unlink(@lockfile)
            reply[:output] = "Lock removed"
          else
            reply[:output] = "Currently running; can't remove lock"
          end
        else
          reply[:output] = "Already enabled"
        end
      end

      def disable
        if File.exists?(@lockfile)
          stat = File::Stat.new(@lockfile)

          stat.zero? ? reply[:output] = "Already disabled" : reply.fail("Currently running; can't remove lock")
        else
          begin
            File.open(@lockfile, "w") { |file| }
            reply[:output] = "Lock created"
          rescue => e
            reply.fail "Could not create lock: #{e}"
          end
        end
      end

      def puppet_agent_pid
        result = `ps -C puppet -o pid,comm --no-headers`.lines.first
        result && result.strip.split(' ')[0].to_i
      end
    end
  end
end
