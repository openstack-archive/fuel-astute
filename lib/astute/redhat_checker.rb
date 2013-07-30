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

      @network_error = 'Unable to reach host cdn.redhat.com. ' + \
        'Please check your Internet connection.'
      @check_credential_errors = {
        /^Network error|^Remote server error/ => @network_error,
        /^Invalid username or password/ => 'Invalid username or password. ' + \
          'To create a login, please visit https://www.redhat.com/wapps/ugc/register.html'
      }

      @check_redhat_licenses_erros = {
      }
      @check_redhat_has_at_least_one_license_erros = {
      }
    end

    # Checking redhat credentials
    def check_redhat_credentials
      timeout = Astute.config[:REDHAT_CHECK_CREDENTIALS_TIMEOUT]
      check_credentials_cmd = "subscription-manager orgs " + \
        "--username '#{@username}' " + \
        "--password '#{@password}'"

      shell = MClient.new(@ctx, 'execute_shell_command', ['master'])

      response = {}
      begin
        Timeout.timeout(timeout) do
          response = shell.execute(:cmd => check_credentials_cmd).first
        end
      rescue Timeout::Error
        Astute.logger.warn("Time out error for shell command '#{check_credentials_cmd}'")
        report_error(@network_error)

        return
      end

      report(response.results[:data], @check_credential_errors)
    end

    # Check redhat linceses and return message, if not enough licenses
    def check_redhat_licenses(nodes)
      response = execute_get_licenses
      unless response
        report_error(@network_error)
      else
        report(response.results[:data], @check_redhat_licenses_erros)
      end
    end

    # Check that redhat has at least one license
    def redhat_has_at_least_one_license
      response = execute_get_licenses
      unless response
        report_error(@network_error)
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
        err_msg = "Unknown error Stdout: #{result[:stdout]} Stderr: #{result[:stderr]}"
        error = get_error(result, errors) || err_msg
        report_error(error)
      end
    end

    def get_error(result, errors)
      errors.each_pair do |regex, msg|
        return msg if regex.match(result[:stdout])
        return msg if regex.match(result[:stderr])
      end
    end

    def report_success
      @ctx.reporter.report({'status' => 'ready', 'progress' => 100})
    end

    def report_error(msg)
      @ctx.reporter.report({'status' => 'error', 'error_msg' => msg, 'progress' => 100})
    end


    def execute_get_licenses
      timeout = Astute.config[:REDHAT_GET_LICENSES_POOL_TIMEOUT]
      get_redhat_licenses_cmd = "get_redhat_licenses " + \
        "--username '#{@username}' " + \
        "--password '#{@password}'"

      shell = MClient.new(@ctx, 'execute_shell_command', ['master'], false, timeout)
      begin
        Timeout.timeout(timeout) do
          return shell.execute(:cmd => get_redhat_licenses_cmd).first
        end
      rescue Timeout::Error
        Astute.logger.warn("Time out error for shell command '#{get_redhat_licenses_cmd}'")
      end
    end

  end
end
