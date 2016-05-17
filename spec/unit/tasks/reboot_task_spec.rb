#    Copyright 2016 Mirantis, Inc.
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

require File.join(File.dirname(__FILE__), '../../spec_helper')

describe Astute::Reboot do
  include SpecHelpers

  let(:task) do
    {
      "parameters" => {
        "timeout" => 300,
      },
      "type" => "reboot",
      "node_id" => '1',
      "fail_on_error" => true,
      "required_for" => [],
      "requires" => [],
      "id" => "openstack-haproxy-reboot",
    }
  end

  let(:ctx) {
    ctx = mock
    ctx.stubs(:task_id)
    ctx.stubs(:deploy_log_parser).returns(Astute::LogParser::NoParsing.new)
    ctx.stubs(:status).returns({})
    reporter = mock
    reporter.stubs(:report)
    up_reporter = Astute::ProxyReporter::DeploymentProxyReporter.new(
      reporter,
      [task['node_id']]
    )
    ctx.stubs(:reporter).returns(up_reporter)
    ctx
  }

  subject { Astute::Reboot.new(task, ctx) }

  let(:mco_puppet_stopped) do
    {
      :changes => {"total" => 1},
      :time => {"last_run" => 1358425701},
      :resources => {"failed" => 0},
      :status => "stopped",
      :enabled => 1,
      :stopped => 1,
      :idling => 0,
      :running => 0,
      :runtime => 1358425701
    }
  end

  let(:mco_puppet_running) do
    mco_puppet_stopped.merge(
      :status => 'running',
      :running => 1,
      :stopped => 0
    )
  end

  let(:mco_puppet_fail) do
    mco_puppet_running.merge(
      :runtime => 1358426000,
      :time => {"last_run" => 1358426000},
      :resources => {"failed" => 1}
    )
  end

  let(:mco_puppet_failed) do
    mco_puppet_fail.merge(
      :status => 'stopped',
      :stopped => 1,
      :running => 0
    )
  end

  let(:mco_puppet_finished) do
    mco_puppet_stopped.merge(
      :time => {'last_run' => 1358428000},
      :status => 'stopped'
    )
  end

  let(:mco_puppet_idling) do
    mco_puppet_stopped.merge(
      :status => 'idling',
      :running => 0,
      :stopped => 0,
      :idling => 1
    )
  end

  describe "#run" do
    it 'should get boot time before reboot' do
      subject.expects(:boot_time).once.returns(12)
      subject.stubs(:reboot)
      subject.run
    end

    it 'should reboot node after getting boot time' do
      subject.stubs(:boot_time).returns(12)
      subject.expects(:reboot).once
      subject.run
    end

    it 'should failed if mclient could not get boot time' do
      subject.expects(:run_shell_without_check).with(
        task['node_id'],
        "stat --printf='%Y' /proc/1",
        _timeout=2
      ).raises(Astute::MClientTimeout)
      subject.expects(:reboot).never

      expect{subject.run}.not_to raise_error(Astute::MClientTimeout)
      expect(subject.status).to eql(:failed)
    end

    it 'should use mclient without check with reboot command to reboot' do
      subject.stubs(:boot_time).returns(12)
      subject.expects(:run_shell_without_check).with(
        task['node_id'],
        regexp_matches(/reboot/),
        _timeout=2
      )
      subject.run
    end

    it 'should use mclient without check with stat to get boot time' do
      subject.expects(:run_shell_without_check).with(
        task['node_id'],
        "stat --printf='%Y' /proc/1",
        _timeout=2
      ).returns({:stdout => "12"})
      subject.stubs(:reboot)
      subject.run
    end

    it 'should fail if mclient with reboot command raise error' do
      subject.stubs(:boot_time).returns(12)
      subject.expects(:run_shell_without_check).with(
        task['node_id'],
        regexp_matches(/reboot/),
        _timeout=2
      ).raises(Astute::MClientTimeout)
      expect{subject.run}.not_to raise_error(Astute::MClientTimeout)
      expect(subject.status).to eql(:failed)
    end

  end #run

  describe "#status" do
    before(:each) do
      ctx.stubs(:report_and_update_status)
    end

    it 'it should succeed if boot time before and after is different' do
      subject.stubs(:reboot)
      subject.expects(:boot_time).twice.returns(12).then.returns(13)

      subject.run
      expect(subject.status).to eql(:successful)
    end

    it 'it should succeed if boot time before and after are different' do
      subject.stubs(:reboot)
      subject.expects(:boot_time).twice.returns(12).then.returns(11)

      subject.run
      expect(subject.status).to eql(:successful)
    end

    it 'it should succeed if boot time before and after is different' do
      subject.stubs(:reboot)
      subject.expects(:boot_time).twice.returns(12).then.returns(11)

      subject.run
      expect(subject.status).to eql(:successful)
    end

    it 'it should fail if timeout is reached' do
      subject.stubs(:reboot)
      subject.expects(:boot_time).once.returns(12)
      task['parameters']['timeout'] = -1

      subject.run
      expect(subject.status).to eql(:failed)
    end

    it 'it should succeed after several tries' do
      subject.stubs(:reboot)
      subject.expects(:boot_time).times(4).returns(12)
                                          .then.returns(12)
                                          .then.returns(0)
                                          .then.returns(11)

      subject.run
      3.times { subject.status }
      expect(subject.status).to eql(:successful)
    end

    it 'it should not failed if boot time raise eror' do
      subject.expects(:run_shell_without_check).with(
        task['node_id'],
        "stat --printf='%Y' /proc/1",
        _timeout=2
      ).times(3).returns({:stdout => "12"})
                .then.raises(Astute::MClientTimeout)
                .then.returns({:stdout => "13"})
      subject.stubs(:reboot)

      subject.run
      expect(subject.status).to eql(:running)
      expect(subject.status).to eql(:successful)
    end

  end #status

end
