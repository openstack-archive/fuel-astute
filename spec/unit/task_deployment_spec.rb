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

  let(:tasks_metadata) do
      {
        'fault_tolerance_groups' =>[
          {"fault_tolerance"=>0, "name"=>"primary-controller", "node_ids"=>["1"]},
          {"fault_tolerance"=>1, "name"=>"controller", "node_ids"=>[]},
          {"fault_tolerance"=>0, "name"=>"cinder", "node_ids"=>[]},
          {"fault_tolerance"=>0, "name"=>"cinder-block-device", "node_ids"=>[]},
          {"fault_tolerance"=>1, "name"=>"cinder-vmware", "node_ids"=>[]},
          {"fault_tolerance"=>0, "name"=>"compute", "node_ids"=>["3", "2"]},
          {"fault_tolerance"=>1, "name"=>"compute-vmware", "node_ids"=>[]},
          {"fault_tolerance"=>1, "name"=>"mongo", "node_ids"=>[]},
          {"fault_tolerance"=>1, "name"=>"primary-mongo", "node_ids"=>[]},
          {"fault_tolerance"=>1,
            "name"=>"ceph-osd",
            "node_ids"=>["3", "2", "5", "4"]},
          {"fault_tolerance"=>1, "name"=>"base-os", "node_ids"=>[]},
          {"fault_tolerance"=>1, "name"=>"virt", "node_ids"=>[]},
          {"fault_tolerance"=>1, "name"=>"ironic", "node_ids"=>[]}
        ]
      }
  end

  let(:tasks_graph) do
    {"1"=>
      [{
        "type"=>"noop",
        "fail_on_error"=>true,
        "required_for"=>[],
        "requires"=> [],
        "id"=>"ironic_post_swift_key",
        "parameters"=>{},
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

  let(:tasks_graph_2) do
    {"master"=>
         [{
              "type"=>"noop",
              "fail_on_error"=>true,
              "required_for"=>[],
              "requires"=> [],
              "id"=>"ironic_post_swift_key",
              "parameters"=>{},
          }],
     "null"=> []
    }
  end

  let(:tasks_graph_3) do
    {
        "null" =>
            [
                {"id" => "sync_task",
                 "requires" =>[]
                }
            ],
        "1" =>
            [
                {"id" => "14", "requires" => [{"node_id" => nil, "name" => "sync_task"}], "required_for" => [{"name" => 15, "node_id" => "1"}]},
                {"id" => "15", "requires" => [{"node_id" => "2", "name" => "6"}]},
                {"id" => "0", "required_for" => [{"name" => 1, "node_id" => "1"}]},
                {"id" => "1", "required_for" => [{"name" => 2, "node_id" => "1"}, {"name" => 3, "node_id" => "1"}]},
                {"id" => "2", "required_for" => [{"name" => 4, "node_id" => "1"}, {"name" => 5, "node_id" => "1"}]},
                {"id" => "3", "required_for" => [{"name" => 6, "node_id" => "1"}, {"name" => 7, "node_id" => "1"}]},
                {"id" => "4", "required_for" => [{"name" => 8, "node_id" => "1"}]},
                {"id" => "5", "required_for" => [{"name" => 10, "node_id" => "1"}]},
                {"id" => "6", "required_for" => [{"name" => 11, "node_id" => "1"}]},
                {"id" => "7", "required_for" => [{"name" => 12, "node_id" => "1"}]},
                {"id" => "8", "required_for" => [{"name" => 9, "node_id" => "1"}]},
                {"id" => "9"},
                {"id" => "10", "required_for" => [{"name" => 9, "node_id" => "1"}]},
                {"id" => "11", "required_for" => [{"name" => 13, "node_id" => "1"}]},
                {"id" => "12", "required_for" => [{"name" => 13, "node_id" => "1"}]},
                {"id" => "13", "required_for" => [{"name" => 9, "node_id" => "1"}]}],
        "2" => [
            {"id" => "0", "required_for" => [{"name" => 1, "node_id" => "2"},
                                             {"name" => 3, "node_id" => "2"}]},
            {"id" => "1", "required_for" => [{"name" => 2, "node_id" => "2"}]},
            {"id" => "2"},
            {"id" => "3", "required_for" => [{"name" => 4, "node_id" => "2"}]},
            {"id" => "4", "requires" => [{"node_id" => 1, "name" => "3"}], "required_for" => [{"name" => 5, "node_id" => "2"}]},
            {"id" => "5", "requires" => [{"node_id" => 1, "name" => "13"}], "required_for" => [{"name" => 7, "node_id" => "2"}]},
            {"id" => "6", "requires" => [{"node_id" => nil, "name" => "sync_task"}], "required_for" => [{"name" => 8, "node_id" => "2"}]},
            {"id" => "7"},
            {"id" => "8"}
        ]
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
      task_deployment.stubs(:fail_offline_nodes).returns([])
      task_deployment.stubs(:write_graph_to_file)
      ctx.stubs(:report)

      Astute::TaskCluster.any_instance.expects(:run).returns({:success => true})
      task_deployment.deploy(
        tasks_metadata: tasks_metadata,
        tasks_graph: tasks_graph,
        tasks_directory: tasks_directory)
    end

    it 'should not raise error if deployment info not provided' do
      task_deployment.stubs(:fail_offline_nodes).returns([])
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

    it 'should support virtual node' do
      d_t = task_deployment.send(:support_virtual_node, tasks_graph)
      expect(d_t.keys).to include 'virtual_sync_node'
      expect(d_t.keys).not_to include 'null'
    end

    it 'should support critical nodes' do
      critical_nodes = task_deployment.send(
        :critical_node_uids,
        tasks_metadata['fault_tolerance_groups']
      )
      expect(critical_nodes).to include '1'
      expect(critical_nodes).to include '2'
      expect(critical_nodes).to include '3'
      expect(critical_nodes.size).to eql(3)
    end

    it 'should support default zero tolerance policy for error on nodes' do
      cluster = mock('cluster')
      cluster.stubs(:nodes).returns([
        ['1', mock('node_1')],
        ['2', mock('node_2')],
        ['3', mock('node_3')],
        ['virtual_sync_node', mock('null')]
      ])

      cluster.expects(:fault_tolerance_groups=).with(
        [
          {'fault_tolerance'=>0, 'name'=>'primary-controller', 'node_ids'=>['1']},
          {'fault_tolerance'=>1, 'name'=>'ceph', 'node_ids'=>['1', '3']},
          {'fault_tolerance'=>1, 'name'=>'ignored_group', 'node_ids'=>[]},
          {'fault_tolerance'=>0, 'name'=>'zero_tolerance_as_default_for_nodes', 'node_ids'=>['2']}
        ]
      )

      task_deployment.send(
        :setup_fault_tolerance_behavior,
        [
          {'fault_tolerance'=>0, 'name'=>'primary-controller', 'node_ids'=>['1']},
          {'fault_tolerance'=>1, 'name'=>'ceph', 'node_ids'=>['1', '3']},
          {'fault_tolerance'=>1, 'name'=>'ignored_group', 'node_ids'=>[]}
        ],
        cluster
      )
    end

    it 'should fail offline nodes' do
      Astute::TaskPreDeploymentActions.any_instance.stubs(:process)
      task_deployment.stubs(:write_graph_to_file)
      ctx.stubs(:report)

      task_deployment.expects(:fail_offline_nodes).returns([])

      Astute::TaskCluster.any_instance.stubs(:run).returns({:success => true})
      task_deployment.deploy(
        tasks_metadata: tasks_metadata,
        tasks_graph: tasks_graph,
        tasks_directory: tasks_directory)
    end

    it 'should not fail if there are no nodes to check for offline nodes' do
      Astute::TaskPreDeploymentActions.any_instance.stubs(:process)
      task_deployment.stubs(:write_graph_to_file)
      ctx.stubs(:report)

      task_deployment.expects(:fail_offline_nodes).returns([])

      Astute::TaskCluster.any_instance.stubs(:run).returns({:success => true})
      task_deployment.deploy(
          tasks_metadata: tasks_metadata,
          tasks_graph: tasks_graph_2,
          tasks_directory: tasks_directory)
    end

    it 'should setup stop condition' do
      Astute::TaskPreDeploymentActions.any_instance.stubs(:process)
      task_deployment.stubs(:write_graph_to_file)
      ctx.stubs(:report)
      task_deployment.stubs(:fail_offline_nodes).returns([])
      Astute::TaskCluster.any_instance.stubs(:run).returns({:success => true})

      Astute::TaskCluster.any_instance.expects(:stop_condition)
      task_deployment.deploy(
        tasks_metadata: tasks_metadata,
        tasks_graph: tasks_graph,
        tasks_directory: tasks_directory)
    end

    context 'task concurrency' do
      let(:task_concurrency) { mock('task_concurrency') }

      before(:each) do
        task_deployment.stubs(:write_graph_to_file)
        ctx.stubs(:report)
        task_deployment.stubs(:fail_offline_nodes).returns([])
        Astute::TaskCluster.any_instance.stubs(:run).returns({:success => true})
        Deployment::Concurrency::Counter.any_instance
                                        .stubs(:maximum=).with(
                                          Astute.config.max_nodes_per_call)
      end

      it 'should setup 0 if no task concurrency setup' do
        Deployment::Concurrency::Counter.any_instance.expects(:maximum=).with(0).times(5)

        task_deployment.deploy(
          tasks_metadata: tasks_metadata,
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
          tasks_metadata: tasks_metadata,
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
          tasks_metadata: tasks_metadata,
          tasks_graph: tasks_graph,
          tasks_directory: tasks_directory)
      end

      it 'should setup 0 if task strategy is parallel and amount do not set' do
        tasks_graph['1'].first['parameters']['strategy'] = {'type' => 'parallel'}
        Deployment::Concurrency::Counter.any_instance.expects(:maximum=)
                                        .with(0).times(5)

        task_deployment.deploy(
          tasks_metadata: tasks_metadata,
          tasks_graph: tasks_graph,
          tasks_directory: tasks_directory)
      end

      it 'should raise error if amount is non-positive integer and type is parallel' do
        tasks_graph['1'].first['parameters']['strategy'] =
           {'type' => 'parallel', 'amount' => -4}
        Deployment::Concurrency::Counter.any_instance.expects(:maximum=)
                                        .with(0).times(2)

        expect {task_deployment.deploy(
          tasks_metadata: tasks_metadata,
          tasks_graph: tasks_graph,
          tasks_directory: tasks_directory)}.to raise_error(
        Astute::DeploymentEngineError, /expect only non-negative integer, but got -4./

      )
      end
    end

    context 'dry_run' do
      it 'should not run actual deployment if dry_run is set to True' do
        task_deployment.stubs(:fail_offline_nodes).returns([])
        task_deployment.stubs(:write_graph_to_file)
        ctx.stubs(:report)

        Astute::TaskCluster.any_instance.expects(:run).never

        task_deployment.deploy(
            tasks_metadata: tasks_metadata,
            tasks_graph: tasks_graph,
            tasks_directory: tasks_directory,
            dry_run: true)
      end
    end

    context 'noop_run' do
      it 'should run noop deployment without error states' do
        task_deployment.stubs(:fail_offline_nodes).returns([])
        task_deployment.stubs(:write_graph_to_file)
        ctx.stubs(:report)

        Astute::TaskCluster.any_instance.expects(:run).returns({:success => true})
        task_deployment.deploy(
            tasks_metadata: tasks_metadata,
            tasks_graph: tasks_graph,
            tasks_directory: tasks_directory,
            noop_run: true)
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

        task_deployment.stubs(:fail_offline_nodes).returns([])
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
          tasks_metadata: tasks_metadata,
          tasks_graph: tasks_graph,
          tasks_directory: tasks_directory)
      end
    end

    context 'subgraphs' do
      it 'should call subgraph set up if subgraphs are present' do
        task_deployment.stubs(:fail_offline_nodes).returns([])
        task_deployment.stubs(:write_graph_to_file)
        Astute::TaskCluster.any_instance.expects(:run).returns({:success => true})


        ctx.stubs(:report)
        Astute::TaskCluster.any_instance.expects(:setup_start_end).once

      subgraphs = [
          {
              'start' => [
                  "3",
              ],
              'end' => [
                  "9"
              ]
          },
          {
              'start' => [ "4" ]
          }
      ]
      tasks_metadata.merge!("subgraphs" => subgraphs)
      task_deployment.deploy(
          tasks_metadata: tasks_metadata,
          tasks_graph: tasks_graph_3,
          tasks_directory: tasks_directory)
      end
      it 'should not call subgraph setup if subgraphs are not present' do
        task_deployment.stubs(:fail_offline_nodes).returns([])
        task_deployment.stubs(:write_graph_to_file)
        ctx.stubs(:report)
        Astute::TaskCluster.any_instance.expects(:run).returns({:success => true})
        Astute::TaskCluster.any_instance.expects(:setup_start_end).never

        subgraphs = [
            {
                'start' => [],
                'end' => nil
            },
            {'start'=>['task99']}
        ]
        tasks_metadata.merge!("subgraphs" => subgraphs)
        task_deployment.deploy(
            tasks_metadata: tasks_metadata,
            tasks_graph: tasks_graph,
            tasks_directory: tasks_directory)
      end
    end



    context 'should report final status' do

      it 'succeed status and 100 progress for all nodes' do
        Astute::TaskCluster.any_instance.stubs(:run).returns({:success => true})
        task_deployment.stubs(:fail_offline_nodes).returns([])
        task_deployment.stubs(:write_graph_to_file)
        ctx.expects(:report).with('nodes' => [
          {'uid' => '1', 'progress' => 100},
          {'uid' => 'virtual_sync_node', 'progress' => 100}]
        )
        ctx.expects(:report).with({'status' => 'ready', 'progress' => 100})

        task_deployment.deploy(
          tasks_metadata: tasks_metadata,
          tasks_graph: tasks_graph,
          tasks_directory: tasks_directory)
      end

      it 'failed status and 100 progress for all nodes' do
        failed_node = mock('node')
        failed_task = mock('task')

        Astute::TaskCluster.any_instance.stubs(:run).returns({
          :success => false,
          :failed_nodes => [failed_node],
          :failed_tasks => [failed_task],
          :status => 'Failed because of'})
        task_deployment.stubs(:fail_offline_nodes).returns([])
        task_deployment.stubs(:write_graph_to_file)
        ctx.expects(:report).with('nodes' => [
          {'uid' => '1', 'progress' => 100},
          {'uid' => 'virtual_sync_node', 'progress' => 100}]
        )
        ctx.expects(:report).with({
          'status' => 'error',
          'progress' => 100,
          'error' => 'Failed because of'})

        task_deployment.deploy(
          tasks_metadata: tasks_metadata,
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

        task_deployment.stubs(:fail_offline_nodes).returns([])
        ctx.stubs(:report)
        Astute::TaskCluster.any_instance.stubs(:run).returns({:success => true})

        file_handle = mock
        file_handle.expects(:write).with(regexp_matches(/digraph/)).never
        File.expects(:open).with("#{Astute.config.graph_dot_dir}/graph-#{ctx.task_id}.dot", 'w')
            .yields(file_handle).never

        task_deployment.deploy(
          tasks_metadata: tasks_metadata,
          tasks_graph: tasks_graph,
          tasks_directory: tasks_directory)
      end

      it 'should write graph if enable' do
        Astute.config.enable_graph_file = true

        task_deployment.stubs(:fail_offline_nodes).returns([])
        ctx.stubs(:report)
        Astute::TaskCluster.any_instance.stubs(:run).returns({:success => true})

        file_handle = mock
        file_handle.expects(:write).with(regexp_matches(/digraph/)).once
        File.expects(:open).with("#{Astute.config.graph_dot_dir}/graph-#{ctx.task_id}.dot", 'w')
            .yields(file_handle).once

        task_deployment.deploy(
          tasks_metadata: tasks_metadata,
          tasks_graph: tasks_graph,
          tasks_directory: tasks_directory)
      end
    end # 'graph file'

  end

end
