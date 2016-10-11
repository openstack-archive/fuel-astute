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

require_relative('../../spec_helper')

describe Astute::PuppetMClient do
  include SpecHelpers

  let(:ctx) {
    ctx = mock
    ctx.stubs(:task_id)
    ctx.stubs(:deploy_log_parser).returns(Astute::LogParser::NoParsing.new)
    ctx.stubs(:status).returns({})
    reporter = mock
    reporter.stubs(:report)
    up_reporter = Astute::ProxyReporter::TaskProxyReporter.new(reporter)
    ctx.stubs(:reporter).returns(up_reporter)
    ctx
  }

  let(:node_id) { 'test_id' }
  let(:puppetd) { mock('puppet_mclient') }
  let(:shell_mclient) do
    shell_mclient = mock('shell_mclient')
    shell_mclient.stubs(:run_without_check)
    shell_mclient
  end

  let(:options) do
    {
      'cwd' => '/etc/puppet/mainfest/test',
      'puppet_manifest' => 'test_manifest.pp',
      'puppet_noop_run' => false,
      'raw_report' => true,
      'puppet_debug' => true,
      'puppet_modules' => '/etc/puppet/modules/test'
    }
  end

  let(:mco_puppet_stopped) do
    {
      :changes => {"total" => 1},
      :time => {"last_run" => 0},
      :resources => {
        "changed_resources"=> "",
        "failed_resources"=> "",
        "failed" => 1,
        "changed"=>0,
        "total"=>0,
        "restarted"=>0,
        "out_of_sync"=>0
      },
      :status => "stopped",
      :enabled => 1,
      :stopped => 1,
      :idling => 0,
      :running => 0,
      :lastrun=>1475516435,
      :runtime => 58201
    }
  end

  let(:mco_puppet_disabled) do
    mco_puppet_stopped.merge(
      :status => 'disabled',
      :enabled => 0
    )
  end

  let(:mco_puppet_running) do
    mco_puppet_stopped.merge(
      :status => 'running',
      :running => 1,
      :stopped => 0
    )
  end

  let(:mco_puppet_unknown) do
    mco_puppet_stopped.merge(
      :status => nil
    )
  end

  let(:mco_puppet_failed) do
    mco_puppet_fail.merge(
      :status => 'stopped',
      :stopped => 1,
      :running => 0
    )
  end

  let(:mco_puppet_succeed) do
    mco_puppet_stopped.merge(
      :time => {'last_run' => 1358428000},
      :resources => {
        "changed_resources"=> "",
        "failed_resources"=> "",
        "failed" => 0,
        "changed"=>1,
        "total"=>1,
        "restarted"=>0,
        "out_of_sync"=>0
      },
    )
  end

  subject do
    Astute::PuppetMClient.new(ctx, node_id, options, shell_mclient)
  end

  describe '#summary' do
    it 'should return empty hash if no data' do
      expect(subject.summary).to eq({})
    end
  end

  describe '#node_id' do
    it 'should return node id' do
      expect(subject.node_id).to eq(node_id)
    end
  end

  describe '#manifest' do
    it 'should return path to manifest' do
      expect(subject.manifest).to \
        eq('/etc/puppet/mainfest/test/test_manifest.pp')
    end
  end

  describe '#status' do
    before do
      subject.stubs(:puppetd).returns(puppetd)
    end

    it 'should return running status if puppet running' do
      puppetd.expects(:last_run_summary).with(
        :puppet_noop_run => options['puppet_noop_run'],
        :raw_report => options['raw_report']
      ).returns([:data => mco_puppet_running])

      expect(subject.status).to eq 'running'
      expect(subject.summary).to eq mco_puppet_running
    end

    it 'should return stopped status if puppet stopped' do
      puppetd.expects(:last_run_summary).with(
        :puppet_noop_run => options['puppet_noop_run'],
        :raw_report => options['raw_report']
      ).returns([:data => mco_puppet_stopped])

      expect(subject.status).to eq 'stopped'
      expect(subject.summary).to eq mco_puppet_stopped
    end

    it 'should return disabled status if puppet disabled' do
      puppetd.expects(:last_run_summary).with(
        :puppet_noop_run => options['puppet_noop_run'],
        :raw_report => options['raw_report']
      ).returns([:data => mco_puppet_disabled])

      expect(subject.status).to eq 'disabled'
      expect(subject.summary).to eq mco_puppet_disabled
    end

    it 'should return succeed status if puppet succeed' do
      puppetd.expects(:last_run_summary).with(
        :puppet_noop_run => options['puppet_noop_run'],
        :raw_report => options['raw_report']
      ).returns([:data => mco_puppet_succeed])

      expect(subject.status).to eq 'succeed'
      expect(subject.summary).to eq mco_puppet_succeed
    end

    it 'should return undefined status if puppet status unknow' do
      puppetd.expects(:last_run_summary).with(
        :puppet_noop_run => options['puppet_noop_run'],
        :raw_report => options['raw_report']
      ).returns([:data => mco_puppet_unknown])

      expect(subject.status).to eq 'undefined'
      expect(subject.summary).to eq({})
    end
  end

  describe '#run' do
    before do
      subject.stubs(:puppetd).returns(puppetd)
    end

    it 'should return true if happened to start' do
      subject.expects(:status).returns('stopped')
      puppetd.expects(:runonce).with(
        :puppet_debug => options['puppet_debug'],
        :manifest => options['puppet_manifest'],
        :modules  => options['puppet_modules'],
        :cwd => options['cwd'],
        :puppet_noop_run => options['puppet_noop_run'],
      )

      expect(subject.run).to be true
    end

    context 'should return false if could not start' do
      it 'if another puppet still running' do
        subject.expects(:status).returns('running')
        puppetd.expects(:runonce).never

        expect(subject.run).to be false
      end

      it 'if puppet was disabled' do
        subject.expects(:status).returns('disabled')
        puppetd.expects(:runonce).never

        expect(subject.run).to be false
      end

      it 'if puppet status unknow' do
        subject.expects(:status).returns('undefined')
        puppetd.expects(:runonce).never

        expect(subject.run).to be false
      end
    end

    it 'should return false if magent raise error' do
      subject.expects(:status).returns('stopped')
      puppetd.expects(:runonce).raises(Astute::MClientError, "Custom error")

      expect(subject.run).to be false
    end

    context 'should cleanup puppet report files before start' do
      it 'if puppet was stopped' do
        subject.stubs(:status).returns('stopped')
        subject.stubs(:runonce)
        shell_mclient.unstub(:run_without_check)
        shell_mclient.expects(:run_without_check)
          .with('rm -f /var/lib/puppet/state/last_run_summary.yaml'\
                ' && rm -f /var/lib/puppet/state/last_run_report.yaml').once
        expect(subject.run).to be true
      end

      it 'if puppet was succeed' do
        subject.stubs(:status).returns('succeed')
        subject.stubs(:runonce)
        shell_mclient.unstub(:run_without_check)
        shell_mclient.expects(:run_without_check)
          .with('rm -f /var/lib/puppet/state/last_run_summary.yaml'\
                ' && rm -f /var/lib/puppet/state/last_run_report.yaml').once
        expect(subject.run).to be true
      end
    end
  end # run

end
