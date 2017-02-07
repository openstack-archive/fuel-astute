#    Copyright 2017 Mirantis, Inc.
#
#    Licensed under the Apache License, Version 2.0 (the 'License'); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an 'AS IS' BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

require File.join(File.dirname(__FILE__), '../../spec_helper')

describe Astute::Shell do
  include SpecHelpers

  let(:task) do
    {
      'parameters' => {
        'debug' => false,
        'retries' => 1,
        'puppet_manifest' => 'puppet_manifest_example.pp',
        'puppet_modules' => '/etc/puppet/modules',
        'cwd' => '/',
        'timeout' => nil,
        'succeed_retries' => 1,
        'timeout' => 180
      },
      'type' => 'puppet',
      'id' => 'puppet_task_example',
      'node_id' => 'node_id',
    }
  end

  let(:ctx) { mock_ctx }

  subject { Astute::Puppet.new(task, ctx) }

  describe '#run' do
    before { Astute::Puppet.any_instance.stubs(:process) }
    context 'debug behavior' do
      it 'puppet debug should disable if debug option disable or missing' do
        subject.run
        expect(subject.task['parameters']['puppet_debug']).to eq(false)
      end

      it 'puppet debug should enable if debug enable' do
        task['parameters']['debug'] = true
        subject.run
        expect(subject.task['parameters']['debug']).to eq(true)
        expect(subject.task['parameters']['puppet_debug']).to eq(true)
      end
    end # context
  end # 'run'
end




