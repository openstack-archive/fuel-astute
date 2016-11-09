#    Copyright 2016 Mirantis, Inc.
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
        'retries' => 3,
        'cmd' => 'sh some_command',
        'cwd' => '/',
        'timeout' => 180,
        'interval' => 1},
      'type' => 'shell',
      'id' => 'shell_task_id',
      'node_id' => 'node_id',
    }
  end

  let(:ctx) { mock_ctx }

  subject { Astute::Shell.new(task, ctx) }

  describe '#run' do
    it 'should create puppet wrapper' do
      mclient = mock_rpcclient
      Astute::Shell.any_instance.stubs(:run_shell_without_check)
      Astute::Puppet.any_instance.stubs(:run)

      content = <<-eos
    # Puppet manifest wrapper for task: shell_task_id
    notice('MODULAR: shell_task_id')

    exec { 'shell_task_id_shell' :
      path      => '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
      command   => '/bin/bash "/etc/puppet/shell_manifests/shell_task_id_command.sh"',
      logoutput => true,
      timeout   => 180,
    }
      eos

      mclient.expects(:upload).with({
        :path => '/etc/puppet/shell_manifests/shell_task_id_manifest.pp',
        :content => content,
        :overwrite => true,
        :parents => true,
        :permissions => '0755',
        :user_owner => 'root',
        :group_owner => 'root',
        :dir_permissions => '0755'})
      subject.run
    end
  end

end

