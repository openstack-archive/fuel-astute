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

describe Astute::Pacemaker do
  include SpecHelpers

  let(:ctx) do
    ctx = mock('context')
    ctx.stubs(:task_id)
    ctx.stubs(:reporter)
    ctx.stubs(:status).returns('1' => 'success', '2' => 'success')
    ctx
  end

  let(:pacemaker) { Astute::Pacemaker }

  let(:deploy_data) { [
                        {'uid' => '1',
                         'role' => 'controller',
                         'openstack_version_prev' => 'old_version',
                         'deployment_mode' => 'ha_compact',
                         'cobbler' => {
                            'profile' => 'centos-x86_64'
                          },
                         'nodes' => [
                          {'uid' => '1', 'role' => 'controller'},
                          {'uid' => '2', 'role' => 'compute'}
                         ]
                        },
                        {'uid' => '2',
                         'role' => 'compute'
                        }
                      ]
                    }

  it 'should return empty array if deployment mode not HA' do
    deploy_data.first['deployment_mode'] = 'simple'
    expect(pacemaker.commands(behavior='stop', deploy_data)).to eql([])
  end

  it 'should return empty array if no controllers' do
    deploy_data.first['role'] = 'cinder'
    expect(pacemaker.commands(behavior='stop', deploy_data)).to eql([])
  end

  context 'controller < 3' do
    it 'should return stop service commands for pacemaker' do
      expect(pacemaker.commands(behavior='stop', deploy_data)).to eql(
        ['crm resource stop openstack-heat-engine && sleep 3',
         'crm resource stop p_openstack-heat-engine && sleep 3'])
    end

    it 'should return start service commands for HA pacemaker' do
      expect(pacemaker.commands(behavior='start', deploy_data)).to eql(
        ['crm resource start openstack-heat-engine && sleep 3',
         'crm resource start p_openstack-heat-engine && sleep 3'])
    end
  end

  context 'controller >= 3' do

    let(:ha_deploy_data) {
      deploy_data.first['nodes'] = [
        {'uid' => '1', 'role' => 'controller'},
        {'uid' => '2', 'role' => 'compute'},
        {'uid' => '3', 'role' => 'primary-controller'},
        {'uid' => '4', 'role' => 'controller'},
       ]
      deploy_data
    }

    it 'should return stop service commands for pacemaker' do
      expect(pacemaker.commands(behavior='stop', ha_deploy_data)).to eql(
        ['pcs resource ban openstack-heat-engine `crm_node -n` && sleep 3',
         'pcs resource ban p_openstack-heat-engine `crm_node -n` && sleep 3'])
    end

    it 'should return start service commands for pacemaker' do
      expect(pacemaker.commands(behavior='start', ha_deploy_data)).to eql(
        ['pcs resource clear openstack-heat-engine `crm_node -n` && sleep 3',
         'pcs resource clear p_openstack-heat-engine `crm_node -n` && sleep 3'])
    end
  end

  it 'should return quantum service commands if quantum enable' do
    deploy_data.first['quantum'] = []
    expect(pacemaker.commands(behavior='stop', deploy_data).size).to eql(6)
  end

  it 'should return ceilometer service commands if ceilometer enable' do
    deploy_data.first['ceilometer'] = { 'enabled' => true }
    expect(pacemaker.commands(behavior='stop', deploy_data).size).to eql(4)
  end

end