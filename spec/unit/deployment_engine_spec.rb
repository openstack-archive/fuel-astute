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

  class Engine < Astute::DeploymentEngine;

    def pre_deployment_actions(deployment_info, pre_deployment)
    end

    def pre_node_actions(part)
    end

    def pre_deploy_actions(part)
    end

    def post_deploy_actions(part)
    end

    def post_deployment_actions(deployment_info, post_deployment)
    end
  end

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
      expect(Engine.new(ctx)).to be_truthy
    end
  end

  let(:deployer) { Engine.new(ctx) }

  describe '#deploy' do
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
        deployer.expects(:pre_deployment_actions).with(nodes, []).once

        deployer.stubs(:remove_failed_nodes).returns([nodes, [], []])

        deployer.deploy(nodes)
      end

      it 'should run post deployment hooks run once for all cluster' do
        deployer.expects(:post_deployment_actions).with(nodes, []).once

        deployer.stubs(:remove_failed_nodes).returns([nodes, [], []])

        deployer.deploy(nodes)
      end

      context 'hooks' do
        it 'should run pre and post deployment nailgun hooks run once for all cluster' do
          hook_order = sequence('hook_order')

          deployer.expects(:pre_deployment_actions).in_sequence(hook_order)
          deployer.expects(:deploy_piece).in_sequence(hook_order)
          deployer.expects(:post_deployment_actions).in_sequence(hook_order)

          deployer.stubs(:remove_failed_nodes).returns([nodes, [], []])

          deployer.deploy(nodes, pre_deployment, post_deployment)
        end

        it 'should not do additional update for node status if pre hooks failed' do
          deployer.expects(:pre_deployment_actions).raises(Astute::DeploymentEngineError)

          ctx.expects(:report_and_update_status).never

          deployer.stubs(:remove_failed_nodes).returns([nodes, [], []])

          expect {deployer.deploy(nodes, pre_deployment, post_deployment)}.to raise_error(Astute::DeploymentEngineError)
        end
      end

    end

    let(:mclient) do
      mclient = mock_rpcclient
      Astute::MClient.any_instance.stubs(:rpcclient).returns(mclient)
      Astute::MClient.any_instance.stubs(:log_result).returns(mclient)
      Astute::MClient.any_instance.stubs(:check_results_with_retries).returns(mclient)
      mclient
    end

    it 'deploy nodes by order' do
      nodes = [{'uid' => 1, 'priority' => 10}, {'uid' => 2, 'priority' => 0}, {'uid' => 1, 'priority' => 15}]

      deployer.stubs(:remove_failed_nodes).returns([nodes, [], []])

      deploy_order = sequence('deploy_order')
      deployer.expects(:deploy_piece).with([{'uid' => 2, 'priority' => 0}]).in_sequence(deploy_order)
      deployer.expects(:deploy_piece).with([{'uid' => 1, 'priority' => 10}]).in_sequence(deploy_order)
      deployer.expects(:deploy_piece).with([{'uid' => 1, 'priority' => 15}]).in_sequence(deploy_order)

      deployer.deploy(nodes)
    end

    it 'nodes with same priority should be deploy at parallel' do
      nodes = [{'uid' => 1, 'priority' => 10}, {'uid' => 2, 'priority' => 0}, {'uid' => 3, 'priority' => 10}]

      deployer.stubs(:remove_failed_nodes).returns([nodes, [], []])

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

      deployer.stubs(:remove_failed_nodes).returns([nodes, [], []])

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

      deployer.stubs(:remove_failed_nodes).returns([nodes, [], []])

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

        deployer.stubs(:remove_failed_nodes).returns([nodes, [], []])

        expect {deployer.deploy(nodes)}.to raise_error(Astute::DeploymentEngineError, "Deployment failed on nodes 2")
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

        deployer.stubs(:remove_failed_nodes).returns([nodes, [], []])

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

        deployer.stubs(:remove_failed_nodes).returns([nodes, [], []])

        expect {deployer.deploy(nodes)}.to raise_error(Astute::DeploymentEngineError)
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

        deployer.stubs(:remove_failed_nodes).returns([nodes, [], []])

        expect {deployer.deploy(nodes)}.to raise_error(Astute::DeploymentEngineError)
      end

      context 'limits' do
        around(:each) do |example|
          old_value = Astute.config.max_nodes_per_call
          example.run
          Astute.config.max_nodes_per_call = old_value
        end

        it 'should affect nodes with same priorities in next deployment group' do
          Astute.config.max_nodes_per_call = 1

          nodes = [
            {'uid' => '2', 'priority' => 10, 'role' => 'primary-controller', 'fail_if_error' => true},
            {'uid' => '2', 'priority' => 20, 'role' => 'cinder', 'fail_if_error' => false},
            {'uid' => '1', 'priority' => 10, 'role' => 'mongo', 'fail_if_error' => true}
          ]
          ctx.stubs(:status).returns({'2' => 'error'})

          deployer.stubs(:deploy_piece).once

          ctx.expects(:report_and_update_status).never

          deployer.stubs(:remove_failed_nodes).returns([nodes, [], []])

          expect {deployer.deploy(nodes)}.to raise_error(Astute::DeploymentEngineError)
        end
      end # 'limits'
    end

    context 'limits' do
      around(:each) do |example|
        old_value = Astute.config.max_nodes_per_call
        example.run
        Astute.config.max_nodes_per_call = old_value
      end

      it 'number of nodes running in parallel should be limited' do
        Astute.config.max_nodes_per_call = 1

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

        deployer.stubs(:remove_failed_nodes).returns([nodes, [], []])

        deployer.deploy(nodes)
      end
    end

    it 'should raise error if deployment list is empty' do
      expect { deployer.deploy([]) }.to raise_error('Deployment info are not provided!')
    end

    it 'should not remove provisioned nodes' do
      nodes = [
        {'uid' => "1", 'priority' => 10, 'role' => 'compute'},
        {'uid' => "3", 'priority' => 10, 'role' => 'compute'},
        {'uid' => "2", 'priority' => 10, 'role' => 'primary-controller'}
      ]
      res1 = {:data => {:node_type => 'target'},
             :sender=>"1"}
      res2 = {:data => {:node_type => 'target'},
             :sender=>"2"}
      res3 = {:data => {:node_type => 'target'},
             :sender=>"3"}
      mc_res1 = mock_mc_result(res1)
      mc_res2 = mock_mc_result(res2)
      mc_res3 = mock_mc_result(res3)
      mc_timeout = 10

      rpcclient = mock_rpcclient(nodes, mc_timeout)
      rpcclient.expects(:get_type).once.returns([mc_res1, mc_res2, mc_res3])

      deployer.expects(:deploy_piece).with(nodes)

      deployer.deploy(nodes)
    end

    it 'should skip failed nodes' do
      nodes = [
        {'uid' => "1", 'priority' => 10, 'role' => 'compute',
          'nodes' => [
            {'uid' => '1', 'role' => 'compute'},
            {'uid' => '2', 'role' => 'primary-controller'},
            {'uid' => '3', 'role' => 'compute'},
            {'uid' => '4', 'role' => 'compute'}
          ]
        },
        {'uid' => "3", 'priority' => 10, 'role' => 'compute',
          'nodes' => [
            {'uid' => '1', 'role' => 'compute'},
            {'uid' => '2', 'role' => 'primary-controller'},
            {'uid' => '3', 'role' => 'compute'},
            {'uid' => '4', 'role' => 'compute'}
          ]
        },
        {'uid' => "2", 'priority' => 10, 'role' => 'primary-controller',
          'nodes' => [
            {'uid' => '1', 'role' => 'compute'},
            {'uid' => '2', 'role' => 'primary-controller'},
            {'uid' => '3', 'role' => 'compute'},
            {'uid' => '4', 'role' => 'compute'}
          ]
        }
      ]
      correct_nodes = [
        {'uid' => "1", 'priority' => 10, 'role' => 'compute',
          'nodes' => [
            {'uid' => '1', 'role' => 'compute'},
            {'uid' => '2', 'role' => 'primary-controller'},
          ]
        },
        {'uid' => "2", 'priority' => 10, 'role' => 'primary-controller',
          'nodes' => [
            {'uid' => '1', 'role' => 'compute'},
            {'uid' => '2', 'role' => 'primary-controller'},
          ]
        }
      ]
      res1 = {:data => {:node_type => "target\n"},
             :sender=>"1"}
      res2 = {:data => {:node_type => "target"},
             :sender=>"2"}
      mc_res1 = mock_mc_result(res1)
      mc_res2 = mock_mc_result(res2)

      mclient.expects(:get_type).times(Astute.config[:mc_retries]).returns([mc_res1, mc_res2])

      ctx.expects(:report_and_update_status).with(
        'nodes' => [{
          'uid' => '3',
          'status' => 'error',
          'error_type' => 'provision',
          'role' => 'hook',
          'error_msg' => 'Node is not ready for deployment: mcollective has not answered'
        },{
          'uid' => '4',
          'status' => 'error',
          'error_type' => 'provision',
          'role' => 'hook',
          'error_msg' => 'Node is not ready for deployment: mcollective has not answered'
        }],
        'error' => 'Node is not ready for deployment'
      )
      deployer.expects(:deploy_piece).with(correct_nodes)

      deployer.deploy(nodes)
    end

    it 'should remove failed nodes from pre and post deployment tasks' do
      tasks = [
        {"priority"=>200, "uids"=>["1", "2"]},
        {"priority"=>300, "uids"=>["1", "2", "3"]},
        {"priority"=>300, "uids"=>["3"]}
      ]
      correct_tasks = [
        {"priority"=>200, "uids"=>["1", "2"]},
        {"priority"=>300, "uids"=>["1", "2"]}
      ]

      nodes = [
        {'uid' => "1", 'priority' => 10, 'role' => 'compute',
          'nodes' => [
            {'uid' => '1', 'role' => 'compute'},
            {'uid' => '2', 'role' => 'primary-controller'},
            {'uid' => '4', 'role' => 'compute'}
          ]},
        {'uid' => "3", 'priority' => 10, 'role' => 'compute',
          'nodes' => [
            {'uid' => '1', 'role' => 'compute'},
            {'uid' => '2', 'role' => 'primary-controller'},
            {'uid' => '4', 'role' => 'compute'}
          ]},
        {'uid' => "2", 'priority' => 10, 'role' => 'primary-controller',
          'nodes' => [
            {'uid' => '1', 'role' => 'compute'},
            {'uid' => '2', 'role' => 'primary-controller'},
            {'uid' => '4', 'role' => 'compute'}
          ]
        }
      ]
      correct_nodes = [
        {'uid' => "1", 'priority' => 10, 'role' => 'compute',
          'nodes' => [
            {'uid' => '1', 'role' => 'compute'},
            {'uid' => '2', 'role' => 'primary-controller'},
          ]
        },
        {'uid' => "2", 'priority' => 10, 'role' => 'primary-controller',
          'nodes' => [
            {'uid' => '1', 'role' => 'compute'},
            {'uid' => '2', 'role' => 'primary-controller'},
          ]
        }
      ]
      res1 = {:data => {:node_type => "target\n"},
             :sender=>"1"}
      res2 = {:data => {:node_type => "target"},
             :sender=>"2"}
      mc_res1 = mock_mc_result(res1)
      mc_res2 = mock_mc_result(res2)

      mclient.expects(:get_type).times(Astute.config[:mc_retries]).returns([mc_res1, mc_res2])

      ctx.expects(:report_and_update_status).with(
        'nodes' => [{
          'uid' => '3',
          'status' => 'error',
          'error_type' => 'provision',
          'role' => 'hook',
          'error_msg' => 'Node is not ready for deployment: mcollective has not answered'
        }, {
          'uid' => '4',
          'status' => 'error',
          'error_type' => 'provision',
          'role' => 'hook',
          'error_msg' => 'Node is not ready for deployment: mcollective has not answered'
        }],
        'error' => 'Node is not ready for deployment'
      )
      deployer.expects(:pre_deployment_actions).with(correct_nodes, correct_tasks)
      deployer.expects(:deploy_piece).with(correct_nodes)
      deployer.expects(:post_deployment_actions).with(correct_nodes, correct_tasks)

      deployer.deploy(nodes, tasks, tasks)
    end

    it 'should raise error if critical node is missing' do
      nodes = [
        {'uid' => "1", 'priority' => 10, 'role' => 'compute',
          'nodes' => [
            {'uid' => '1', 'role' => 'compute'},
            {'uid' => '2', 'role' => 'primary-controller'},
            {'uid' => '4', 'role' => 'compute'}
          ]
        },
        {'uid' => "3", 'priority' => 10, 'role' => 'compute',
          'nodes' => [
            {'uid' => '1', 'role' => 'compute'},
            {'uid' => '2', 'role' => 'primary-controller'},
            {'uid' => '4', 'role' => 'compute'}
          ]
        },
        {'uid' => "2", 'priority' => 10, 'role' => 'primary-controller',
          'fail_if_error' => true, 'nodes' => [
            {'uid' => '1', 'role' => 'compute'},
            {'uid' => '2', 'role' => 'primary-controller'},
            {'uid' => '4', 'role' => 'compute'}
        ]}
      ]

      res1 = {:data => {:node_type => "target\n"},
             :sender=>"1"}
      res2 = {:data => {:node_type => 'target'},
             :sender=>"3"}

      mc_res1 = mock_mc_result(res1)
      mc_res2 = mock_mc_result(res2)
      mclient.expects(:get_type).times(Astute.config[:mc_retries]).returns([mc_res1, mc_res2])

      ctx.expects(:report_and_update_status).with(
        'nodes' => [{
          'uid' => '2',
          'status' => 'error',
          'error_type' => 'provision',
          'role' => 'hook',
          'error_msg' => 'Node is not ready for deployment: mcollective has not answered'
        },{
          'uid' => '4',
          'status' => 'error',
          'error_type' => 'provision',
          'role' => 'hook',
          'error_msg' => 'Node is not ready for deployment: mcollective has not answered'
        }],
        'error' => 'Node is not ready for deployment'
      )

      expect { deployer.deploy(nodes) }.to raise_error(Astute::DeploymentEngineError, "Critical nodes are not available for deployment: [\"2\"]")
    end

    it 'should ask about type several times' do
      nodes = [
       {'uid' => "1", 'priority' => 10, 'role' => 'compute'},
       {'uid' => "3", 'priority' => 10, 'role' => 'compute'},
       {'uid' => "2", 'priority' => 10, 'role' => 'primary-controller'}
      ]

      res1 = {:data => {:node_type => 'target'},
            :sender=>"1"}
      res2 = {:data => {:node_type => 'target'},
            :sender=>"2"}
      res3 = {:data => {:node_type => 'target'},
            :sender=>"3"}
      mc_res1 = mock_mc_result(res1)
      mc_res2 = mock_mc_result(res2)
      mc_res3 = mock_mc_result(res3)

      mclient.expects(:get_type).times(3).returns([mc_res1])
        .then.returns([mc_res2])
        .then.returns([mc_res3])

      deployer.expects(:deploy_piece).with(nodes)

      deployer.deploy(nodes)
    end

  end
end
