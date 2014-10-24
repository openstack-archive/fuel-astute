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

require File.join(File.dirname(__FILE__), '../spec_helper')
require 'tmpdir'

describe Astute::DeploymentEngine do
  include SpecHelpers

  class Engine < Astute::DeploymentEngine; end

  let(:ctx) do
    tctx = mock_ctx
    tctx.stubs(:status).returns({})
    tctx
  end

  describe '#new' do
    it 'should not be avaliable to instantiation' do
      expect { Astute::DeploymentEngine.new(ctx) }.to raise_exception(/Instantiation of this superclass is not allowed/)
    end

    it 'should be avaliable as superclass' do
      expect { Engine.new(ctx) }.to be_true
    end
  end

  let(:deployer) { Engine.new(ctx) }

  describe '#deploy' do

    before(:each) do
      Astute::PreDeployActions.any_instance.stubs(:process).returns(nil)
      Astute::PostDeployActions.any_instance.stubs(:process).returns(nil)
      Astute::PreNodeActions.any_instance.stubs(:process).returns(nil)
      Astute::PreDeploymentActions.any_instance.stubs(:process).returns(nil)
      Astute::PostDeploymentActions.any_instance.stubs(:process).returns(nil)
    end

    context 'hooks' do

      let(:nodes) {
        [{'uid' => 1, 'priority' => 10}, {'uid' => 2, 'priority' => 0}, {'uid' => 1, 'priority' => 15}]
      }

      let(:pre_deployment) {
        [{
          "priority" =>  100,
          "type" =>  "upload_file",
          "uids" =>  [1, 2],
          "parameters" =>  {}
        }]
      }

      let(:post_deployment) {
        [{
          "priority" =>  100,
          "type" =>  "puppet",
          "uids" =>  [1, 2],
          "parameters" =>  {}
        }]
      }

      before(:each) { deployer.stubs(:deploy_piece) }

      it 'should run pre deployment hooks run once for all cluster' do
        Astute::PreDeploymentActions.any_instance.expects(:process).once

        deployer.deploy(nodes)
      end

      context 'nailgun hooks' do
        it 'should run pre and post deployment nailgun hooks run once for all cluster' do
          pre_hook = mock('pre')
          post_hook = mock('post')
          hook_order = sequence('hook_order')

          Astute::NailgunHooks.expects(:new).with(pre_deployment, ctx).returns(pre_hook)
          Astute::NailgunHooks.expects(:new).with(post_deployment, ctx).returns(post_hook)

          Astute::PreDeploymentActions.any_instance.expects(:process).in_sequence(hook_order)
          pre_hook.expects(:process).in_sequence(hook_order)
          deployer.expects(:deploy_piece).in_sequence(hook_order)
          post_hook.expects(:process).in_sequence(hook_order)
          Astute::PostDeploymentActions.any_instance.expects(:process).in_sequence(hook_order)

          deployer.deploy(nodes, pre_deployment, post_deployment)
        end

        it 'should not do additional update for node status if pre hooks failed' do
          pre_hook = mock('pre')
          Astute::NailgunHooks.expects(:new).with(pre_deployment, ctx).returns(pre_hook)
          pre_hook.expects(:process).raises(Astute::DeploymentEngineError)

          ctx.expects(:report_and_update_status).never

          expect {deployer.deploy(nodes, pre_deployment, post_deployment)}.to raise_error(Astute::DeploymentEngineError)
        end

        it 'should update all nodes status to error if post hooks failed' do
          pre_hook = mock('pre')
          post_hook = mock('post')
          Astute::NailgunHooks.expects(:new).with(pre_deployment, ctx).returns(pre_hook)
          pre_hook.expects(:process)

          Astute::NailgunHooks.expects(:new).with(post_deployment, ctx).returns(post_hook)
          post_hook.expects(:process).raises(Astute::DeploymentEngineError)

          ctx.expects(:report_and_update_status).with({
            'nodes' => [
              {'uid' => 1, 'status' => 'error', 'error_type' => 'deploy', 'role' => 'hook'},
              {'uid' => 2, 'status' => 'error', 'error_type' => 'deploy', 'role' => 'hook'}
            ]
          })

          expect {deployer.deploy(nodes, pre_deployment, post_deployment)}.to raise_error(Astute::DeploymentEngineError)
        end
      end

      it 'should run pre node hooks once for node' do
        Astute::PreNodeActions.any_instance.expects(:process).twice

        deployer.deploy(nodes)
      end

      it 'should run pre deploy hooks once for role' do
        Astute::PreDeployActions.any_instance.expects(:process).times(3)

        deployer.deploy(nodes)
      end

      it 'should run post deploy hooks once for role' do
        Astute::PostDeployActions.any_instance.expects(:process).times(3)

        deployer.deploy(nodes)
      end

      it 'should run post deployment hooks run once for all cluster' do
        Astute::PostDeploymentActions.any_instance.expects(:process).once

        deployer.deploy(nodes)
      end
    end

    it 'deploy nodes by order' do
      nodes = [{'uid' => 1, 'priority' => 10}, {'uid' => 2, 'priority' => 0}, {'uid' => 1, 'priority' => 15}]

      deploy_order = sequence('deploy_order')
      deployer.expects(:deploy_piece).with([{'uid' => 2, 'priority' => 0}]).in_sequence(deploy_order)
      deployer.expects(:deploy_piece).with([{'uid' => 1, 'priority' => 10}]).in_sequence(deploy_order)
      deployer.expects(:deploy_piece).with([{'uid' => 1, 'priority' => 15}]).in_sequence(deploy_order)

      deployer.deploy(nodes)
    end

    it 'nodes with same priority should be deploy at parallel' do
      nodes = [{'uid' => 1, 'priority' => 10}, {'uid' => 2, 'priority' => 0}, {'uid' => 3, 'priority' => 10}]

      deployer.expects(:deploy_piece).with([{'uid' => 2, 'priority' => 0}])
      deployer.expects(:deploy_piece).with([{"uid"=>1, "priority"=>10}, {"uid"=>3, "priority"=>10}])

      deployer.deploy(nodes)
    end

    it 'node with several roles with same priority should not run at parallel' do
      nodes = [
        {'uid' => 1, 'priority' => 10, 'role' => 'compute'},
        {'uid' => 2, 'priority' => 0, 'role' => 'primary-controller'},
        {'uid' => 1, 'priority' => 10, 'role' => 'cinder'}
      ]

      deployer.expects(:deploy_piece).with([{'uid' => 2, 'priority' => 0, 'role' => 'primary-controller'}])
      deployer.expects(:deploy_piece).with([{'uid' => 1, 'priority' => 10, 'role' => 'compute'}])
      deployer.expects(:deploy_piece).with([{'uid' => 1, 'priority' => 10, 'role' => 'cinder'}])

      deployer.deploy(nodes)
    end

    it 'node with several roles with same priority should not run at parallel, but different nodes should' do
      nodes = [
        {'uid' => 1, 'priority' => 10, 'role' => 'compute'},
        {'uid' => 3, 'priority' => 10, 'role' => 'compute'},
        {'uid' => 2, 'priority' => 0, 'role' => 'primary-controller'},
        {'uid' => 1, 'priority' => 10, 'role' => 'cinder'}
      ]

      deployer.expects(:deploy_piece).with([{'uid' => 2, 'priority' => 0, 'role' => 'primary-controller'}])
      deployer.expects(:deploy_piece).with([
        {'uid' => 1, 'priority' => 10, 'role' => 'compute'},
        {'uid' => 3, 'priority' => 10, 'role' => 'compute'}
      ])
      deployer.expects(:deploy_piece).with([{'uid' => 1, 'priority' => 10, 'role' => 'cinder'}])

      deployer.deploy(nodes)
    end


    context 'critical node' do

      let(:ctx)  { mock_ctx }

      it 'should stop deployment if critical node deployment fail' do
        nodes = [
          {'uid' => '1', 'priority' => 20, 'role' => 'compute', 'fail_if_error' => false},
          {'uid' => '3', 'priority' => 20, 'role' => 'compute', 'fail_if_error' => false},
          {'uid' => '2', 'priority' => 10, 'role' => 'primary-controller', 'fail_if_error' => true},
          {'uid' => '1', 'priority' => 20, 'role' => 'cinder', 'fail_if_error' => false},
          {'uid' => '2', 'priority' => 5, 'role' => 'mongo', 'fail_if_error' => false}
        ]
        ctx.stubs(:status).returns({'2' => 'success'}).then.returns({'2' => 'error'})

        deployer.expects(:deploy_piece).with([
          {'uid' => '2',
           'priority' => 5,
           'role' => 'mongo',
           'fail_if_error' => false}]
        )
        deployer.expects(:deploy_piece).with([
          {'uid' => '2',
           'priority' => 10,
           'role' => 'primary-controller',
           'fail_if_error' => true}]
        )

        ctx.stubs(:report_and_update_status)
        deployer.deploy(nodes)
      end

      it 'should not stop deployment if fail non-critical node' do
        nodes = [
          {'uid' => '1', 'priority' => 20, 'role' => 'compute', 'fail_if_error' => false},
          {'uid' => '2', 'priority' => 10, 'role' => 'primary-controller', 'fail_if_error' => true},
          {'uid' => '1', 'priority' => 5, 'role' => 'mongo', 'fail_if_error' => false}
        ]

        ctx.stubs(:status).returns({'1' => 'error'})
          .then.returns({'2' => 'success', '1' => 'error'})
          .then.returns({'1' => 'success', '2' => 'success' })

        deployer.expects(:deploy_piece).with([
          {'uid' => '1',
           'priority' => 5,
           'role' => 'mongo',
           'fail_if_error' => false}]
        )
        deployer.expects(:deploy_piece).with([
          {'uid' => '2',
           'priority' => 10,
           'role' => 'primary-controller',
           'fail_if_error' => true}]
        )
        deployer.expects(:deploy_piece).with([
          {'uid' => '1',
           'priority' => 20,
           'role' => 'compute',
           'fail_if_error' => false}]
        )

        deployer.deploy(nodes)
      end

      it 'should not send status for all nodes after nodes group where critical node fail' do
        nodes = [
          {'uid' => '1', 'priority' => 20, 'role' => 'compute', 'fail_if_error' => false},
          {'uid' => '3', 'priority' => 20, 'role' => 'compute', 'fail_if_error' => false},
          {'uid' => '2', 'priority' => 10, 'role' => 'primary-controller', 'fail_if_error' => true},
          {'uid' => '1', 'priority' => 20, 'role' => 'cinder', 'fail_if_error' => false},
          {'uid' => '2', 'priority' => 5, 'role' => 'mongo', 'fail_if_error' => false}
        ]
        ctx.stubs(:status).returns({'2' => 'success'}).then.returns({'2' => 'error'})

        deployer.stubs(:deploy_piece).twice

        ctx.expects(:report_and_update_status).never
        deployer.deploy(nodes)
      end

      it 'should not affect parallel nodes in same running group' do
        nodes = [
          {'uid' => '1', 'priority' => 20, 'role' => 'compute', 'fail_if_error' => false},
          {'uid' => '3', 'priority' => 20, 'role' => 'compute', 'fail_if_error' => false},
          {'uid' => '2', 'priority' => 10, 'role' => 'primary-controller', 'fail_if_error' => true},
          {'uid' => '2', 'priority' => 20, 'role' => 'cinder', 'fail_if_error' => false},
          {'uid' => '1', 'priority' => 10, 'role' => 'mongo', 'fail_if_error' => true}
        ]
        ctx.stubs(:status).returns({'2' => 'success', '1' => 'error'})

        deployer.stubs(:deploy_piece).once

        ctx.expects(:report_and_update_status).never

        deployer.deploy(nodes)
      end

      context 'limits' do
        around(:each) do |example|
          old_value = Astute.config.MAX_NODES_PER_CALL
          example.run
          Astute.config.MAX_NODES_PER_CALL = old_value
        end

        it 'should affect nodes with same priorities in next deployment group' do
          Astute.config.MAX_NODES_PER_CALL = 1

          nodes = [
            {'uid' => '2', 'priority' => 10, 'role' => 'primary-controller', 'fail_if_error' => true},
            {'uid' => '2', 'priority' => 20, 'role' => 'cinder', 'fail_if_error' => false},
            {'uid' => '1', 'priority' => 10, 'role' => 'mongo', 'fail_if_error' => true}
          ]
          ctx.stubs(:status).returns({'2' => 'error'})

          deployer.stubs(:deploy_piece).once

          ctx.expects(:report_and_update_status).never

          deployer.deploy(nodes)
        end
      end # 'limits'
    end

    context 'limits' do
      around(:each) do |example|
        old_value = Astute.config.MAX_NODES_PER_CALL
        example.run
        Astute.config.MAX_NODES_PER_CALL = old_value
      end

      it 'number of nodes running in parallel should be limited' do
        Astute.config.MAX_NODES_PER_CALL = 1

        nodes = [
          {'uid' => 1, 'priority' => 10, 'role' => 'compute'},
          {'uid' => 3, 'priority' => 10, 'role' => 'compute'},
          {'uid' => 2, 'priority' => 0, 'role' => 'primary-controller'},
          {'uid' => 1, 'priority' => 10, 'role' => 'cinder'}
        ]

        deployer.expects(:deploy_piece).with([{'uid' => 2, 'priority' => 0, 'role' => 'primary-controller'}])
        deployer.expects(:deploy_piece).with([{'uid' => 1, 'priority' => 10, 'role' => 'compute'}])
        deployer.expects(:deploy_piece).with([{'uid' => 3, 'priority' => 10, 'role' => 'compute'}])
        deployer.expects(:deploy_piece).with([{'uid' => 1, 'priority' => 10, 'role' => 'cinder'}])

        deployer.deploy(nodes)
      end
    end

    it 'should raise error if deployment list is empty' do
      expect { deployer.deploy([]) }.to raise_error('Deployment info are not provided!')
    end

  end
end
