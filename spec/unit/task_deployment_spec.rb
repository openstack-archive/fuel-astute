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

describe Astute::TaskDeployment do
  include SpecHelpers

  let(:ctx) do
    ctx = mock('context')
    ctx.stubs(:task_id)
    ctx
  end

  let(:deployment_info) do
    [
      {
        'uid' => '1',
        'fail_if_error' => false
      }
    ]
  end

  let(:tasks_graph) do
    {"1"=>
      [{
        "type"=>"noop",
        "fail_on_error"=>true,
        "required_for"=>[],
        "requires"=> [],
        "id"=>"ironic_post_swift_key"
      }],
      "null"=> [{
        "skipped"=>true,
        "type"=>"skipped",
        "fail_on_error"=>false,
        "required_for"=>[],
        "requires"=>[],
        "id"=>"post_deployment_start"}]
    }
  end

  let(:tasks_directory) do
    {"ironic_post_swift_key"=>{
      "parameters"=>{
        "retries"=>3,
        "cmd"=>"sh generate_keys.sh -i 1 -s 'ceph' -p /var/lib/fuel/keys/",
        "cwd"=>"/",
        "timeout"=>180,
        "interval"=>1},
       "type"=>"shell",
       "id"=>"ironic_post_swift_key"},
     "post_deployment_start"=>{
       "parameters"=>{}
     }
    }
  end

  let(:task_deployment) { Astute::TaskDeployment.new(ctx) }

  describe '#deploy' do
    it 'should run deploy' do
      task_deployment.stubs(:remove_failed_nodes).returns([deployment_info, []])
      Astute::TaskPreDeploymentActions.any_instance.stubs(:process)
      task_deployment.stubs(:write_graph_to_file)
      ctx.stubs(:report)

      Astute::TaskCluster.any_instance.expects(:run).returns({:success => true})
      task_deployment.deploy(deployment_info, tasks_graph, tasks_directory)
    end

    it 'should raise error if deployment info not provided' do
      expect{task_deployment.deploy([],{}, {})}.to raise_error(
        Astute::DeploymentEngineError,
        "Deployment info are not provided!"
      )
    end

    it 'should run pre deployment task' do
      task_deployment.stubs(:remove_failed_nodes).returns([deployment_info, []])
      task_deployment.stubs(:write_graph_to_file)
      ctx.stubs(:report)
      Astute::TaskCluster.any_instance.stubs(:run).returns({:success => true})

      pre_deployment = Astute::TaskPreDeploymentActions.new(deployment_info, ctx)
      Astute::TaskPreDeploymentActions.expects(:new)
                                      .with(deployment_info, ctx)
                                      .returns(pre_deployment)
      Astute::TaskPreDeploymentActions.any_instance.expects(:process)
      task_deployment.deploy(deployment_info, tasks_graph, tasks_directory)
    end

    it 'should support virtual node' do
      d_t = task_deployment.send(:support_virtual_node, tasks_graph)
      expect(d_t.keys).to include 'virtual_sync_node'
      expect(d_t.keys).not_to include 'null'
    end

    it 'should remove failed nodes' do
      #TODO(vsharshov): improve remove failed nodes check. Check mcollective
      Astute::TaskPreDeploymentActions.any_instance.stubs(:process)
      task_deployment.stubs(:write_graph_to_file)
      ctx.stubs(:report)

      task_deployment.expects(:remove_failed_nodes).returns([deployment_info, []])

      Astute::TaskCluster.any_instance.stubs(:run).returns({:success => true})
      task_deployment.deploy(deployment_info, tasks_graph, tasks_directory)
    end

    it 'should setup stop condition' do
      Astute::TaskPreDeploymentActions.any_instance.stubs(:process)
      task_deployment.stubs(:write_graph_to_file)
      ctx.stubs(:report)
      task_deployment.stubs(:remove_failed_nodes).returns([deployment_info, []])
      Astute::TaskCluster.any_instance.stubs(:run).returns({:success => true})

      Astute::TaskCluster.any_instance.expects(:stop_condition)
      task_deployment.deploy(deployment_info, tasks_graph, tasks_directory)
    end

    it 'should setup deployment logger' do
      Astute::TaskPreDeploymentActions.any_instance.stubs(:process)
      task_deployment.stubs(:write_graph_to_file)
      ctx.stubs(:report)
      task_deployment.stubs(:remove_failed_nodes).returns([deployment_info, []])
      Astute::TaskCluster.any_instance.stubs(:run).returns({:success => true})

      Deployment::Log.expects(:logger=).with(Astute.logger)
      task_deployment.deploy(deployment_info, tasks_graph, tasks_directory)
    end

    context 'config' do
      around(:each) do |example|
        max_nodes_old_value = Astute.config.max_nodes_per_call
        example.run
        Astute.config.max_nodes_per_call = max_nodes_old_value
      end

      it 'should setup max nodes per call using config' do
        Astute.config.max_nodes_per_call = 33

        task_deployment.stubs(:remove_failed_nodes).returns([deployment_info, []])
        Astute::TaskPreDeploymentActions.any_instance.stubs(:process)
        task_deployment.stubs(:write_graph_to_file)
        ctx.stubs(:report)

        Astute::TaskCluster.any_instance
          .stubs(:run)
          .returns({:success => true})

        node_concurrency = mock('node_concurrency')
        Astute::TaskCluster.any_instance
          .expects(:node_concurrency).returns(node_concurrency)

        node_concurrency.expects(:maximum=).with(Astute.config.max_nodes_per_call)

        task_deployment.deploy(deployment_info, tasks_graph, tasks_directory)
      end
    end

    context 'should report final status' do

      it 'succeed status' do
        Astute::TaskPreDeploymentActions.any_instance.stubs(:process)
        Astute::TaskCluster.any_instance.stubs(:run).returns({:success => true})
        task_deployment.stubs(:remove_failed_nodes).returns([deployment_info, []])
        task_deployment.stubs(:write_graph_to_file)
        ctx.expects(:report).with({'status' => 'ready', 'progress' => 100})

        task_deployment.deploy(deployment_info, tasks_graph, tasks_directory)
      end

      it 'failed status' do
        Astute::TaskPreDeploymentActions.any_instance.stubs(:process)
        Astute::TaskCluster.any_instance.stubs(:run).returns({
          :success => false,
          :failed_nodes => [],
          :failed_tasks => [],
          :status => 'Failed because of'})
        task_deployment.stubs(:remove_failed_nodes).returns([deployment_info, []])
        task_deployment.stubs(:write_graph_to_file)
        ctx.expects(:report).with({
            'status' => 'error',
            'progress' => 100,
            'error' => 'Failed because of'})

        task_deployment.deploy(deployment_info, tasks_graph, tasks_directory)
      end
    end

    context 'graph file' do

      around(:each) do |example|
        old_value = Astute.config.enable_graph_file
        example.run
        Astute.config.enable_graph_file = old_value
      end

      it 'should write if disable' do
        Astute.config.enable_graph_file = false

        task_deployment.stubs(:remove_failed_nodes).returns([deployment_info, []])
        Astute::TaskPreDeploymentActions.any_instance.stubs(:process)
        ctx.stubs(:report)
        Astute::TaskCluster.any_instance.stubs(:run).returns({:success => true})

        file_handle = mock
        file_handle.expects(:write).with(regexp_matches(/digraph/)).never
        File.expects(:open).with("/tmp/graph-#{ctx.task_id}.dot", 'w')
            .yields(file_handle).never

        task_deployment.deploy(deployment_info, tasks_graph, tasks_directory)
      end

      it 'should write graph if enable' do
        Astute.config.enable_graph_file = true

        task_deployment.stubs(:remove_failed_nodes).returns([deployment_info, []])
        Astute::TaskPreDeploymentActions.any_instance.stubs(:process)
        ctx.stubs(:report)
        Astute::TaskCluster.any_instance.stubs(:run).returns({:success => true})

        file_handle = mock
        file_handle.expects(:write).with(regexp_matches(/digraph/)).once
        File.expects(:open).with("/tmp/graph-#{ctx.task_id}.dot", 'w')
            .yields(file_handle).once

        task_deployment.deploy(deployment_info, tasks_graph, tasks_directory)
      end
    end # 'graph file'

  end

end
