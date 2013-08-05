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

  class RedhatCheckingError < Exception; end

  class RedhatChecker

    def initialize(ctx, credentials)
      @ctx = ctx
      @username = Shellwords.escape(credentials['redhat']['username'])
      @password = Shellwords.escape(credentials['redhat']['password'])
      satellite = credentials['redhat']['satellite']
      if satellite && !satellite.empty?
        @satellite_server = Shellwords.escape(satellite)
      end

      release_name = credentials['release_name']

      @network_error = 'Unable to reach host cdn.redhat.com. ' + \
        'Please check your Internet connection.'

      @user_does_not_have_licenses = 'Could not find any valid Red Hat ' + \
        'OpenStack subscriptions. Contact your Red Hat sales representative ' + \
        'to get the proper subscriptions associated with your account: '+ \
        'https://access.redhat.com/site/solutions/368643. If you are still ' + \
        'encountering issues, contact Mirantis Support.'

      @not_enough_licenses = "Your account has only %d licenses " + \
        'available to deploy Red Hat OpenStack. Contact your Red Hat sales ' + \
        'representative to get the proper subscriptions associated with your ' + \
        'account. https://access.redhat.com/site/solutions/368643'

      @check_credentials_success = "Account information for #{release_name} " + \
        'has been successfully modified.'

      @satellite_error = 'Unable to communicate with RHN Satellite Server. ' + \
        'Please check host and try again.'

      @common_errors = {
        /^Network error|^Remote server error/ => @network_error,
        /The requested URL returned error|Couldn't resolve host|couldn't connect to host/ => @satellite_error,
        /^Invalid username or password/ => 'Invalid username or password. ' + \
          'To create a login, please visit https://www.redhat.com/wapps/ugc/register.html'
      }
    end

    # Checking redhat credentials and satellite server
    def check_redhat_credentials
      timeout = Astute.config[:REDHAT_CHECK_CREDENTIALS_TIMEOUT]
      check_credentials_cmd = 'subscription-manager orgs ' + \
        "--username #{@username} " + \
        "--password #{@password}"

      # check user/password
      response = exec_cmd_with_timeout(check_credentials_cmd, timeout, @network_error)

      # checking user/password is succeed, than try to check satellite server if it set
      if @satellite_server && !contain_errors?(response.results[:data])
        check_server_satellite_cmd = 'curl -k -f -L -v --silent -o /dev/null ' + \
          "http://#{@satellite_server}/pub/RHN-ORG-TRUSTED-SSL-CERT"

        response = exec_cmd_with_timeout(check_server_satellite_cmd, timeout, @satellite_error)
      end

      report(response.results[:data], @check_credentials_success)
    end

    # Check redhat linceses and return message, if not enough licenses
    def check_redhat_licenses(nodes=nil)
      timeout = Astute.config[:REDHAT_GET_LICENSES_POOL_TIMEOUT]
      get_redhat_licenses_cmd = 'get_redhat_licenses ' + \
        "#{@username} " + \
        "#{@password}"

      response = exec_cmd_with_timeout(get_redhat_licenses_cmd, timeout, @network_error)

      licenses_count = nil
      begin
        licenses_pool = JSON.load(response.results[:data][:stdout])
        licenses_count = licenses_pool['openstack_licenses_physical_hosts_count']
      rescue JSON::ParserError
        report(response.results[:data])

        return
      end

      if licenses_count <= 0
        report_error(@user_does_not_have_licenses)
      elsif nodes && licenses_count < nodes.count
        report_success(format(@not_enough_licenses, licenses_count))
      else
        report_success
      end
    end

    private

    def report(result, success_msg=nil)
      stdout = result[:stdout]
      stderr = result[:stderr]
      exit_code = result[:exit_code]

      if contain_errors?(result)
        err_msg = "Unknown error Stdout: #{stdout} Stderr: #{stderr}"
        error = get_error(result) || err_msg
        Astute.logger.error(err_msg)
        report_error(error)
      else
        report_success(success_msg)
      end
    end

    def contain_errors?(data)
      get_error(data) || data[:exit_code] != 0
    end

    def get_error(result)
      @common_errors.each_pair do |regex, msg|
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

    # Report error and raise exception
    def report_error(msg)
      @ctx.reporter.report({'status' => 'error', 'error' => msg, 'progress' => 100})
      raise RedhatCheckingError.new(msg)
    end

    def exec_cmd_with_timeout(cmd, timeout, timeout_expired_msg)
      shell = MClient.new(@ctx, 'execute_shell_command', ['master'])
      begin
        Timeout.timeout(timeout) do
          response = shell.execute(:cmd => cmd).first
          report_error(timeout_expired_msg) unless response
          return response
        end
      rescue Timeout::Error
        Astute.logger.warn("Time out error for shell command '#{cmd}'")
        report_error(timeout_expired_msg)
      end
    end

  end
end
