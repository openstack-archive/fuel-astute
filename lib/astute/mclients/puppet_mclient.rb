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
  class PuppetMClient

    PUPPET_STATUSES = [
      'running', 'stopped', 'disabled'
    ]

    ALLOWING_STATUSES_TO_RUN = [
      'stopped'
    ]

    PUPPET_FILES_TO_CLEANUP = [
      "/var/lib/puppet/state/last_run_summary.yaml",
      "/var/lib/puppet/state/last_run_report.yaml"
    ]

    attr_reader :summary

    def initialize(ctx, node_id, options)
      @ctx = ctx
      @node_id = node_id
      @options = options
      @summary = {}
    end

    # Return actual status of puppet using mcollective puppet agent
    # @return [String] status: succeed, one of PUPPET_STATUSES or undefined
    def status
      last_run_summary
      succeed? ? 'succeed' : @summary.fetch(:status, 'undefined')
    end

    # Run puppet on node if available
    # @return [true, false]
    def run
      cleanup!
      actual_status = status
      runonce and return true if
        ALLOWING_STATUSES_TO_RUN.include?(actual_status)

      Astute.logger.warn "Unable to start puppet on node #{@node_id}"\
        " because of status: #{actual_status}. Expected: "\
        "#{ALLOWING_STATUSES_TO_RUN}"
      false
    rescue MClientError, MClientTimeout => e
      Astute.logger.warn "Unable to start puppet on node #{@node_id}. "\
        "Reason: #{e.message}"
      false
    end

    private

    # Create configured puppet mcollective agent
    # @return [Astute::MClient]
    def puppetd
      puppetd = MClient.new(
        @ctx,
        "puppetd",
        [@node_id],
        _check_result=true,
        _timeout=nil,
        _retries=1,
        _enable_result_logging=false
      )
      puppetd.on_respond_timeout do |uids|
        Astute.logger.error "Nodes #{uids} reached the response timeout"
        raise MClientTimeout
      end
      puppetd
    end

    # Run last_run_summary action using mcollective puppet agent
    # @return [Hash] return hash with status and resources
    def last_run_summary
      @summary = puppetd.last_run_summary(
        :puppet_noop_run => @options[:puppet_noop_run],
        :raw_report => @options[:raw_report]
      ).first[:data]
      validate_status!(@summary[:status])
      @summary
    rescue MClientError, MClientTimeout => e
      Astute.logger.warn "Unable to get actual status of puppet on "\
        "node #{@node_id}. Reason: #{e.message}"
      @summary = {}
    end

    # Run runonce action using mcollective puppet agent
    # @return [void]
    # @raise [MClientTimeout, MClientError]
    def runonce
      puppetd.runonce(
        :puppet_debug => @options[:puppet_debug],
        :manifest => @options[:puppet_manifest],
        :modules  => @options[:puppet_modules],
        :cwd => @options[:cwd],
        :puppet_noop_run => @options[:puppet_noop_run],
      )
    end

    # Validate puppet status
    # @param [String] status The puppet status
    # @return [void]
    # @raise [StandardError] Unknown status
    def validate_status!(status)
      unless PUPPET_STATUSES.include?(status)
        raise MClientError, "Unknow status #{status} from mcollective agent"
      end
    end

    # Detect succeed of puppet run using summary from last_run_summary call
    # @return [true, false]
    def succeed?
      return false if @summary.blank?

      @summary[:status] == 'stopped' &&
      @summary[:resources] &&
      @summary[:resources]['failed'].to_i == 0 &&
      @summary[:resources]['failed_to_restart'].to_i == 0
    end

    # Clean up puppet report files to exclude incorrect status detection
    # @return [void]
    def cleanup!
      ShellMClient.new(@ctx, @node_id).run_without_check(rm_cmd)
    end

    # Generate shell cmd for file deletion
    # @return [String] shell cmd for deletion
    def rm_cmd
      PUPPET_FILES_TO_CLEANUP.inject([]) do
        |cmd, file| cmd << "rm -f #{file}"
      end.join(" && ")
    end

  end # PuppetMclient
end
