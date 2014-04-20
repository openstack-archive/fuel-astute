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

describe 'dump_environment' do
  include SpecHelpers

  let(:ctx) { mock_ctx }
  let(:settings) do
    {
      'lastdump' => '/last/dump/path'
    }
  end
  let(:rpc_mock) { mock_rpcclient }

  def exec_result(exit_code=0, stdout='', stderr='')
    result_mock = mock_mc_result({
        :data => {
          :exit_code => exit_code,
          :stdout => stdout,
          :stderr => stderr}})
    [result_mock]
  end

  it "should upload the config and call execute method with shotgun as cmd" do
    config_path = '/tmp/dump_config'
    dump_cmd = "shotgun -c #{config_path} >> /var/log/dump.log 2>&1 && cat #{settings['lastdump']}"
    rpc_mock.expects(:upload).with({
        path: config_path,
        content: settings.to_json,
        user_owner: 'root',
        group_owner: 'root',
        overwrite: true}).returns([mock_mc_result])

    rpc_mock.expects(:execute).with({:cmd => dump_cmd}).returns(exec_result)

    Astute::Dump.dump_environment(ctx, settings)
  end

  it "should report success if shell agent returns 0" do
    rpc_mock.expects(:upload).returns([mock_mc_result])
    rpc_mock.expects(:execute).returns(exec_result)
    Astute::Dump.expects(:report_success)
    Astute::Dump.dump_environment(ctx, settings)
  end

  it "should report error if shell agent returns not 0" do
    rpc_mock.expects(:upload).returns([mock_mc_result])
    rpc_mock.expects(:execute).returns(exec_result(1, '', 'stderr'))
    Astute::Dump.expects(:report_error).with(ctx, "exit code: 1 stderr: stderr")
    Astute::Dump.dump_environment(ctx, settings)
  end

  it "should report error if shell agent times out" do
    agent = mock do
      stubs(:upload)
      stubs(:execute).raises(Timeout::Error)
    end
    Astute::MClient.stubs(:new).returns(agent)
    Astute::Dump.expects(:report_error).with(ctx, "Dump is timed out")
    Astute::Dump.dump_environment(ctx, settings)
  end

  it "should report error if any other exception occured" do
    agent = mock do
      stubs(:upload)
      stubs(:execute).raises(StandardError , "MESSAGE")
    end
    Astute::MClient.stubs(:new).returns(agent)
    Astute::Dump.expects(:report_error).with do |c, msg|
      c == ctx && msg =~ /Exception occured during dump task: message: MESSAGE/
    end

    Astute::Dump.dump_environment(ctx, settings)
  end
end
