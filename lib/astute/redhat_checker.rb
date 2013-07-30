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

      @user_dont_has_licenses = 'Could not find any valid Red Hat ' + \
        'OpenStack subscriptions. Contact your Red Hat sales representative ' + \
        'to get the proper subscriptions associated with your account: '+ \
        'https://access.redhat.com/site/solutions/368643. If you are still ' + \
        'encountering issues, contact Mirantis Support.'

      @check_licenses_success_msg = 'Your account appears to be fully entitled ' + \
        'to deploy Red Hat Openstack.'

      @msg_not_enough_licenses = "Your account has only %d licenses " + \
        'available to deploy Red Hat OpenStack. Contact your Red Hat sales ' + \
        'representative to get the proper subscriptions associated with your ' + \
        'account. https://access.redhat.com/site/solutions/368643'

      @common_errors = {
        /^Network error|^Remote server error/ => @network_error,
        /^Invalid username or password/ => 'Invalid username or password. ' + \
          'To create a login, please visit https://www.redhat.com/wapps/ugc/register.html'
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

      report(response.results[:data], @common_errors)
    end

    # Check redhat linceses and return message, if not enough licenses
    def check_redhat_licenses(nodes=nil)
      response = execute_get_licenses
      unless response
        report_error(@network_error)

        return
      end

      licenses_count = nil
      begin
        licenses_pool = JSON.load(response.results[:data][:stdout])
        licenses_count = licenses_pool['openstack_licenses_physical_hosts_count']
      rescue JSON::ParserError
        report(response.results[:data], @common_errors)

        return
      end

      if licenses_count <= 0
        report_error(@user_dont_has_licenses)
      elsif nodes && licenses_count < nodes.count
        report_success(format(@msg_not_enough_licenses, licenses_count))
      else
        report_success(@check_licenses_success_msg)
      end
    end

    private

    def report(result, errors)
      stdout = result[:stdout]
      stderr = result[:stderr]
      exit_code = result[:exit_code]

      if !get_error(result, errors) && exit_code == 0
        report_success
      else
        err_msg = "Unknown error Stdout: #{stdout} Stderr: #{stderr}"
        error = get_error(result, errors) || err_msg
        report_error(error)
      end
    end

    def get_error(result, errors)
      errors.each_pair do |regex, msg|
        return msg if regex.match(result[:stdout])
        return msg if regex.match(result[:stderr])
      end
      nil
    end

    def report_success(msg=nil)
      success_msg = {'status' => 'ready', 'progress' => 100}
      success_msg.merge!({'msg' => msg}) if msg
      @ctx.reporter.report(success_msg)
    end

    def report_error(msg)
      @ctx.reporter.report({'status' => 'error', 'error_msg' => msg, 'progress' => 100})
    end

    def execute_get_licenses
      timeout = Astute.config[:REDHAT_GET_LICENSES_POOL_TIMEOUT]
      get_redhat_licenses_cmd = "get_redhat_licenses " + \
        "'#{@username}' " + \
        "'#{@password}'"

      shell = MClient.new(@ctx, 'execute_shell_command', ['master'])
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
