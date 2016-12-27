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

    def initialize(ctx, node_id)
      @ctx = ctx
      @node_id = node_id
    end

    # Run shell cmd without check using mcollective agent
    # @param [Hash] mco_params Upload file options
    # @param [Integer] timeout Timeout for upload command
    # @return [true, false] upload result
    def upload_without_check(mco_params)
      mco_params = setup_defaults(mco_params)

      results = upload_file(_check_result=false, mco_params['timeout'])
        .upload(
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
        Astute.logger.debug("#{@ctx.task_id}: file was uploaded "\
          "#{details_for_log(mco_params)} successfully")
        true
      else
        Astute.logger.error("#{@ctx.task_id}: file was not uploaded "\
          "#{details_for_log(mco_params)}: #{results.first[:msg]}")
        false
      end
    rescue MClientTimeout, MClientError => e
      Astute.logger.error("#{@ctx.task_id}: file was not uploaded "\
        "#{details_for_log(mco_params)}: #{e.message}")
      false
    end

    private

    # Create configured shell mcollective agent
    # @return [Astute::MClient]
    def upload_file(check_result=false, timeout=2)
      MClient.new(
        @ctx,
        "uploadfile",
        [@node_id],
        check_result,
        timeout
      )
    end

    def setup_default(mco_params)
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
      "#{mco_params['path']} on node #{@node_id} "\
      "with timeout #{mco_params['timeout']}"
    end

  end
end
