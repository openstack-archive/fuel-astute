# -*- coding: utf-8 -*-

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
  module RedhatChecker

    def initalize(ctx, credentials)
      @ctx = ctx
      credentials
    end

    def check_redhat_credentials()
      check_credentials_cmd = "subscription-manager orgs " + \
        "--username '#{username}' " + \
        "--password '#{password}'"

      shell = MClient.new(@ctx, 'execute_shell_command', 'master', false)
      shell.execute(:cmd => check_credentials_cmd)
    end

    def check_redhat_licenses()
      get_redhat_licenses_cmd = "get_redhat_licenses " + \
        "--username '#{username}' " + \
        "--password '#{password}'"

      shell = MClient.new(@ctx, 'master', false)
      shell.execute(:cmd => get_redhat_licenses_cmd)
    end

end
