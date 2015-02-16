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

include Astute

describe Astute::NailgunHooks do
  include SpecHelpers

  let(:ctx) { mock_ctx }

  around(:each) do |example|
    old_value = Astute.config.MAX_NODES_PER_CALL
    example.run
    Astute.config.MAX_NODES_PER_CALL = old_value
  end

  let(:upload_file_hook) do
    {
      "priority" =>  100,
      "type" =>  "upload_file",
      "fail_on_error" => false,
      "diagnostic_name" => "upload-example-1.0",
      "uids" =>  ['2', '3'],
      "parameters" =>  {
        "path" =>  "/etc/yum.repos.d/fuel_awesome_plugin-0.1.0.repo",
        "data" =>  "[fuel_awesome_plugin-0.1.0]\\nname=Plugin fuel_awesome_plugin-0.1.0 repository\\nbaseurl=http => //10.20.0.2 => 8080/plugins/fuel_awesome_plugin-0.1.0/repositories/centos\\ngpgcheck=0"
      }
    }
  end

  let(:sync_hook) do
    {
      "priority" =>  200,
      "type" =>  "sync",
      "fail_on_error" => false,
      "diagnostic_name" => "sync-example-1.0",
      "uids" =>  ['1', '2'],
      "parameters" =>  {
        "src" =>  "rsync://10.20.0.2/plugins/fuel_awesome_plugin-0.1.0/deployment_scripts/",
        "dst" =>  "/etc/fuel/plugins/fuel_awesome_plugin-0.1.0/"
      }
    }
  end

  let(:shell_hook) do
    {
      "priority" =>  100,
      "type" =>  "shell",
      "fail_on_error" => false,
      "id" => "shell-example-1.0",
      "uids" =>  ['1','2','3'],
      "parameters" =>  {
        "cmd" =>  "./deploy.sh",
        "cwd" =>  "/etc/fuel/plugins/fuel_awesome_plugin-0.1.0/",
        "timeout" =>  60
      }
    }
  end

  let(:puppet_hook) do
    {
      "priority" =>  300,
      "type" =>  "puppet",
      "fail_on_error" => false,
      "diagnostic_name" => "puppet-example-1.0",
      "uids" =>  ['1', '3'],
      "parameters" =>  {
        "puppet_manifest" =>  "cinder_glusterfs.pp",
        "puppet_modules" =>  "modules",
        "cwd" => "/etc/fuel/plugins/plugin_name-1.0",
        "timeout" =>  42
      }
    }
  end

  let(:reboot_hook) do
    {
      "priority" =>  600,
      "type" =>  "reboot",
      "fail_on_error" => false,
      "diagnostic_name" => "reboot-example-1.0",
      "uids" =>  ['2', '3'],
      "parameters" =>  {
        "timeout" =>  42
      }
    }
  end

  let(:copy_files_hook) do
    {
      "priority" =>  100,
      "type" =>  "copy_files",
      "fail_on_error" => false,
      "diagnostic_name" => "copy-example-1.0",
      "uids" =>  ['2', '3'],
      "parameters" =>  {
        "files" => [{
          "src" => "/etc/fuel/nova.key",
          "dst" => "/etc/astute/nova.key"}],
        "permissions" => "0600",
        "dir_permissions" => "0700"
      }
    }
  end

  let(:hooks_data) do
    [
      upload_file_hook,
      sync_hook,
      shell_hook,
      puppet_hook,
      copy_files_hook,
      reboot_hook
    ]
  end

  context '#new' do
    it 'should use default run type if no type setting' do
      hooks = Astute::NailgunHooks.new(hooks_data, ctx)
      expect(hooks.instance_variable_get("@type")).to eql('deploy')
    end

    it 'should use type if it set' do
      hooks = Astute::NailgunHooks.new(hooks_data, ctx, 'execute_tasks')
      expect(hooks.instance_variable_get("@type")).to eql('execute_tasks')
    end
  end

  context "#process" do
    it 'should process known hook type' do
      hooks = Astute::NailgunHooks.new(hooks_data, ctx)

      hooks.expects(:upload_file_hook)
      hooks.expects(:puppet_hook)
      hooks.expects(:shell_hook)
      hooks.expects(:sync_hook)
      hooks.expects(:reboot_hook)
      hooks.expects(:copy_files_hook)

      hooks.process
    end

    it 'should raise exception if hook type is unknown' do
      wrong_hook = [{
        "priority" =>  300,
        "type" =>  "unknown",
        "uids" =>  ['1', '3'],
        "parameters" =>  {
          "parameter" => "1"
        }
        }]
      hooks = Astute::NailgunHooks.new(wrong_hook, ctx)

      expect {hooks.process}.to raise_error(StandardError, /Unknown hook type/)
    end

    it 'should run hooks by priority order' do
      File.stubs(:file?).returns(true)
      File.stubs(:readable?).returns(true)
      File.stubs(:read).returns('')
      hooks = Astute::NailgunHooks.new(hooks_data, ctx)

      hook_order = sequence('hook_order')
      hooks.expects(:upload_file_hook).in_sequence(hook_order)
      hooks.expects(:copy_files_hook).in_sequence(hook_order)
      hooks.expects(:shell_hook).in_sequence(hook_order)
      hooks.expects(:sync_hook).in_sequence(hook_order)
      hooks.expects(:puppet_hook).in_sequence(hook_order)
      hooks.expects(:reboot_hook).in_sequence(hook_order)

      hooks.process
    end

    context 'critical hook' do

      before(:each) do
        hooks_data[2]['fail_on_error'] = true
        ctx.stubs(:report_and_update_status)
      end

      it 'should raise exception if critical hook failed' do
        hooks = Astute::NailgunHooks.new(hooks_data, ctx)
        hooks.expects(:copy_files_hook).returns(true)
        hooks.expects(:upload_file_hook).returns(true)
        hooks.expects(:shell_hook).returns(false)

        expect {hooks.process}.to raise_error(Astute::DeploymentEngineError, /Failed to deploy plugin shell-example-1.0/)
      end

      it 'should not process next hooks if critical hook failed' do
        hooks = Astute::NailgunHooks.new(hooks_data, ctx)
        hooks.expects(:upload_file_hook).returns(true)
        hooks.expects(:shell_hook).returns(false)
        hooks.expects(:sync_hook).never
        hooks.expects(:puppet_hook).never
        hooks.expects(:reboot_hook).never

        hooks.process rescue nil
      end

      it 'should process next hooks if non critical hook failed' do
        hooks = Astute::NailgunHooks.new(hooks_data, ctx)
        hooks.expects(:upload_file_hook).returns(false)
        hooks.expects(:shell_hook).returns(true)
        hooks.expects(:sync_hook).returns(false)
        hooks.expects(:puppet_hook).returns(true)
        hooks.expects(:reboot_hook).returns(true)

        hooks.process
      end

      it 'should report error node status if critical hook failed' do
        hooks = Astute::NailgunHooks.new(hooks_data, ctx)
        hooks.expects(:upload_file_hook).returns(true)
        hooks.expects(:shell_hook).returns(false)

        ctx.expects(:report_and_update_status).with(
          {'nodes' =>
            [
              { 'uid' => '1',
                'status' => 'error',
                'error_type' => 'deploy',
                'role' => 'hook',
                'hook' => "shell-example-1.0"
              },
              { 'uid' => '2',
                'status' => 'error',
                'error_type' => 'deploy',
                'role' => 'hook',
                'hook' => "shell-example-1.0"
              },
              { 'uid' => '3',
                'status' => 'error',
                'error_type' => 'deploy',
                'role' => 'hook',
                'hook' => "shell-example-1.0"
              },
            ]
          }
        )

        hooks.process rescue nil
      end

      it 'should not send report if non critical hook failed' do
        hooks = Astute::NailgunHooks.new(hooks_data, ctx)
        hooks.expects(:upload_file_hook).returns(false)
        hooks.expects(:shell_hook).returns(true)
        hooks.expects(:sync_hook).returns(false)
        hooks.expects(:puppet_hook).returns(true)
        hooks.expects(:reboot_hook).returns(true)

        ctx.expects(:report_and_update_status).never

        hooks.process
      end

    end #hook

  end #process

  context '#copy_files_hook' do

    it 'should validate presence of node uids' do
      copy_files_hook['uids'] = []
      hooks = Astute::NailgunHooks.new([copy_files_hook], ctx)

      expect {hooks.process}.to raise_error(StandardError, /Missing a required parameter/)
    end

    it 'should validate presence files' do
      copy_files_hook['parameters'].delete('files')
      hooks = Astute::NailgunHooks.new([copy_files_hook], ctx)

      expect {hooks.process}.to raise_error(StandardError, /Missing a required parameter/)
    end

    it 'should upload file' do
      File.stubs(:file?).returns(true)
      File.stubs(:readable?).returns(true)
      File.stubs(:read).returns("")
      hooks = Astute::NailgunHooks.new([copy_files_hook], ctx)

      hooks.expects(:upload_file).once.with(
        ctx,
        ['2', '3'],
        has_entries(
          'content' => "",
          'path' => copy_files_hook['parameters']['files'][0]['dst']
        )
      )

      hooks.process
    end

    it 'should limit nodes processing in parallel' do
      Astute.config.MAX_NODES_PER_CALL = 1
      File.stubs(:file?).returns(true)
      File.stubs(:readable?).returns(true)
      File.stubs(:read).returns("")
      hooks = Astute::NailgunHooks.new([copy_files_hook], ctx)

      hooks.expects(:upload_file).once.with(
        ctx,
        ['2'],
        has_entries(
          'content' => "",
          'path' => copy_files_hook['parameters']['files'][0]['dst']
        )
      )
      hooks.expects(:upload_file).once.with(
        ctx,
        ['3'],
        has_entries(
          'content' => "",
          'path' => copy_files_hook['parameters']['files'][0]['dst']
        )
      )
      hooks.process
    end

    context 'process data from mcagent in case of critical hook' do
      before(:each) do
        copy_files_hook['fail_on_error'] = true
        ctx.stubs(:report_and_update_status)
      end

      it 'mcagent success' do
        File.stubs(:file?).returns(true)
        File.stubs(:readable?).returns(true)
        File.stubs(:read).returns("")
        hooks = Astute::NailgunHooks.new([copy_files_hook], ctx)
        hooks.expects(:upload_file).returns(true).once

        expect {hooks.process}.to_not raise_error
      end

      it 'mcagent fail' do
        File.stubs(:file?).returns(true)
        File.stubs(:readable?).returns(true)
        File.stubs(:read).returns("")
        hooks = Astute::NailgunHooks.new([copy_files_hook], ctx)
        hooks.expects(:upload_file).returns(false).once

        expect {hooks.process}.to raise_error(Astute::DeploymentEngineError, /Failed to deploy plugin/)
      end
    end #context
  end#copy_files_hook

  context '#shell_hook' do

    it 'should validate presence of node uids' do
      shell_hook['uids'] = []
      hooks = Astute::NailgunHooks.new([shell_hook], ctx)

      expect {hooks.process}.to raise_error(StandardError, /Missing a required parameter/)
    end

    it 'should validate presence cmd hooks' do
      shell_hook['parameters'].delete('cmd')
      hooks = Astute::NailgunHooks.new([shell_hook], ctx)

      expect {hooks.process}.to raise_error(StandardError, /Missing a required parameter/)
    end

    it 'should run shell command with timeout' do
      hooks = Astute::NailgunHooks.new([shell_hook], ctx)
      hooks.expects(:run_shell_command).once.with(
        ctx,
        ['1','2','3'],
        regexp_matches(/deploy/),
        shell_hook['parameters']['timeout'],
        shell_hook['parameters']['cwd']
      )
      .returns(:data => {:exit_code => 0})

      hooks.process
    end

    it 'should use default timeout if it does not set' do
      shell_hook['parameters'].delete('timeout')
      hooks = Astute::NailgunHooks.new([shell_hook], ctx)
      hooks.expects(:run_shell_command).once.with(
        ctx,
        ['1','2','3'],
        regexp_matches(/deploy/),
        300,
        shell_hook['parameters']['cwd']
      )
      .returns(:data => {:exit_code => 0})

      hooks.process
    end

    it 'should limit nodes processing in parallel' do
      Astute.config.MAX_NODES_PER_CALL = 2

      hooks = Astute::NailgunHooks.new([shell_hook], ctx)
      hooks.expects(:run_shell_command).once.with(
        ctx,
        ['1', '2'],
        regexp_matches(/deploy/),
        shell_hook['parameters']['timeout'],
        shell_hook['parameters']['cwd']
      )
      .returns(:data => {:exit_code => 0})

      hooks.expects(:run_shell_command).once.with(
        ctx,
        ['3'],
        regexp_matches(/deploy/),
        shell_hook['parameters']['timeout'],
        shell_hook['parameters']['cwd']
      )
      .returns(:data => {:exit_code => 0})

      hooks.process
    end

    context 'process data from mcagent in case of critical hook' do
      before(:each) do
        shell_hook['fail_on_error'] = true
        ctx.stubs(:report_and_update_status)
      end

      it 'if exit code eql 0 -> do not raise error' do
        hooks = Astute::NailgunHooks.new([shell_hook], ctx)
        hooks.expects(:run_shell_command).returns({:data => {:exit_code => 0}}).once

        expect {hooks.process}.to_not raise_error
      end

      it 'if exit code not eql 0 -> raise error' do
        hooks = Astute::NailgunHooks.new([shell_hook], ctx)
        hooks.expects(:run_shell_command).returns({:data => {:exit_code => 1}}).times(Astute.config.MC_RETRIES)

        expect {hooks.process}.to raise_error(Astute::DeploymentEngineError, /Failed to deploy plugin/)
      end

      it 'if exit code not presence -> raise error' do
        hooks = Astute::NailgunHooks.new([shell_hook], ctx)
        hooks.expects(:run_shell_command).returns({:data => {}}).times(Astute.config.MC_RETRIES)

        expect {hooks.process}.to raise_error(Astute::DeploymentEngineError, /Failed to deploy plugin/)
      end
    end #context

  end #shell_hook

  context '#upload_file_hook' do
    it 'should validate presence of node uids' do
      upload_file_hook['uids'] = []
      hooks = Astute::NailgunHooks.new([upload_file_hook], ctx)

      expect {hooks.process}.to raise_error(StandardError, /Missing a required parameter/)
    end

    it 'should validate presence of file destination' do
      upload_file_hook['parameters'].delete('path')
      hooks = Astute::NailgunHooks.new([upload_file_hook], ctx)

      expect {hooks.process}.to raise_error(StandardError, /Missing a required parameter/)
    end

    it 'should validate presence of file source' do
      upload_file_hook['parameters'].delete('data')
      hooks = Astute::NailgunHooks.new([upload_file_hook], ctx)

      expect {hooks.process}.to raise_error(StandardError, /Missing a required parameter/)
    end

    it 'should upload file' do
      hooks = Astute::NailgunHooks.new([upload_file_hook], ctx)

      hooks.expects(:upload_file).once.with(
        ctx,
        ['2', '3'],
        has_entries(
          'content' => upload_file_hook['parameters']['data'],
          'path' => upload_file_hook['parameters']['path']
        )
      )

      hooks.process
    end

    it 'should limit nodes processing in parallel' do
      Astute.config.MAX_NODES_PER_CALL = 1
      hooks = Astute::NailgunHooks.new([upload_file_hook], ctx)

      hooks.expects(:upload_file).once.with(
        ctx,
        ['2'],
        has_entries(
          'content' => upload_file_hook['parameters']['data'],
          'path' => upload_file_hook['parameters']['path']
        )
      )

      hooks.expects(:upload_file).once.with(
        ctx,
        ['3'],
        has_entries(
          'content' => upload_file_hook['parameters']['data'],
          'path' => upload_file_hook['parameters']['path']
        )
      )

      hooks.process
    end

    context 'process data from mcagent in case of critical hook' do
      before(:each) do
        upload_file_hook['fail_on_error'] = true
        ctx.stubs(:report_and_update_status)
      end

      it 'mcagent success' do
        hooks = Astute::NailgunHooks.new([upload_file_hook], ctx)
        hooks.expects(:upload_file).returns(true).once

        expect {hooks.process}.to_not raise_error
      end

      it 'mcagent fail' do
        hooks = Astute::NailgunHooks.new([upload_file_hook], ctx)
        hooks.expects(:upload_file).returns(false).once

        expect {hooks.process}.to raise_error(Astute::DeploymentEngineError, /Failed to deploy plugin/)
      end
    end #context

  end #upload_file_hook

  context '#sync_hook' do
    it 'should validate presence of node uids' do
      sync_hook['uids'] = []
      hooks = Astute::NailgunHooks.new([sync_hook], ctx)

      expect {hooks.process}.to raise_error(StandardError, /Missing a required parameter/)
    end

    it 'should validate presence of destination' do
      sync_hook['parameters'].delete('dst')
      hooks = Astute::NailgunHooks.new([sync_hook], ctx)

      expect {hooks.process}.to raise_error(StandardError, /Missing a required parameter/)
    end

    it 'should validate presence of source' do
      sync_hook['parameters'].delete('src')
      hooks = Astute::NailgunHooks.new([sync_hook], ctx)

      expect {hooks.process}.to raise_error(StandardError, /Missing a required parameter/)
    end

    it 'should run sync command with timeout' do
      sync_hook['parameters']['timeout'] = '60'
      hooks = Astute::NailgunHooks.new([sync_hook], ctx)
      hooks.expects(:run_shell_command).once.with(
        ctx,
        ['1','2'],
        regexp_matches(/deploy/),
        sync_hook['parameters']['timeout']
      )
      .returns(:data => {:exit_code => 0})

      hooks.process
    end

    it 'should use default timeout if it does not set' do
      shell_hook['parameters'].delete('timeout')
      hooks = Astute::NailgunHooks.new([sync_hook], ctx)
      hooks.expects(:run_shell_command).once.with(
        ctx,
        ['1','2'],
        regexp_matches(/rsync/),
        300
      )
      .returns(:data => {:exit_code => 0})

      hooks.process
    end

    it 'should limit nodes processing in parallel' do
      Astute.config.MAX_NODES_PER_CALL = 1

      hooks = Astute::NailgunHooks.new([sync_hook], ctx)
      hooks.expects(:run_shell_command).once.with(
        ctx,
        ['1'],
        regexp_matches(/rsync/),
        is_a(Integer)
      )
      .returns(:data => {:exit_code => 0})

      hooks.expects(:run_shell_command).once.with(
        ctx,
        ['2'],
        regexp_matches(/rsync/),
        is_a(Integer)
      )
      .returns(:data => {:exit_code => 0})

      hooks.process
    end

    context 'process data from mcagent in case of critical hook' do
      before(:each) do
        sync_hook['fail_on_error'] = true
        ctx.stubs(:report_and_update_status)
      end

      it 'if exit code eql 0 -> do not raise error' do
        hooks = Astute::NailgunHooks.new([sync_hook], ctx)
        hooks.expects(:run_shell_command).returns({:data => {:exit_code => 0}}).once

        expect {hooks.process}.to_not raise_error
      end

      it 'if exit code not eql 0 -> raise error' do
        hooks = Astute::NailgunHooks.new([sync_hook], ctx)
        hooks.expects(:run_shell_command).returns({:data => {:exit_code => 1}}).times(10)

        expect {hooks.process}.to raise_error(Astute::DeploymentEngineError, /Failed to deploy plugin/)
      end

      it 'if exit code not presence -> raise error' do
        hooks = Astute::NailgunHooks.new([sync_hook], ctx)
        hooks.expects(:run_shell_command).returns({:data => {}}).times(10)

        expect {hooks.process}.to raise_error(Astute::DeploymentEngineError, /Failed to deploy plugin/)
      end
    end #context

  end #sync_hook

  context '#puppet_hook' do
    it 'should validate presence of node uids' do
      puppet_hook['uids'] = []
      hooks = Astute::NailgunHooks.new([puppet_hook], ctx)

      expect {hooks.process}.to raise_error(StandardError, /Missing a required parameter/)
    end

    it 'should validate presence of manifest parameter' do
      puppet_hook['parameters'].delete('puppet_manifest')
      hooks = Astute::NailgunHooks.new([puppet_hook], ctx)

      expect {hooks.process}.to raise_error(StandardError, /Missing a required parameter/)
    end

    it 'should validate presence of modules parameter' do
      puppet_hook['parameters'].delete('puppet_modules')
      hooks = Astute::NailgunHooks.new([puppet_hook], ctx)

      expect {hooks.process}.to raise_error(StandardError, /Missing a required parameter/)
    end

    it 'should validate presence of cwd parameter' do
      puppet_hook['parameters'].delete('cwd')
      hooks = Astute::NailgunHooks.new([puppet_hook], ctx)

      expect {hooks.process}.to raise_error(StandardError, /Missing a required parameter/)
    end

     it 'should run puppet command using main mechanism' do
      hooks = Astute::NailgunHooks.new([puppet_hook], ctx)
      PuppetdDeployer.expects(:deploy).once.with(
        instance_of(Astute::Context),
        [
          {'uid' => '1', 'role' => 'hook'},
          {'uid' => '3', 'role' => 'hook'}
        ],
        retries=2,
        puppet_hook['parameters']['puppet_manifest'],
        puppet_hook['parameters']['puppet_modules'],
        puppet_hook['parameters']['cwd']
      )

      Astute::Context.any_instance.stubs(:status).returns({'1' => 'success', '3' => 'success'})
      hooks.process
    end

    it 'should run puppet command with timeout' do
      hooks = Astute::NailgunHooks.new([puppet_hook], ctx)
      hooks.expects(:run_puppet).once.with(
        ctx,
        ['1','3'],
        puppet_hook['parameters']['puppet_manifest'],
        puppet_hook['parameters']['puppet_modules'],
        puppet_hook['parameters']['cwd'],
        puppet_hook['parameters']['timeout']
      ).returns(true)
      Astute::Context.any_instance.stubs(:status).returns({'1' => 'success', '3' => 'success'})

      hooks.process
    end

    it 'should use default timeout if it does not set' do
      puppet_hook['parameters'].delete('timeout')
      hooks = Astute::NailgunHooks.new([puppet_hook], ctx)
      hooks.expects(:run_puppet).once.with(
        ctx,
        ['1','3'],
        puppet_hook['parameters']['puppet_manifest'],
        puppet_hook['parameters']['puppet_modules'],
        puppet_hook['parameters']['cwd'],
        300
      ).returns(true)
      Astute::Context.any_instance.stubs(:status).returns({'1' => 'success', '3' => 'success'})

      hooks.process
    end

    it 'should limit nodes processing in parallel' do
      Astute.config.MAX_NODES_PER_CALL = 1

      hooks = Astute::NailgunHooks.new([puppet_hook], ctx)
      hooks.expects(:run_puppet).once.with(
        ctx,
        ['1'],
        puppet_hook['parameters']['puppet_manifest'],
        puppet_hook['parameters']['puppet_modules'],
        puppet_hook['parameters']['cwd'],
        puppet_hook['parameters']['timeout']
      ).returns(true)

      hooks.expects(:run_puppet).once.with(
        ctx,
        ['3'],
        puppet_hook['parameters']['puppet_manifest'],
        puppet_hook['parameters']['puppet_modules'],
        puppet_hook['parameters']['cwd'],
        puppet_hook['parameters']['timeout']
      ).returns(true)

      Astute::Context.any_instance.stubs(:status).returns({'1' => 'success', '3' => 'success'})
      hooks.process
    end

    it 'if mclient failed and task is not critical -> do not raise error' do
      hooks = Astute::NailgunHooks.new([puppet_hook], ctx)
      PuppetdDeployer.expects(:deploy).once.raises(Astute::MClientError)

      expect {hooks.process}.to_not raise_error
    end

    context 'process data from mcagent in case of critical hook' do
      before(:each) do
        puppet_hook['fail_on_error'] = true
        ctx.stubs(:report_and_update_status)
      end

      it 'if puppet success do not raise error' do
        hooks = Astute::NailgunHooks.new([puppet_hook], ctx)
        PuppetdDeployer.expects(:deploy).once
        Astute::Context.any_instance.stubs(:status).returns({'1' => 'success', '3' => 'success'})

        expect {hooks.process}.to_not raise_error
      end

      it 'if puppet fail -> raise error' do
        hooks = Astute::NailgunHooks.new([puppet_hook], ctx)
        PuppetdDeployer.expects(:deploy).once
        Astute::Context.any_instance.stubs(:status).returns({'1' => 'error', '3' => 'success'})

        expect {hooks.process}.to raise_error(Astute::DeploymentEngineError, /Failed to deploy plugin/)
      end

      it 'if mclient failed -> raise error' do
        hooks = Astute::NailgunHooks.new([puppet_hook], ctx)
        PuppetdDeployer.expects(:deploy).once.raises(Astute::MClientError)

        expect {hooks.process}.to raise_error(Astute::DeploymentEngineError, /Failed to deploy plugin/)
      end
    end #context
  end # puppet_hook

  context '#reboot_hook' do

    it 'should validate presence of node uids' do
      reboot_hook['uids'] = []
      hooks = Astute::NailgunHooks.new([reboot_hook], ctx)

      expect {hooks.process}.to raise_error(StandardError, /Missing a required parameter/)
    end

    it 'should run reboot command with timeout - 10 sec' do
      hooks = Astute::NailgunHooks.new([reboot_hook], ctx)

      time = Time.now.to_i
      hooks.stubs(:run_shell_without_check).twice.with(
        ctx,
        ['2','3'],
        regexp_matches(/stat/),
        10,
      )
      .returns('2' => (time - 5).to_s, '3' => (time - 5).to_s).then
      .returns('2' => time.to_s, '3' => time.to_s)

      hooks.expects(:run_shell_without_check).once.with(
        ctx,
        ['2','3'],
        "reboot",
        10,
      )
      .returns('2' => '', '3' => '')

      hooks.stubs(:sleep)

      hooks.process
    end

    it 'should run reboot validation command with timeout - 10 sec' do
      hooks = Astute::NailgunHooks.new([reboot_hook], ctx)

      time = Time.now.to_i
      hooks.stubs(:run_shell_without_check).twice.with(
        ctx,
        ['2','3'],
        regexp_matches(/stat/),
        10,
      )
      .returns('2' => (time - 5).to_s, '3' => (time - 5).to_s).then
      .returns('2' => time.to_s, '3' => time.to_s)

      hooks.stubs(:run_shell_without_check).once.with(
        ctx,
        ['2','3'],
        regexp_matches(/reboot/),
        10,
      )
      .returns('2' => '', '3' => '')

      hooks.stubs(:sleep)

      hooks.process
    end

    it 'should sleep between checks for one-tenth of timeout' do
      hooks = Astute::NailgunHooks.new([reboot_hook], ctx)

      time = Time.now.to_i
      hooks.stubs(:run_shell_without_check).twice.with(
        ctx,
        ['2','3'],
        regexp_matches(/stat/),
        10,
      )
      .returns('2' => (time - 5).to_s, '3' => (time - 5).to_s).then
      .returns('2' => time.to_s, '3' => time.to_s)

      hooks.stubs(:run_shell_without_check).once.with(
        ctx,
        ['2','3'],
        regexp_matches(/reboot/),
        10,
      )
      .returns('2' => '', '3' => '')

      hooks.expects(:sleep).with(reboot_hook['parameters']['timeout']/10)

      hooks.process
    end

    it 'should use default timeout if it does not set' do
      reboot_hook['parameters'].delete('timeout')
      hooks = Astute::NailgunHooks.new([reboot_hook], ctx)

      time = Time.now.to_i
      hooks.stubs(:run_shell_without_check).twice.with(
        ctx,
        ['2','3'],
        regexp_matches(/stat/),
        10,
      )
      .returns('2' => (time - 5).to_s, '3' => (time - 5).to_s).then
      .returns('2' => time.to_s, '3' => time.to_s)

      hooks.stubs(:run_shell_without_check).once.with(
        ctx,
        ['2','3'],
        regexp_matches(/reboot/),
        10,
      )
      .returns('2' => '', '3' => '')

      hooks.expects(:sleep).with(300/10)

      hooks.process
    end

    it 'should limit nodes processing in parallel' do
      Astute.config.MAX_NODES_PER_CALL = 1

      hooks = Astute::NailgunHooks.new([reboot_hook], ctx)

      time = Time.now.to_i
      hooks.stubs(:run_shell_without_check).once.with(
        ctx,
        ['2'],
        regexp_matches(/stat/),
        10,
      )
      .returns('2' => time.to_s)

      hooks.stubs(:run_shell_without_check).once.with(
        ctx,
        ['3'],
        regexp_matches(/stat/),
        10,
      )
      .returns('3' => time.to_s)

      hooks.expects(:run_shell_without_check).once.with(
        ctx,
        ['2'],
        regexp_matches(/reboot/),
        10,
      )
      .returns('2' => '')

      hooks.expects(:run_shell_without_check).once.with(
        ctx,
        ['3'],
        regexp_matches(/reboot/),
        10,
      )
      .returns('3' => '')

      hooks.stubs(:sleep)

      time = Time.now.to_i + 100
      hooks.stubs(:run_shell_without_check).once.with(
        ctx,
        ['2','3'],
        "stat --printf='%Y' /proc/1",
        10,
      )
      .returns('2' => time.to_s, '3' => time.to_s)

      hooks.process
    end

    context 'process data from mcagent in case of critical hook' do

      let(:hooks) do
        reboot_hook['fail_on_error'] = true
        reboot_hook['parameters']['timeout'] = 1

        hooks = Astute::NailgunHooks.new([reboot_hook], ctx)

        hooks.stubs(:run_shell_without_check).once.with(
          ctx,
          ['2','3'],
          regexp_matches(/reboot/),
          10,
        )
        .returns('2' => '', '3' => '')

        hooks.stubs(:sleep)

        hooks
      end

      before(:each) do
        ctx.stubs(:report_and_update_status)
      end

      it 'if reboot succeed -> do not raise error' do
        time = Time.now.to_i
        hooks.stubs(:run_shell_without_check).twice.with(
          ctx,
          ['2','3'],
          regexp_matches(/stat/),
          10,
        )
        .returns('2' => (time - 5).to_s, '3' => (time - 5).to_s).then
        .returns('2' => time.to_s, '3' => time.to_s)
        expect {hooks.process}.to_not raise_error
      end

      it 'if reboot failed -> raise error' do
        time = Time.now.to_i
        hooks.stubs(:run_shell_without_check).with(
          ctx,
          ['2','3'],
          regexp_matches(/stat/),
          10,
        )
        .returns('2' => time.to_s, '3' => (time - 5).to_s).then
        .returns('2' => (time - 5).to_s, '3' => time.to_s)

        hooks.stubs(:run_shell_without_check).with(
          ctx,
          ['2'],
          regexp_matches(/stat/),
          10,
        )
        .returns('2' => (time - 5).to_s, '3' => time.to_s)

        expect {hooks.process}.to raise_error(Astute::DeploymentEngineError, /Failed to deploy plugin/)
      end

      it 'if reboot validate info not presence -> raise error' do
        time = Time.now.to_i
        hooks.stubs(:run_shell_without_check).with(
          ctx,
          ['2','3'],
          regexp_matches(/stat/),
          10,
        )
        .returns('2' => time.to_s, '3' => (time - 5).to_s).then
        .returns('3' => time.to_s)

        hooks.stubs(:run_shell_without_check).with(
          ctx,
          ['2'],
          regexp_matches(/stat/),
          10,
        ).returns({})

        expect {hooks.process}.to raise_error(Astute::DeploymentEngineError, /Failed to deploy plugin/)
      end
    end #context

  end #reboot_hook

end # 'describe'
