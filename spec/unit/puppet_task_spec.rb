#    Copyright 2015 Mirantis, Inc.
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

describe Astute::PuppetTask do
  include SpecHelpers

  let(:node) do
    {
      'uid' => '45',
      'priority' => 200,
      'role' => 'ceph',
      'tasks' => [
        {
         'priority' => 100,
         'type' => 'puppet',
         'uids' => ['45']
        },
        {
         'priority' => 300,
         'type' => 'puppet',
         'uids' => ['45']
        }
      ]
    }
  end

  let(:ctx) {
    ctx = mock
    ctx.stubs(:task_id)
    ctx.stubs(:deploy_log_parser).returns(Astute::LogParser::NoParsing.new)
    ctx.stubs(:status).returns({})
    reporter = mock
    reporter.stubs(:report)
    up_reporter = Astute::ProxyReporter::DeploymentProxyReporter.new(reporter, [node])
    ctx.stubs(:reporter).returns(up_reporter)
    ctx
  }

  let(:puppet_task) { Astute::PuppetTask.new(ctx, node)}
  let(:puppet_task_wo_retries) { Astute::PuppetTask.new(ctx, node, {:retries=>0})}
  let(:puppet_task_success_retries) { Astute::PuppetTask.new(ctx, node, {
    :retries=>1,
    :puppet_manifest=>nil,
    :puppet_modules=>nil,
    :cwd=>nil,
    :timeout=>nil,
    :puppet_debug=>false,
    :succeed_retries=>1
    })
  }

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
    it 'run puppet using mcollective' do
      puppet_task.expects(:puppet_status).returns(mco_puppet_stopped)
      puppet_task.expects(:puppet_run)
      puppet_task.run
    end
  end #run

  describe "#status" do
    before(:each) do
      ctx.stubs(:report_and_update_status)
    end

    it 'check puppet using mcollective' do
      puppet_task.stubs(:puppet_status).returns(mco_puppet_stopped)
        .then.returns(mco_puppet_running)
        .then.returns(mco_puppet_finished)

      puppet_task.expects(:puppet_run)
      puppet_task.run
    end

    it 'return error for node if puppet failed (a cycle w/o any transitional states)' do
      puppet_task_wo_retries.stubs(:puppet_status).returns(mco_puppet_stopped)
        .then.returns(mco_puppet_failed)

      puppet_task_wo_retries.expects(:puppet_run)
      puppet_task_wo_retries.run
      expect(puppet_task_wo_retries.status).to eql('error')
    end

    it 'retries to run puppet if it fails and return middle status' do
      puppet_task.stubs(:puppet_status).returns(mco_puppet_stopped)
        .then.returns(mco_puppet_failed)
        .then.returns(mco_puppet_failed)
        .then.returns(mco_puppet_finished)

      puppet_task.expects(:puppet_run).times(2)
      puppet_task.run
      expect(puppet_task.status).to eql('deploying')
      expect(puppet_task.status).to eql('ready')
    end

    it "return error for node if puppet failed (a cycle with one running state only)" do
      puppet_task_wo_retries.stubs(:puppet_status).returns(mco_puppet_stopped)
        .then.returns(mco_puppet_running)
        .then.returns(mco_puppet_running)
        .then.returns(mco_puppet_fail)
        .then.returns(mco_puppet_failed)

      puppet_task_wo_retries.expects(:puppet_run)
      puppet_task_wo_retries.run

      expect(puppet_task_wo_retries.status).to eql('deploying')
      expect(puppet_task_wo_retries.status).to eql('deploying')
      expect(puppet_task_wo_retries.status).to eql('deploying')
      expect(puppet_task_wo_retries.status).to eql('error')
    end

    it "error status for node if puppet failed (a cycle w/o idle and finishing states)" do
      puppet_task_wo_retries.stubs(:puppet_status).returns(mco_puppet_stopped)
        .then.returns(mco_puppet_running)
        .then.returns(mco_puppet_failed)

      puppet_task_wo_retries.expects(:puppet_run)
      puppet_task_wo_retries.run
      expect(puppet_task_wo_retries.status).to eql('deploying')
      expect(puppet_task_wo_retries.status).to eql('error')
    end

    it "retries to run puppet if it idling" do
      puppet_task.stubs(:puppet_status).returns(mco_puppet_stopped)
        .then.returns(mco_puppet_idling)
        .then.returns(mco_puppet_stopped)
        .then.returns(mco_puppet_running)
        .then.returns(mco_puppet_finished)

      puppet_task.expects(:puppet_run)
      puppet_task.run
      expect(puppet_task.status).to eql('deploying')
      expect(puppet_task.status).to eql('ready')
    end

    it "error status for node if puppet failed (mcollective retries)" do
      puppet_task.stubs(:puppet_status).raises(Astute::MClientTimeout)

      puppet_task.stubs(:puppetd_runonce)
      puppet_task.run

      expect(puppet_task.status).to eql('error')
    end

    it 'status will retry successful puppet task if configured' do
      puppet_task_success_retries.stubs(:puppet_status).returns(mco_puppet_finished)
      puppet_task_success_retries.stubs(:node_status).returns('succeed')

      puppet_task_success_retries.expects(:puppetd_runonce).times(2)
      puppet_task_success_retries.run
      puppet_task_success_retries.status
    end
  end #status

end
