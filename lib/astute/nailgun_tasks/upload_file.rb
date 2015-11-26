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
  class UploadFile < NailgunTask

    private

    def process
      @upload_status = :pending
      @work_thread = Thread.new do
        @upload_status = upload_file(@hook['node_id'], @hook['parameters'])
      end
    end

    def calculate_status
      failed! and return if @upload_status == false
      succeed! and return if @upload_status == true

      failed! if !@work_thread.alive? && @upload_status == :pending
    end

    def pre_validation
      validate_presence(@hook, 'node_id')
      validate_presence(@hook['parameters'], 'files')
    end

  end
end