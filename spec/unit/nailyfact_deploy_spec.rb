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

describe "NailyFact DeploymentEngine" do
  include SpecHelpers

  context "When deploy is called, " do
    let(:ctx) do
      ctx = mock
      ctx.stubs(:task_id)
      ctx.stubs(:deploy_log_parser).returns(Astute::LogParser::NoParsing.new)
      ctx.stubs(:status).returns({})
      reporter = mock
      reporter.stubs(:report)
      up_reporter = Astute::ProxyReporter::DeploymentProxyReporter.new(reporter, deploy_data)
      ctx.stubs(:reporter).returns(up_reporter)
      ctx
    end

    let(:deploy_engine) do
      Astute::DeploymentEngine::NailyFact.new(ctx)
    end

    let(:controller_nodes) do
      nodes_with_role(deploy_data, 'controller')
    end

    let(:compute_nodes) do
      nodes_with_role(deploy_data, 'compute')
    end

    let(:cinder_nodes) do
      nodes_with_role(deploy_data, 'cinder')
    end

    before(:each) do
      uniq_nodes_uid = deploy_data.map {|n| n['uid'] }.uniq
      Astute::PreDeploymentActions.any_instance.stubs(:process).returns(nil)
      Astute::PostDeploymentActions.any_instance.stubs(:process).returns(nil)
      Astute::PreDeployActions.any_instance.stubs(:process).returns(nil)
      Astute::PreNodeActions.any_instance.stubs(:process).returns(nil)
      Astute::PreDeployActions.any_instance.stubs(:process).returns(nil)
    end

    context 'log parsing' do
      let(:deploy_data) do
        [{'uid' => 1, 'role' => 'controller', 'deployment_mode' => 'unknown', 'deployment_id' => '123'}]
      end

      it "it should not raise an exception if deployment mode is unknown" do
        Astute::PuppetdDeployer.stubs(:deploy).with(ctx, deploy_data, instance_of(Fixnum)).once
        expect {deploy_engine.deploy(deploy_data)}.to_not raise_exception
      end
    end

    context 'multinode deploy ' do
      let(:deploy_data) do
        Fixtures.multi_deploy
      end

      it "should not raise any exception" do
        # we got two calls, one for controller (high priority), and another for all computes (same low priority)
        Astute::PuppetdDeployer.expects(:deploy).with(ctx, controller_nodes, instance_of(Fixnum)).once
        Astute::PuppetdDeployer.expects(:deploy).with(ctx, compute_nodes, instance_of(Fixnum)).once

        expect {deploy_engine.deploy(deploy_data)}.to_not raise_exception
      end
    end

    context 'multiroles support' do
      let(:deploy_data) do
        data = Fixtures.multi_deploy
        compute_node = deep_copy(data.last)
        cinder_node = deep_copy(data.last)
        cinder_node['role'] = 'cinder'
        [compute_node, cinder_node]
      end

      let(:node_amount) { deploy_data.size }

      it "should prepare log parsing for every deploy call because node may be deployed several times" do
        ctx.deploy_log_parser.expects(:prepare).with(compute_nodes).once
        ctx.deploy_log_parser.expects(:prepare).with(cinder_nodes).once

        Astute::PuppetdDeployer.expects(:deploy).times(2)

        deploy_engine.deploy(deploy_data)
      end

      it "should generate and publish facts for every deploy call because node may be deployed several times" do
        ctx.deploy_log_parser.expects(:prepare).with(compute_nodes).once
        ctx.deploy_log_parser.expects(:prepare).with(cinder_nodes).once

        Astute::PuppetdDeployer.expects(:deploy).times(2)

        deploy_engine.deploy(deploy_data)
      end
    end

    context 'ha deploy' do
      let(:deploy_data) do
        Fixtures.ha_deploy
      end

      it "ha deploy should not raise any exception" do
        primary_controller = deploy_data.find { |n| n['role'] == 'primary-controller' }
        Astute::PuppetdDeployer.expects(:deploy).with(ctx, [primary_controller], 1).once

        controller_nodes.each do |n|
          Astute::PuppetdDeployer.expects(:deploy).with(ctx, [n], 1).once
        end
        Astute::PuppetdDeployer.expects(:deploy).with(ctx, compute_nodes, instance_of(Fixnum)).once

        deploy_engine.deploy(deploy_data)
      end

      context 'exception case' do
        let(:deploy_data) do
          [Fixtures.ha_deploy.find { |n| n['role'] == 'controller' }]
        end

        it "ha deploy should not raise any exception if there are only one controller" do
          Astute::PuppetdDeployer.expects(:deploy).once

          deploy_engine.deploy(deploy_data)
        end
      end
    end # 'ha deploy'
  end
end
