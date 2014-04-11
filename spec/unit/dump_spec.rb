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

  before(:each) { @tmp = Astute::MClient }
  after(:each)  { Astute::MClient = @tmp }

  let(:ctx) { mock_ctx() }

  it "should call execute method with nailgun_dump as cmd" do
    lastdump = "LASTDUMP"
    ctx = mock_ctx()

    agent = mock() do
      expects(:execute).with({:cmd => "/usr/bin/nailgun_dump >>/var/log/dump.log 2>&1 && cat #{lastdump}"}).\
      returns([{:data => {:exit_code => 0, :stdout => "stdout", :stderr => "stderr"}}])
    end

    Astute::MClient = mock() do
      expects(:new).with(ctx, 'execute_shell_command', ['master'], true, Astute.config.DUMP_TIMEOUT, 1).returns(agent)
    end
    Astute::Dump.dump_environment(ctx, lastdump)
  end

  it "should report success if shell agent returns 0" do
    agent = mock() do
      expects(:execute).returns([{:data => {:exit_code => 0, :stdout => "stdout"}}])
    end
    Astute::MClient = mock() do
      stubs(:new).returns(agent)
    end
    Astute::Dump.expects(:report_success)
    Astute::Dump.dump_environment(ctx, nil)
  end

  it "should report error if shell agent returns not 0" do
    agent = mock() do
      expects(:execute).returns([{:data => {:exit_code => 1, :stderr => "stderr"}}])
    end
    Astute::MClient = mock() do
      stubs(:new).returns(agent)
    end
    Astute::Dump.expects(:report_error).with(ctx, "exit code: 1 stderr: stderr")
    Astute::Dump.dump_environment(ctx, nil)
  end

  it "should report error if shell agent times out" do
    agent = mock() do
      expects(:execute).raises(Timeout::Error)
    end
    Astute::MClient = mock() do
      stubs(:new).returns(agent)
    end
    Astute::Dump.expects(:report_error).with(ctx, "Dump is timed out")
    Astute::Dump.dump_environment(ctx, nil)
  end

  it "should report error if any other exception occured" do
    agent = mock() do
      expects(:execute).raises(StandardError , "MESSAGE")
    end
    Astute::MClient = mock() do
      stubs(:new).returns(agent)
    end
    Astute::Dump.expects(:report_error).with() do |c, msg|
      c == ctx && msg =~ /Exception occured during dump task: message: MESSAGE/
    end
    Astute::Dump.dump_environment(ctx, nil)
  end
end
