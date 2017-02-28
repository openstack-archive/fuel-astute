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
  class UploadFileMClient

    attr_reader :ctx, :node_id
    def initialize(ctx, node_id)
      @ctx = ctx
      @node_id = node_id
    end

    # Run upload without check using mcollective agent
    # @param [Hash] mco_params Upload file options
    # @return [true, false] upload result
    def upload_without_check(mco_params)
      upload_mclient = upload_mclient(
        :check_result => false,
        :timeout => mco_params['timeout']
      )
      upload(mco_params, upload_mclient)
    end

    # Run upload with check using mcollective agent
    # @param [Hash] mco_params Upload file options
    # @return [true, false] upload result
    def upload_with_check(mco_params)
      upload_mclient = upload_mclient(
        :check_result => false,
        :timeout => mco_params['timeout'],
        :retries => mco_params['retries']
      )
      process_with_retries(:retries => mco_params['retries']) do
        upload(mco_params, upload_mclient)
      end
    end

    private


    def upload(mco_params, magent)
      mco_params = setup_default(mco_params)

      results = magent.upload(
          :path => mco_params['path'],
          :content => mco_params['content'],
          :overwrite => mco_params['overwrite'],
          :parents => mco_params['parents'],
          :permissions => mco_params['permissions'],
          :user_owner => mco_params['user_owner'],
          :group_owner => mco_params['group_owner'],
          :dir_permissions => mco_params['dir_permissions']
      )

      if results.present? && results.first[:statuscode] == 0
        Astute.logger.debug("#{ctx.task_id}: file was uploaded "\
          "#{details_for_log(mco_params)} successfully")
        true
      else
        Astute.logger.error("#{ctx.task_id}: file was not uploaded "\
          "#{details_for_log(mco_params)}: "\
          "#{results.present? ? results.first[:msg] : "node has not answered"  }")
        false
      end
    rescue MClientTimeout, MClientError => e
      Astute.logger.error("#{ctx.task_id}: file was not uploaded "\
        "#{details_for_log(mco_params)}: #{e.message}")
      false
    end

    # Create configured shell mcollective agent
    # @return [Astute::MClient]
    def upload_mclient(args={})
      MClient.new(
        ctx,
        "uploadfile",
        [node_id],
        args.fetch(:check_result, false),
        args.fetch(:timeout, 2),
        args.fetch(:retries, Astute.config.upload_retries)
      )
    end

    # Setup default value for upload mcollective agent
    # @param [Hash] mco_params Upload file options
    # @return [Hash] mco_params
    def setup_default(mco_params)
      mco_params['retries'] ||= Astute.config.upload_retries
      mco_params['timeout'] ||= Astute.config.upload_timeout
      mco_params['overwrite'] = true if mco_params['overwrite'].nil?
      mco_params['parents'] = true if mco_params['parents'].nil?
      mco_params['permissions'] ||= '0644'
      mco_params['user_owner']  ||= 'root'
      mco_params['group_owner'] ||= 'root'
      mco_params['dir_permissions'] ||= '0755'

      mco_params
    end

    # Return short useful info about node and shell task
    # @return [String] detail info about upload task
    def details_for_log(mco_params)
      "#{mco_params['path']} on node #{node_id} "\
      "with timeout #{mco_params['timeout']}"
    end

    def process_with_retries(args={}, &block)
      retries = args.fetch(:retries, 1) + 1
      result = false

      retries.times do |attempt|
        result = block.call
        break if result

        Astute.logger.warn("#{ctx.task_id} Upload retry for node "\
          "#{node_id}: attempt № #{attempt + 1}/#{retries}")
      end
      result
    end

  end
end
