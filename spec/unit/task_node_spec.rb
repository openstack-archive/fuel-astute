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

describe Astute::TaskNode do
  include SpecHelpers

  let(:cluster) do
    Deployment::Cluster.new
  end

  let(:ctx) do
    ctx = mock('context')
    ctx.stubs(:task_id)
    ctx.stubs(:report)
    ctx
  end

  let(:task_node) do
    node = Astute::TaskNode.new('node_id', cluster)
    node.context = ctx
    node
  end

  let(:task) do
    task_node.graph.create_task(
      task_data['id'],
      task_data.merge({'node_id' => 'node_id'})
    )
  end

  context '#run' do

    let(:task_data) do
      {
        "parameters" => {
          "puppet_modules" => "/etc/puppet/modules",
          "puppet_manifest" => "/etc/puppet/modules/osnailyfacter/modular" \
            "/openstack-haproxy/openstack-haproxy-mysqld.pp",
          "timeout" => 300,
          "cwd" => "/"
        },
        "type" => "puppet",
        "fail_on_error" => true,
        "required_for" => [],
        "requires" => [],
        "id" => "openstack-haproxy-mysqld",
      }
    end

    it 'should run task' do
      Astute::Puppet.any_instance.expects(:run)
      task_node.run(task)
    end

    it 'should run noop puppet task' do
      task_node.stubs(:noop_run?).returns(true)
      Astute::NoopPuppet.any_instance.expects(:run)
      task_node.run(task)
    end

    it 'should mark node as busy' do
      Astute::Puppet.any_instance.stubs(:run)
      task_node.run(task)
      expect(task_node.status).to eql(:busy)
    end

    it 'should mark task as running' do
      Astute::Puppet.any_instance.stubs(:run)
      task_node.run(task)
      expect(task.status).to eql(:running)
    end

    it 'should report about task as running' do
      Astute::Puppet.any_instance.stubs(:run)
      ctx.expects(:report).with('nodes' => [{
        'uid' => 'node_id',
        'status' => 'deploying',
        'progress' => 0,
        'deployment_graph_task_name' => 'openstack-haproxy-mysqld',
        'task_status' => 'running',
        'custom' => {}
      }])
      task_node.run(task)
    end

    context 'should not report about task as running' do
      let(:task_data_wo_type) do
        {
          "type" => "noop",
          "fail_on_error" => true,
          "required_for" => [],
          "requires" => [],
          "id" => "openstack-haproxy"
        }
      end

      shared_examples 'disable running report' do
        it 'task should not report running status' do
          ctx.unstub(:report)
          ctx.expects(:report).never
          task_node.run(task)
        end
      end

      context 'noop' do
        let(:task_data) { task_data_wo_type.merge!('type'=> 'noop') }
        it_behaves_like 'disable running report'
      end

      context 'stage' do
        let(:task_data) { task_data_wo_type.merge!('type'=> 'stage') }
        it_behaves_like 'disable running report'
      end

      context 'skipped' do
        let(:task_data) { task_data_wo_type.merge!('type'=> 'skipped') }
        it_behaves_like 'disable running report'
      end
    end

    context 'support different task type' do

      let(:task_data) do
        {
          "parameters" => {},
          "type" => "noop",
          "fail_on_error" => false,
          "required_for" => [],
          "requires" => [],
          "id" => "test-task",
        }
      end

      it 'shell' do
        task_data['type'] = "shell"
        Astute::Shell.any_instance.expects(:run)
        task_node.run(task)
      end

      it 'puppet' do
        task_data['type'] = "puppet"
        Astute::Puppet.any_instance.expects(:run)
        task_node.run(task)
      end

      it 'sync' do
        task_data['type'] = "sync"
        Astute::Sync.any_instance.expects(:run)
        task_node.run(task)
      end

      it 'cobbler_sync' do
        task_data['type'] = "cobbler_sync"
        Astute::CobblerSync.any_instance.expects(:run)
        task_node.run(task)
      end

      it 'noop' do
        task_data['type'] = "noop"
        Astute::Noop.any_instance.expects(:run)
        task_node.run(task)
      end

      it 'skipped' do
        task_data['type'] = "skipped"
        Astute::Noop.any_instance.expects(:run)
        task_node.run(task)
      end

      it 'stage' do
        task_data['type'] = "stage"
        Astute::Noop.any_instance.expects(:run)
        task_node.run(task)
      end

      it 'reboot' do
        task_data['type'] = "reboot"
        Astute::Reboot.any_instance.expects(:run)
        task_node.run(task)
      end

      it 'upload_file' do
        task_data['type'] = "upload_file"
        Astute::UploadFile.any_instance.expects(:run)
        task_node.run(task)
      end

      it 'upload_files' do
        task_data['type'] = "upload_files"
        task_data['parameters']['nodes'] = []
        Astute::UploadFiles.any_instance.expects(:run)
        task_node.run(task)
      end

      it 'copy_files' do
        task_data['type'] = "copy_files"
        task_data['parameters']['files'] = []
        Astute::CopyFiles.any_instance.expects(:run)
        task_node.run(task)
      end

      it 'unkown type' do
        task_data['type'] = "unknown"
        expect{task_node.run(task)}.to raise_error(
          Astute::TaskValidationError,
          "Unknown task type 'unknown'")
      end
    end # support task type
  end


  context '#poll' do

    context 'not busy' do
      it 'should not raise any error' do
        expect{task_node.poll}.not_to raise_error
      end

      it 'should not change node status' do
        old_status = task_node.status
        task_node.poll
        expect(task_node.status).to eql(old_status)
      end
    end

    context 'busy' do
      let(:task_data) do
        {
          "parameters" => {},
          "type" => "puppet",
          "fail_on_error" => false,
          "required_for" => [],
          "requires" => [],
          "id" => "test-task",
        }
      end

      before(:each) do
        Astute::Puppet.any_instance.stubs(:run)
      end

      context 'mark failed' do
        it 'if task failed' do
          Astute::Puppet.any_instance.stubs(:status).returns(:failed)
          ctx.stubs(:report)
          task_node.run(task)
          task_node.poll
          expect(task_node.status).to eql(:failed)
        end
      end

      context 'mark online' do
        it 'if task successful' do
          Astute::Puppet.any_instance.stubs(:status).returns(:successful)
          ctx.stubs(:report)
          task_node.run(task)
          task_node.poll
          expect(task_node.status).to eql(:online)
        end

        context "skipped" do
          let(:task_data) do
            {
              "parameters" => {},
              "type" => "noop",
              "fail_on_error" => false,
              "required_for" => [],
              "requires" => [],
              "id" => "test-task",
            }
          end

          it 'if task skipped' do
            ctx.stubs(:report)
            task_node.run(task)
            task_node.poll
            expect(task_node.status).to eql(:online)
          end
        end
      end

      it 'should report progress if task running' do
        Astute::Puppet.any_instance.expects(:status).returns(:running)
        task_node.run(task)
        ctx.expects(:report).with({
          'nodes' => [{
            'uid' => 'node_id',
            'status' => 'deploying',
            'deployment_graph_task_name' => task.name,
            'task_status' => 'running',
            'progress' => 0}]
        })
        task_node.poll
      end

      it 'should report ready if task successful and no more task' do
        Astute::Puppet.any_instance.expects(:status).returns(:successful)
        task_node.run(task)
        ctx.expects(:report).with({
          'nodes' => [{
            'uid' => 'node_id',
            'status' => 'ready',
            'deployment_graph_task_name' => task.name,
            'custom' => {},
            'task_status' => 'successful',
            'progress' => 100}]
        })
        task_node.poll
      end

      context 'skipped' do
        let(:task_data) do
          {
            "parameters" => {},
            "type" => "noop",
            "fail_on_error" => false,
            "required_for" => [],
            "requires" => [],
            "id" => "test-task",
          }
        end

        it 'should report ready if task skipped and no more task' do
          task_node.run(task)
          ctx.expects(:report).with({
            'nodes' => [{
              'uid' => 'node_id',
              'status' => 'ready',
              'deployment_graph_task_name' => task.name,
              'custom' => {},
              'task_status' => 'skipped',
              'progress' => 100}]
          })
          task_node.poll
        end

        it 'should report deploy progress if task skipped and another tasks exists' do
          task_node.graph.create_task(
            'second_task',
            task_data.merge({'node_id' => 'node_id'})
          )

          task_node.run(task)
          ctx.expects(:report).with({
            'nodes' => [{
              'uid' => 'node_id',
              'status' => 'deploying',
              'deployment_graph_task_name' => task.name,
              'custom' => {},
              'task_status' => 'skipped',
              'progress' => 50}]
          })
          task_node.poll
        end
      end

      it 'should report error if task failed and no more task' do
        Astute::Puppet.any_instance.expects(:status).returns(:failed)
        task_node.run(task)
        ctx.expects(:report).with({
          'nodes' => [{
            'uid' => 'node_id',
            'status' => 'error',
            'deployment_graph_task_name' => task.name,
            'custom' => {},
            'task_status' => 'failed',
            'error_type' => 'deploy',
            'progress' => 100}]
        })
        task_node.poll
      end

      it 'should report deploy progress if task successful and another tasks exists' do
        Astute::Puppet.any_instance.expects(:status).returns(:successful)
        task_node.graph.create_task(
          'second_task',
          task_data.merge({'node_id' => 'node_id'})
        )

        task_node.run(task)
        ctx.expects(:report).with({
          'nodes' => [{
            'uid' => 'node_id',
            'status' => 'deploying',
            'deployment_graph_task_name' => task.name,
            'custom' => {},
            'task_status' => 'successful',
            'progress' => 50}]
        })
        task_node.poll
      end

      it 'should not report deploy progress if task failed and another tasks exists' do
        Astute::Puppet.any_instance.expects(:status).returns(:failed)
        task_node.graph.create_task(
          'second_task',
          task_data.merge({'node_id' => 'node_id'})
        )

        task_node.run(task)
        ctx.expects(:report).never
        task_node.poll
      end
    end

  end


end
