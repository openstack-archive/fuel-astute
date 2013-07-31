# -*- encoding: utf-8 -*-

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


require File.join(File.dirname(__FILE__), '../spec_helper')


describe Astute::RedhatChecker do
  include SpecHelpers

  let(:redhat_credentials) do
    {
      'release_name' => 'RELEASE_NAME',
      'redhat' => {
        'username' => 'user',
        'password' => 'password'
      }
    }
  end

  let(:reporter) { mock('reporter') }
  let(:ctx) { Astute::Context.new('task-uuuid', reporter) }
  let(:redhat_checker) { described_class.new(ctx, redhat_credentials) }

  let!(:rpcclient) { mock_rpcclient }
  let(:success_result) { {'status' => 'ready', 'progress' => 100} }

  def execute_returns(data)
    result = mock_mc_result({:data => data })
    rpcclient.expects(:execute).once.returns([result])
  end

  def should_report_once(data)
    reporter.expects(:report).once.with(data)
  end

  def should_report_error(data)
    error_data = {'status' => 'error', 'progress' => 100}.merge(data)
    reporter.expects(:report).once.with(error_data)
  end

  shared_examples 'redhat checker' do
    it 'should handle network connection errors' do
      execute_returns({
        :exit_code => 0,
        :stdout => "Text before\nNetwork error, unable to connect to server.\nText after"})

      err_msg = 'Unable to reach host cdn.redhat.com. ' + \
        'Please check your Internet connection.'
      should_report_error({'error' => err_msg})

      expect { execute_handler }.to raise_error(Astute::RedhatCheckingError)
    end

    it 'should handle wrong username/password errors' do
      execute_returns({
        :exit_code => 0,
        :stdout => "Text before\nInvalid username or password\nText after"})

      err_msg = 'Invalid username or password. ' + \
        'To create a login, please visit https://www.redhat.com/wapps/ugc/register.html'
      should_report_error({'error' => err_msg})

      expect { execute_handler }.to raise_error(Astute::RedhatCheckingError)
    end

    it 'should handle uniq errors' do
      execute_returns({
        :exit_code => 1,
        :stdout => "Uniq error stdout",
        :stderr => "Uniq error stderr"})

      err_msg = "Unknown error Stdout: Uniq error stdout Stderr: Uniq error stderr"
      should_report_error({'error' => err_msg})

      expect { execute_handler }.to raise_error(Astute::RedhatCheckingError)
    end
  end

  describe '#check_redhat_credentials' do
    it_behaves_like 'redhat checker' do
      def execute_handler
        redhat_checker.check_redhat_credentials
      end
    end

    it 'should be success with right credentials' do
      execute_returns({:exit_code => 0, :stdout => '{"openstack_licenses_physical_hosts_count":1}'})
      success_msg = "Account information for RELEASE_NAME has been successfully modified."
      should_report_once(success_result.merge({'msg' => success_msg}))

      redhat_checker.check_redhat_credentials
    end
  end

  describe '#check_redhat_licenses' do
    let(:success_result) do
      {
        'status' => 'ready',
        'progress' => 100,
        'msg' => 'Your account appears to be fully entitled to deploy Red Hat Openstack.'
      }
    end

    describe 'nodes parameter is nil' do
      it_behaves_like 'redhat checker' do
        def execute_handler
          redhat_checker.check_redhat_credentials
        end
      end

      it 'should be success if no errors' do
        execute_returns({:exit_code => 0, :stdout => '{"openstack_licenses_physical_hosts_count":1}'})
        should_report_once(success_result)

        redhat_checker.check_redhat_licenses
      end
    end

    describe 'nodes parameter is not nil' do
      it_behaves_like 'redhat checker' do
        def execute_handler
          redhat_checker.check_redhat_licenses([1])
        end
      end

      it 'should report ready if no errors' do
        execute_returns({:exit_code => 0,
          :stdout => '{"openstack_licenses_physical_hosts_count":1}'})
        should_report_once(success_result)

        nodes = [1]
        redhat_checker.check_redhat_licenses(nodes)
      end

      it 'should report message if not enough licenses' do
        execute_returns({:exit_code => 0,
          :stdout => '{"openstack_licenses_physical_hosts_count":3}'})

        err_msg = 'Your account has only 3 licenses available to deploy Red ' + \
        'Hat OpenStack. Contact your Red Hat sales representative to ' + \
        'get the proper subscriptions associated with your account. ' + \
        'https://access.redhat.com/site/solutions/368643'

        should_report_once({'progress' => 100, 'status' => 'ready', 'msg' => err_msg})

        nodes = [1, 2, 3, 4]
        redhat_checker.check_redhat_licenses(nodes)
      end

    end
  end
end
