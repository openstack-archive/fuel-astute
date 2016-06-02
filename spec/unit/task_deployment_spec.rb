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
        "id"=>"ironic_post_swift_key",
        "parameters"=>{}
      }],
      "null"=> [{
        "skipped"=>true,
        "type"=>"skipped",
        "fail_on_error"=>false,
        "required_for"=>[],
        "requires"=>[],
        "parameters"=>{},
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

  before(:each) do
    task_deployment.stubs(:write_yaml_to_file)
    task_deployment.stubs(:write_info_to_file)
  end

  describe '#deploy' do
    it 'should run deploy' do
      task_deployment.stubs(:remove_failed_nodes).returns([deployment_info, []])
      Astute::TaskPreDeploymentActions.any_instance.stubs(:process)
      task_deployment.stubs(:write_graph_to_file)
      ctx.stubs(:report)

      Astute::TaskCluster.any_instance.expects(:run).returns({:success => true})
      task_deployment.deploy(
        deployment_info: deployment_info,
        tasks_graph: tasks_graph,
        tasks_directory: tasks_directory)
    end

    it 'should not raise error if deployment info not provided' do
      task_deployment.stubs(:remove_failed_nodes).returns([deployment_info, []])
      Astute::TaskPreDeploymentActions.any_instance.stubs(:process)
      task_deployment.stubs(:write_graph_to_file)
      ctx.stubs(:report)

      Astute::TaskCluster.any_instance.expects(:run).returns({:success => true})
      expect{task_deployment.deploy(
        tasks_graph: tasks_graph,
        tasks_directory: tasks_directory)}.to_not raise_error
    end

    it 'should raise error if tasks graph not provided' do
      expect{task_deployment.deploy(
        tasks_directory: tasks_directory)}.to raise_error(
        Astute::DeploymentEngineError,
        "Deployment graph was not provided!"
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
      task_deployment.deploy(
        deployment_info: deployment_info,
        tasks_graph: tasks_graph,
        tasks_directory: tasks_directory)
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
      task_deployment.deploy(
        deployment_info: deployment_info,
        tasks_graph: tasks_graph,
        tasks_directory: tasks_directory)
    end

    it 'should setup stop condition' do
      Astute::TaskPreDeploymentActions.any_instance.stubs(:process)
      task_deployment.stubs(:write_graph_to_file)
      ctx.stubs(:report)
      task_deployment.stubs(:remove_failed_nodes).returns([deployment_info, []])
      Astute::TaskCluster.any_instance.stubs(:run).returns({:success => true})

      Astute::TaskCluster.any_instance.expects(:stop_condition)
      task_deployment.deploy(
        deployment_info: deployment_info,
        tasks_graph: tasks_graph,
        tasks_directory: tasks_directory)
    end

    it 'should setup deployment logger' do
      Astute::TaskPreDeploymentActions.any_instance.stubs(:process)
      task_deployment.stubs(:write_graph_to_file)
      ctx.stubs(:report)
      task_deployment.stubs(:remove_failed_nodes).returns([deployment_info, []])
      Astute::TaskCluster.any_instance.stubs(:run).returns({:success => true})

      Deployment::Log.expects(:logger=).with(Astute.logger)
      task_deployment.deploy(
        deployment_info: deployment_info,
        tasks_graph: tasks_graph,
        tasks_directory: tasks_directory)
    end

    context 'task concurrency' do
      let(:task_concurrency) { mock('task_concurrency') }

      before(:each) do
        Astute::TaskPreDeploymentActions.any_instance.stubs(:process)
        task_deployment.stubs(:write_graph_to_file)
        ctx.stubs(:report)
        task_deployment.stubs(:remove_failed_nodes).returns([deployment_info, []])
        Astute::TaskCluster.any_instance.stubs(:run).returns({:success => true})
        Deployment::Concurrency::Counter.any_instance
                                        .stubs(:maximum=).with(
                                          Astute.config.max_nodes_per_call)
      end

      it 'should setup 0 if no task concurrency setup' do
        Deployment::Concurrency::Counter.any_instance.expects(:maximum=).with(0).times(5)

        task_deployment.deploy(
          deployment_info: deployment_info,
          tasks_graph: tasks_graph,
          tasks_directory: tasks_directory)
      end

      it 'it should setup 1 if task concurrency type one_by_one' do
        tasks_graph['1'].first['parameters']['strategy'] =
          {'type' => 'one_by_one'}
        Deployment::Concurrency::Counter.any_instance.expects(:maximum=)
                                                     .with(0).times(4)
        Deployment::Concurrency::Counter.any_instance.expects(:maximum=)
                                                     .with(1)

        task_deployment.deploy(
          deployment_info: deployment_info,
          tasks_graph: tasks_graph,
          tasks_directory: tasks_directory)
      end

      it 'should setup task concurrency as amount if type is parallel' do
        tasks_graph['1'].first['parameters']['strategy'] =
          {'type' => 'parallel', 'amount' => 7}
        Deployment::Concurrency::Counter.any_instance.expects(:maximum=)
                                                     .with(0).times(4)
        Deployment::Concurrency::Counter.any_instance.expects(:maximum=)
                                                     .with(7)

        task_deployment.deploy(
          deployment_info: deployment_info,
          tasks_graph: tasks_graph,
          tasks_directory: tasks_directory)
      end

      it 'should setup 0 if task strategy is parallel and amount do not set' do
        tasks_graph['1'].first['parameters']['strategy'] = {'type' => 'parallel'}
        Deployment::Concurrency::Counter.any_instance.expects(:maximum=)
                                        .with(0).times(5)

        task_deployment.deploy(
          deployment_info: deployment_info,
          tasks_graph: tasks_graph,
          tasks_directory: tasks_directory)
      end

      it 'should raise error if amount is non-positive integer and type is parallel' do
        tasks_graph['1'].first['parameters']['strategy'] =
           {'type' => 'parallel', 'amount' => -4}
        Deployment::Concurrency::Counter.any_instance.expects(:maximum=)
                                        .with(0).times(2)

        expect {task_deployment.deploy(
          deployment_info: deployment_info,
          tasks_graph: tasks_graph,
          tasks_directory: tasks_directory)}.to raise_error(
        Astute::DeploymentEngineError, /expect only non-negative integer, but got -4./

      )
      end
    end

    context 'dry_run' do
      it 'should not run actual deployment if dry_run is set to True' do
        task_deployment.stubs(:remove_failed_nodes).returns([deployment_info, []])
        Astute::TaskPreDeploymentActions.any_instance.stubs(:process)
        task_deployment.stubs(:write_graph_to_file)
        ctx.stubs(:report)

        Astute::TaskCluster.any_instance.expects(:run).never

        task_deployment.deploy(
            deployment_info: deployment_info,
            tasks_graph: tasks_graph,
            tasks_directory: tasks_directory,
            dry_run: true)
      end
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

        task_deployment.deploy(
          deployment_info: deployment_info,
          tasks_graph: tasks_graph,
          tasks_directory: tasks_directory)
      end
    end

    context 'should report final status' do

      it 'succeed status' do
        Astute::TaskPreDeploymentActions.any_instance.stubs(:process)
        Astute::TaskCluster.any_instance.stubs(:run).returns({:success => true})
        task_deployment.stubs(:remove_failed_nodes).returns([deployment_info, []])
        task_deployment.stubs(:write_graph_to_file)
        ctx.expects(:report).with({'status' => 'ready', 'progress' => 100})

        task_deployment.deploy(
          deployment_info: deployment_info,
          tasks_graph: tasks_graph,
          tasks_directory: tasks_directory)
      end

      it 'failed status' do
        Astute::TaskPreDeploymentActions.any_instance.stubs(:process)

        failed_node = mock('node')
        failed_node.expects(:id).returns('1')

        failed_task = mock('task')
        failed_task.expects(:node).returns(failed_node)
        failed_task.expects(:name).returns('test')
        failed_task.expects(:status).returns(:failed)

        Astute::TaskCluster.any_instance.stubs(:run).returns({
          :success => false,
          :failed_nodes => [failed_node],
          :failed_tasks => [failed_task],
          :status => 'Failed because of'})
        task_deployment.stubs(:remove_failed_nodes).returns([deployment_info, []])
        task_deployment.stubs(:write_graph_to_file)
        ctx.expects(:report).with('nodes' => [{
          'uid' => '1',
          'status' => 'error',
          'error_type' => 'deploy',
          'error_msg' => 'Failed because of',
          'deployment_graph_task_name' => 'test',
          'task_status' => 'failed'
        }])
        ctx.expects(:report).with({
          'status' => 'error',
          'progress' => 100,
          'error' => 'Failed because of'})

        task_deployment.deploy(
          deployment_info: deployment_info,
          tasks_graph: tasks_graph,
          tasks_directory: tasks_directory)
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
        File.expects(:open).with("#{Astute.config.graph_dot_dir}/graph-#{ctx.task_id}.dot", 'w')
            .yields(file_handle).never

        task_deployment.deploy(
          deployment_info: deployment_info,
          tasks_graph: tasks_graph,
          tasks_directory: tasks_directory)
      end

      it 'should write graph if enable' do
        Astute.config.enable_graph_file = true

        task_deployment.stubs(:remove_failed_nodes).returns([deployment_info, []])
        Astute::TaskPreDeploymentActions.any_instance.stubs(:process)
        ctx.stubs(:report)
        Astute::TaskCluster.any_instance.stubs(:run).returns({:success => true})

        file_handle = mock
        file_handle.expects(:write).with(regexp_matches(/digraph/)).once
        File.expects(:open).with("#{Astute.config.graph_dot_dir}/graph-#{ctx.task_id}.dot", 'w')
            .yields(file_handle).once

        task_deployment.deploy(
          deployment_info: deployment_info,
          tasks_graph: tasks_graph,
          tasks_directory: tasks_directory)
      end
    end # 'graph file'

  end

end
