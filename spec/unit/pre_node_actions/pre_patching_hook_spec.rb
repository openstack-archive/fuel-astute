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

require File.join(File.dirname(__FILE__), '../../spec_helper')

describe Astute::PrePatching do
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
                         'role' => 'controller',
                         'openstack_version_prev' => 'old_version',
                         'cobbler' => {
                            'profile' => 'centos-x86_64'
                          }
                        },
                        {'uid' => '2',
                         'role' => 'compute'
                        }
                      ]
                    }

  let(:pre_patching) { Astute::PrePatching.new }

  it 'should run if upgrade/downgrade env' do
    pre_patching.expects(:run_shell_command).once.returns(:data => {:exit_code => 0})
    pre_patching.process(deploy_data, ctx)
  end

  it 'should not run if deploy new env' do
    deploy_data.first.delete('openstack_version_prev')
    pre_patching.process(deploy_data, ctx)
    pre_patching.expects(:run_shell_command).never

    pre_patching.process(deploy_data, ctx)
  end

  it 'should not change deployment status if command fail' do
    pre_patching.expects(:run_shell_command).once.returns(:data => {:exit_code => 1})
    ctx.expects(:report_and_update_status).never

    pre_patching.process(deploy_data, ctx)
  end

  it 'should not change deployment status if shell exec using mcollective fail' do
    pre_patching.expects(:run_shell_command).once.returns(:data => {})

    pre_patching.process(deploy_data, ctx)
    ctx.expects(:report_and_update_status).never
  end

  describe '#getremovepackage_cmd' do

    it 'should use yum command for CenoOS system' do
      pre_patching.expects(:run_shell_command).once.with(
        ctx,
        ['1', '2'],
        regexp_matches(/yum/),
        is_a(Integer))
      .returns(:data => {:exit_code => 0})

      pre_patching.process(deploy_data, ctx)
    end

    it 'should use aptitude command for Ubuntu system' do
      new_deploy_data = deploy_data.clone
      new_deploy_data.first['cobbler']['profile'] = 'ubuntu_1204_x86_64'
      pre_patching.expects(:run_shell_command).once.with(
        ctx,
        ['1', '2'],
        regexp_matches(/aptitude/),
        is_a(Integer))
      .returns(:data => {:exit_code => 0})

      pre_patching.process(new_deploy_data, ctx)
    end

    it 'raise error if target system unknown' do
      new_deploy_data = deploy_data.clone
      new_deploy_data.first['cobbler']['profile'] = 'unknown'
      pre_patching.expects(:run_shell_command).never
      expect { pre_patching.process(new_deploy_data, ctx) }.to raise_error(Astute::DeploymentEngineError, /Unknown system/)
    end

  end # getremovepackage_cmd

end