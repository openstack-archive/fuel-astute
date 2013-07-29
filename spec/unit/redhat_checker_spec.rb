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

  let(:data) do
    {
      'username' => 'user',
      'password' => 'password'
    }
  end

  let(:reporter) { mock('reporter') }
  let(:ctx) { Astute::Context.new('task-uuuid', reporter) }
  let(:redhat_checker) { described_class.new(ctx, data) }

  let!(:rpcclient) { mock_rpcclient }

  def execute_returns(data)
    result = mock_mc_result({:data => data })
    rpcclient.expects(:execute).once.returns([result])
  end

  describe '#check_redhat_credentials' do
    it 'should report ready if exit_code 0' do
      execute_returns({:exit_code => 0})
      reporter.expects(:report).once.with({'status' => 'ready', 'progress' => 100})

      redhat_checker.check_redhat_credentials
    end
  end

  describe '#check_redhat_licenses' do
    it 'should report ready if exit_code 0' do
      execute_returns({:exit_code => 0})
      reporter.expects(:report).once.with({'status' => 'ready', 'progress' => 100})

      nodes = []
      redhat_checker.check_redhat_licenses(nodes)
    end
  end

  describe '#redhat_has_at_least_one_license' do
    it 'should report ready if exit_code 0' do
      execute_returns({:exit_code => 0})
      reporter.expects(:report).once.with({'status' => 'ready', 'progress' => 100})

      redhat_checker.redhat_has_at_least_one_license
    end
  end

end
