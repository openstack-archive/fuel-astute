#    Copyright 2014 Mirantis, Inc.
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

include Astute

describe Astute::Rsyslogd do
  include SpecHelpers

  before(:each) do
    @ctx = mock('context')
    @ctx.stubs(:task_id)
    @master_ip = '127.0.0.1'
  end

  it "should create mclient, execute_shell_command for master and send kill -HUP to rsyslogd" do

    rpcclient = mock_rpcclient()
    cmd = "ssh root@#{@master_ip} 'pkill -HUP rsyslogd'"
    rpcclient.expects(:execute).with(:cmd => cmd).once

    Astute::Rsyslogd.send_sighup(@ctx, @master_ip)
  end
end
