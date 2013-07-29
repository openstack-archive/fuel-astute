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
  class RedhatChecker

    def initialize(ctx, credentials)
      @ctx = ctx
      @username = credentials['username']
      @password = credentials['password']

      @check_credentials_errors = {
        127 => 'Can not find subscription-manager on the server',
      }
      @check_redhat_licenses_erros = {
        127 => 'Can not find get_redhat_licenses on the server',
      }
      @check_redhat_has_at_least_one_license_erros = {
        127 => 'Can not find get_redhat_licenses on the server',
      }
    end

    # Checking redhat credentials
    def check_redhat_credentials
      timeout = Astute.config[:REDHAT_CHECK_CREDENTIALS_TIMEOUT]
      check_credentials_cmd = "subscription-manager orgs " + \
        "--username '#{@username}' " + \
        "--password '#{@password}'"

      shell = MClient.new(@ctx, 'execute_shell_command', ['master'], false, timeout)
      response = shell.execute(:cmd => check_credentials_cmd).first

      report(response.results[:data], @check_credentials_errors)
    end

    # Check redhat linceses and return message, if not enough licenses
    def check_redhat_licenses(nodes)
      response = execute_get_licenses
      report(response.results[:data], @check_redhat_licenses_erros)
    end

    # Check that redhat has at least one license
    def redhat_has_at_least_one_license
      response = execute_get_licenses
      if response.results[:data][:exit_code] == 0
        report_success
      else
        report(response.results[:data], @redhat_has_at_least_one_license)
      end
    end

    private

    def report(result, errors)
      stdout = result[:stdout]
      stderr = result[:stderr]
      exit_code = result[:exit_code]

      if exit_code == 0
        report_success
      else
        error = errors[exit_code] || "Stdout: #{result[:stdout]} Stderr: #{result[:stderr]}"
        report_error(error)
      end
    end

    def report_success
      @ctx.reporter.report({'status' => 'ready', 'progress' => 100})
    end

    def report_error(msg)
      @ctx.reporter.report({'status' => 'error', 'error' => msg, 'progress' => 100})
    end


    def execute_get_licenses
      timeout = Astute.config[:REDHAT_GET_LICENSES_POOL_TIMEOUT]
      get_redhat_licenses_cmd = "get_redhat_licenses " + \
        "--username '#{@username}' " + \
        "--password '#{@password}'"

      shell = MClient.new(@ctx, 'execute_shell_command', ['master'], false, timeout)

      shell.execute(:cmd => get_redhat_licenses_cmd).first
    end

  end
end
