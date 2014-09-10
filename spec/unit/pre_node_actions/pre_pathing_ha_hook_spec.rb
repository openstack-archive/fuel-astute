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

require File.join(File.dirname(__FILE__), '../../spec_helper')

describe Astute::PrePatchingHa do
  include SpecHelpers

  let(:ctx) do
    ctx = mock('context')
    ctx.stubs(:task_id)
    ctx.stubs(:reporter)
    ctx.stubs(:status).returns('1' => 'success', '2' => 'success')
    ctx
  end

  let(:deploy_data) { [
                        {'uid' => '1',
                         'role' => 'cinder',
                         'openstack_version_prev' => 'old_version',
                         'deployment_mode' => 'ha_compact',
                         'cobbler' => {
                            'profile' => 'centos-x86_64'
                          },
                          'nodes' => [
                            {
                              'uid' => '1',
                              'slave_name' => 'node-1',
                              'role' => 'cinder'
                            },
                            {
                              'uid' => '1',
                              'slave_name' => 'node-1',
                              'role' => 'controller'
                            },
                            {
                              'uid' => '2',
                              'slave_name' => 'node-2',
                              'role' => 'ceph-osd'
                            },
                            {
                              'uid' => '3',
                              'slave_name' => 'node-3',
                              'role' => 'primary-controller'
                            }
                          ],
                        },
                        {'uid' => '2',
                         'role' => 'compute'
                        },
                        {'uid' => '3',
                         'role' => 'primary-controller'
                        }
                      ]
                    }

  let(:pre_patching_ha) { Astute::PrePatchingHa.new }

  it 'should run if upgrade/downgrade env' do
    Astute::Pacemaker.expects(:commands).returns(['basic command'])
    pre_patching_ha.expects(:run_shell_command).returns(:data => {:exit_code => 0})
    pre_patching_ha.process(deploy_data, ctx)
  end

  it 'should not run if deploy new env' do
    deploy_data.first.delete('openstack_version_prev')

    Astute::Pacemaker.expects(:commands).never
    pre_patching_ha.expects(:run_shell_command).never

    pre_patching_ha.process(deploy_data, ctx)
  end

  it 'should run if upgrade/downgrade not HA env' do
    deploy_data.first['deployment_mode'] = 'simple'

    Astute::Pacemaker.expects(:commands).never
    pre_patching_ha.expects(:run_shell_command).never

    pre_patching_ha.process(deploy_data, ctx)
  end

  it 'should not change deployment status if command fail' do
    Astute::Pacemaker.expects(:commands).returns(['basic command'])
    pre_patching_ha.expects(:run_shell_command).once.returns(:data => {:exit_code => 1})
    ctx.expects(:report_and_update_status).never

    pre_patching_ha.process(deploy_data, ctx)
  end

  it 'should not change deployment status if shell exec using mcollective fail' do
    Astute::Pacemaker.expects(:commands).returns(['basic command'])
    pre_patching_ha.expects(:run_shell_command).once.returns(:data => {})

    pre_patching_ha.process(deploy_data, ctx)
    ctx.expects(:report_and_update_status).never
  end

  it 'should run command for every pacemaker services' do
    Astute::Pacemaker.expects(:commands).returns(['command1', 'command2'])
    pre_patching_ha.expects(:run_shell_command).twice.returns(:data => {:exit_code => 1})

    pre_patching_ha.process(deploy_data, ctx)
  end

  context 'Pacemaker stuff' do

    let(:transormed_data) {
      [{'uid' => '1',
       'role' => 'controller',
       'openstack_version_prev' => 'old_version',
       'deployment_mode' => 'ha_compact',
       'cobbler' => {
          'profile' => 'centos-x86_64'
        },
        'nodes' => [
          {
            'uid' => '1',
            'slave_name' => 'node-1',
            'role' => 'cinder'
          },
          {
            'uid' => '1',
            'slave_name' => 'node-1',
            'role' => 'controller'
          },
          {
            'uid' => '2',
            'slave_name' => 'node-2',
            'role' => 'ceph-osd'
          },
          {
            'uid' => '3',
            'slave_name' => 'node-3',
            'role' => 'primary-controller'
          }
        ],
      },
      {'uid' => '3',
       'role' => 'primary-controller'
      }]
    }

    let(:no_controllers) {
      [{'uid' => '1',
       'role' => 'compute',
       'openstack_version_prev' => 'old_version',
       'deployment_mode' => 'ha_compact',
       'cobbler' => {
          'profile' => 'centos-x86_64'
        },
        'nodes' => [
          {
            'uid' => '1',
            'slave_name' => 'node-1',
            'role' => 'cinder'
          },
          {
            'uid' => '2',
            'slave_name' => 'node-2',
            'role' => 'controller'
          },
          {
            'uid' => '3',
            'slave_name' => 'node-3',
            'role' => 'mongo'
          }
        ],
      },
      {'uid' => '3',
       'role' => 'cinder'
      }]
    }

    it 'should get commands for service ban' do
      Astute::Pacemaker.expects(:commands).with('stop', transormed_data).returns(['basic command'])
      pre_patching_ha.expects(:run_shell_command).returns(:data => {:exit_code => 0})
      pre_patching_ha.process(deploy_data, ctx)
    end

    it 'should not run if no controllers in cluster' do
      deploy_data.first['role'] = 'cinder'

      Astute::Pacemaker.expects(:commands).never
      pre_patching_ha.expects(:run_shell_command).never
      pre_patching_ha.process(no_controllers, ctx)
    end

  end

end