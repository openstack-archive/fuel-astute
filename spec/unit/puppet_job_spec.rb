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

require File.join(File.dirname(__FILE__), '../spec_helper')

describe Astute::PuppetJob do
  include SpecHelpers

  let(:puppet_mclient) do
    puppet_mclient = mock('puppet_mclient')
    puppet_mclient.stubs(:run)
    puppet_mclient.stubs(:status)
    puppet_mclient.stubs(:manifest).returns('/etc/puppet/test_manifest.pp')
    puppet_mclient.stubs(:summary)
    puppet_mclient.stubs(:node_id).returns('test_node')
    puppet_mclient
  end

  let(:options) do
    {
      'retries' => 1,
      'succeed_retries' => 0,
      'timeout' => 1,
      'fade_timeout' => 0.01
    }
  end

  subject do
    puppet_job = Astute::PuppetJob.new('test_task', puppet_mclient, options)
    puppet_job.stubs(:sleep)
    puppet_job
  end

  describe '#run' do
    it 'should run puppet using mcollective client' do
      puppet_mclient.expects(:run).once.returns(true)
      expect(subject.run).to eq('running')
    end

    it 'should rerun puppet several times if client failed' do
      puppet_mclient.expects(:run).twice.returns(false).then.returns(true)
      expect(subject.run).to eq('running')
    end

    it 'should failed if puppet could not start after several retries' do
      puppet_mclient.expects(:run).at_least_once.returns(false)
      expect(subject.run).to eq('failed')
    end
  end

  describe '#summary' do
    it 'should return summary from mcollective agent' do
      summary = { 'info'=>'data' }
      puppet_mclient.expects(:summary).once.returns(summary)
      expect(subject.summary).to eq(summary)
    end
  end

  describe '#task_status=' do
    it 'should raise error if status do not support' do
      expect {subject.send(:task_status=, 'unknow_status')}.to \
        raise_error(StandardError, /unknow_status/)
    end
  end

  describe '#status' do

    context 'unknow status' do
      it 'should raise error if magent return unknow status' do
        puppet_mclient.stubs(:run).returns(true)
        subject.run

        puppet_mclient.expects(:status).returns('unknow_status')
        expect {subject.status}.to raise_error(StandardError, /unknow_status/)
      end
    end

    context 'running' do
      it 'should return runing when processing' do
        puppet_mclient.stubs(:run).returns(true)
        subject.run

        puppet_mclient.expects(:status).returns('running')
        expect(subject.status).to eq('running')
      end

      it 'should return runing when succeed but need succeed retries' do
        puppet_mclient.expects(:run).twice.returns(true)
        options['succeed_retries'] = 1
        subject.run

        puppet_mclient.stubs(:status)
          .returns('running')
          .then.returns('succeed')
          .then.returns('running')

        3.times { expect(subject.status).to eq('running') }
      end

      it 'should return runing when failed but can retry' do
        puppet_mclient.expects(:run).twice.returns(true)
        subject.run

        puppet_mclient.stubs(:status)
          .returns('running')
          .then.returns('stopped')
          .then.returns('running')

        3.times { expect(subject.status).to eq('running') }
      end

      it 'should return runing when magent failed but can retry' do
        puppet_mclient.expects(:run).twice.returns(true)
        subject.run

        puppet_mclient.stubs(:status)
          .returns('running')
          .then.returns('undefined')
          .then.returns('running')

        3.times { expect(subject.status).to eq('running') }
      end
    end

    context 'successful' do
      it 'should return successful if succeed' do
        puppet_mclient.stubs(:run).returns(true)
        subject.run

        puppet_mclient.stubs(:status)
          .returns('running')
          .then.returns('succeed')

        expect(subject.status).to eq('running')
        expect(subject.status).to eq('successful')
      end

      it 'should successful if failed but retry succeed' do
        puppet_mclient.stubs(:run).returns(true)
        options['retries'] = 2
        subject.run

        puppet_mclient.stubs(:status)
          .returns('stopped')
          .then.returns('undefined')
          .then.returns('succeed')

        2.times { expect(subject.status).to eq('running') }
        expect(subject.status). to eq('successful')
      end

      it 'should do nothing if final status set and retries end' do
        puppet_mclient.stubs(:run).returns(true)
        options['retries'] = 0
        subject.run

        puppet_mclient.stubs(:status).returns('succeed')
        3.times { expect(subject.status). to eq('successful') }
      end
    end

    context 'failed' do
      it 'should return failed if failed and no more retries' do
        puppet_mclient.stubs(:run).returns(true)
        subject.run

        puppet_mclient.stubs(:status)
          .returns('undefined')
          .then.returns('stopped')

        expect(subject.status).to eq('running')
        expect(subject.status).to eq('failed')
      end

      it 'should return failed if time is over and no result' do
        puppet_mclient.stubs(:run).returns(true)
        options['timeout'] = 0.01
        subject.run

        puppet_mclient.stubs(:status).returns('running')
        expect(subject.status).to eq('running')
        sleep options['timeout']
        expect(subject.status).to eq('failed')
      end

      it 'should do nothing if final status set and retries end' do
        puppet_mclient.stubs(:run).returns(true)
        options['retries'] = 1
        subject.run

        puppet_mclient.stubs(:status)
          .returns('undefined')
          .then.returns('stopped')

        expect(subject.status).to eq('running')
        3.times { expect(subject.status). to eq('failed') }
      end
    end
  end

end
