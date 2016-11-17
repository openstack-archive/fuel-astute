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
    max_nodes_old_value = Astute.config.max_nodes_per_call
    mc_retries_old_value = Astute.config.mc_retries
    example.run
    Astute.config.max_nodes_per_call = max_nodes_old_value
    Astute.config.mc_retries = mc_retries_old_value
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
        "timeout" =>  42,
        "retries" => 21
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

  let(:upload_files_hook) do
    {
      "priority" =>  100,
      "type" =>  "upload_files",
      "fail_on_error" => false,
      "diagnostic_name" => "copy-example-1.0",
      "uids" =>  ['1'],
      "parameters" =>  {
        "nodes" =>[
          "uid" => '1',
          "files" => [{
            "dst" => "/etc/fuel/nova.key",
            "data" => "",
            "permissions" => "0600",
            "dir_permissions" => "0700"}],
        ]
      }
    }
  end

  let (:cobbler_sync_hook) do
    {
      "priority" => 800,
      "type" => "cobbler_sync",
      "fail_on_error" => false,
      "diagnostic_name" => "copy-example-1.0",
      "uids" => ['master'],
      "parameters" => {
        "provisioning_info" => {
          "engine" => {
            "url" => "http://10.20.0.2:80/cobbler_api",
            "username" => "cobbler",
            "password" => "cobblerpassword",
            "master_ip" => "10.20.0.2"
          }
        }
      }
    }
  end

  let (:cobbler_sync_nodes_hook) do
    {
      "priority" => 900,
      "type" => "cobbler_sync_nodes",
      "fail_on_error" => false,
      "diagnostic_name" => "copy-example-1.0",
      "uids" => ['master'],
      "parameters" => {
        "provisioning_info" => {
          "engine" => {
            "url" => "http://10.20.0.2:80/cobbler_api",
            "username" => "cobbler",
            "password" => "cobblerpassword",
            "master_ip" => "10.20.0.2"
          },
          "nodes"=>
            [{"profile"=>"ubuntu_1404_x86_64",
              "name_servers_search"=>"\"domain.tld\"",
              "uid"=>"2",
              "interfaces"=>
               {
                "eno1"=>
                 {"ip_address"=>"10.10.0.12",
                  "dns_name"=>"node-2.domain.tld",
                  "netmask"=>"255.255.0.0",
                  "static"=>"0",
                  "mac_address"=>"f8:cb:11:2a:92:90"},
                "eno2"=>{"static"=>"0", "mac_address"=>"f8:cb:11:2a:92:92"},
                "eno3"=>{"static"=>"0", "mac_address"=>"f8:cb:11:2a:92:b0"},
                "eno4"=>{"static"=>"0", "mac_address"=>"f8:cb:11:2a:92:b1"}},
              "interfaces_extra"=>
               {
                "eno1"=>{"onboot"=>"yes", "peerdns"=>"no"},
                "eno2"=>{"onboot"=>"no", "peerdns"=>"no"},
                "eno3"=>{"onboot"=>"no", "peerdns"=>"no"},
                "eno4"=>{"onboot"=>"no", "peerdns"=>"no"}},
            }]
        }
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
      upload_files_hook,
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

      hooks.expects(:upload_file_hook).returns({'error' => nil})
      hooks.expects(:puppet_hook).returns({'error' => nil})
      hooks.expects(:shell_hook).returns({'error' => nil})
      hooks.expects(:sync_hook).returns({'error' => nil})
      hooks.expects(:reboot_hook).returns({'error' => nil})
      hooks.expects(:copy_files_hook).returns({'error' => nil})
      hooks.expects(:upload_files_hook).returns({'error' => nil})

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
      hooks.expects(:upload_file_hook).returns({'error' => nil}).in_sequence(hook_order)
      hooks.expects(:copy_files_hook).returns({'error' => nil}).in_sequence(hook_order)
      hooks.expects(:upload_files_hook).returns({'error' => nil}).in_sequence(hook_order)
      hooks.expects(:shell_hook).returns({'error' => nil}).in_sequence(hook_order)
      hooks.expects(:sync_hook).returns({'error' => nil}).in_sequence(hook_order)
      hooks.expects(:puppet_hook).returns({'error' => nil}).in_sequence(hook_order)
      hooks.expects(:reboot_hook).returns({'error' => nil}).in_sequence(hook_order)

      hooks.process
    end

    context 'critical hook' do

      before(:each) do
        hooks_data[2]['fail_on_error'] = true
        ctx.stubs(:report_and_update_status)
      end

      it 'should raise exception if critical hook failed' do
        hooks = Astute::NailgunHooks.new(hooks_data, ctx)
        hooks.expects(:copy_files_hook).returns({'error' => nil})
        hooks.expects(:upload_file_hook).returns({'error' => nil})
        hooks.expects(:upload_files_hook).returns({'error' => nil})
        hooks.expects(:shell_hook).returns({'error' => 'Shell error'})

        expect {hooks.process}.to raise_error(Astute::DeploymentEngineError, /Failed to execute hook 'shell-example-1.0'/)
      end

      it 'should not process next hooks if critical hook failed' do
        hooks = Astute::NailgunHooks.new(hooks_data, ctx)
        hooks.expects(:upload_file_hook).returns({'error' => nil})
        hooks.expects(:upload_files_hook).returns({'error' => nil})
        hooks.expects(:shell_hook).returns({'error' => 'Shell error'})
        hooks.expects(:sync_hook).never
        hooks.expects(:puppet_hook).never
        hooks.expects(:reboot_hook).never

        hooks.process rescue nil
      end

      it 'should process next hooks if non critical hook failed' do
        hooks = Astute::NailgunHooks.new(hooks_data, ctx)
        hooks.expects(:upload_files_hook).returns({'error' => nil})
        hooks.expects(:upload_file_hook).returns({'error' => 'Upload error'})
        hooks.expects(:shell_hook).returns({'error' => nil})
        hooks.expects(:sync_hook).returns({'error' => 'Sync error'})
        hooks.expects(:puppet_hook).returns({'error' => nil})
        hooks.expects(:reboot_hook).returns({'error' => nil})

        hooks.process
      end

      it 'should report error node status if critical hook failed' do
        hooks = Astute::NailgunHooks.new(hooks_data, ctx)
        hooks.expects(:upload_files_hook).returns({'error' => nil})
        hooks.expects(:upload_file_hook).returns({'error' => nil})
        hooks.expects(:shell_hook).returns({'error' => 'Shell error'})
        error_msg = 'Shell error'

        ctx.expects(:report_and_update_status).with(
          {'nodes' =>
            [
              { 'uid' => '1',
                'status' => 'error',
                'error_type' => 'deploy',
                'role' => 'hook',
                'hook' => "shell-example-1.0",
                'error_msg' => error_msg
              },
              { 'uid' => '2',
                'status' => 'error',
                'error_type' => 'deploy',
                'role' => 'hook',
                'hook' => "shell-example-1.0",
                'error_msg' => error_msg
              },
              { 'uid' => '3',
                'status' => 'error',
                'error_type' => 'deploy',
                'role' => 'hook',
                'hook' => "shell-example-1.0",
                'error_msg' => error_msg
              },
            ],
            'error' => "Failed to execute hook 'shell-example-1.0' #{error_msg}"
          }
        )

        hooks.process rescue nil
      end

      it 'should not send report if non critical hook failed' do
        hooks = Astute::NailgunHooks.new(hooks_data, ctx)
        hooks.expects(:upload_files_hook).returns({'error' => nil})
        hooks.expects(:upload_file_hook).returns({'error' => 'Upload error'})
        hooks.expects(:shell_hook).returns({'error' => nil})
        hooks.expects(:sync_hook).returns({'error' => 'Sync error'})
        hooks.expects(:puppet_hook).returns({'error' => nil})
        hooks.expects(:reboot_hook).returns({'error' => nil})

        ctx.expects(:report_and_update_status).never

        hooks.process
      end

    end #hook

  end #process

  context '#upload_files_hook' do
    it 'should validate presence of nodes' do
      upload_files_hook['parameters']['nodes'] = []
      hooks = Astute::NailgunHooks.new([upload_files_hook], ctx)

      expect {hooks.process}.to raise_error(StandardError, /Missing a required parameter/)
    end


    it 'should uploads files' do
      hooks = Astute::NailgunHooks.new([upload_files_hook], ctx)

      hooks.expects(:upload_file).once.with(
        ctx,
        '1',
        has_entries(
          'content' => upload_files_hook['parameters']['nodes'][0]['files'][0]['data'],
          'path' => upload_files_hook['parameters']['nodes'][0]['files'][0]['dst']
        )
      )

      hooks.process
    end

    context 'process data from mcagent in case of critical hook' do
      before(:each) do
        upload_files_hook['fail_on_error'] = true
        ctx.stubs(:report_and_update_status)
      end

      it 'mcagent success' do
        hooks = Astute::NailgunHooks.new([upload_files_hook], ctx)
        hooks.expects(:upload_file).returns(true).once

        expect {hooks.process}.to_not raise_error
      end

      it 'mcagent fail' do
        hooks = Astute::NailgunHooks.new([upload_files_hook], ctx)
        hooks.expects(:upload_file).returns(false).once

        expect {hooks.process}.to raise_error(Astute::DeploymentEngineError, /Failed to execute hook/)
      end
    end #context

  end #upload_files_hook

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
      File.stubs(:binread).returns("")
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
      Astute.config.max_nodes_per_call = 1
      File.stubs(:file?).returns(true)
      File.stubs(:readable?).returns(true)
      File.stubs(:binread).returns("")
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
        #ctx.stubs(:report_and_update_status)
      end

      it 'mcagent success' do
        File.stubs(:file?).returns(true)
        File.stubs(:readable?).returns(true)
        File.stubs(:binread).returns("")
        hooks = Astute::NailgunHooks.new([copy_files_hook], ctx)
        hooks.expects(:upload_file).returns(true).once

        expect {hooks.process}.to_not raise_error
      end

      it 'mcagent fail' do
        File.stubs(:file?).returns(true)
        File.stubs(:readable?).returns(true)
        File.stubs(:binread).returns("")

        hooks = Astute::NailgunHooks.new([copy_files_hook], ctx)
        hooks.expects(:upload_file).returns(false).once
        error_msg = 'Upload not successful'
        ctx.expects(:report_and_update_status).once.with(
          {'nodes' =>
            [
              { 'uid' => '2',
                'status' => 'error',
                'error_type' => 'deploy',
                'role' => 'hook',
                'hook' => "copy-example-1.0",
                'error_msg' => error_msg
              },
              { 'uid' => '3',
                'status' => 'error',
                'error_type' => 'deploy',
                'role' => 'hook',
                'hook' => "copy-example-1.0",
                'error_msg' => error_msg
              },
            ],
            'error' => "Failed to execute hook 'copy-example-1.0' #{error_msg}"
          }
        )

        expect {hooks.process}.to raise_error(Astute::DeploymentEngineError, /Failed to execute hook/)

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
        Astute.config.mc_retries,
        Astute.config.mc_retry_interval,
        shell_hook['parameters']['timeout'],
        shell_hook['parameters']['cwd']
      )
      .returns(:data => {:exit_code => 0})

      hooks.process
    end

    it 'should run shell command with global timeout (including retries)' do
      hooks = Astute::NailgunHooks.new([shell_hook], ctx)
      hooks.stubs(:run_shell_command).once.with(
        ctx,
        ['1','2','3'],
        regexp_matches(/deploy/),
        Astute.config.mc_retries,
        Astute.config.mc_retry_interval,
        shell_hook['parameters']['timeout'],
        shell_hook['parameters']['cwd']
      )
      .raises(Timeout::Error)

      expect {hooks.process}.to_not raise_error
    end

    it 'should use default timeout if it does not set' do
      shell_hook['parameters'].delete('timeout')
      hooks = Astute::NailgunHooks.new([shell_hook], ctx)
      hooks.expects(:run_shell_command).once.with(
        ctx,
        ['1','2','3'],
        regexp_matches(/deploy/),
        Astute.config.mc_retries,
        Astute.config.mc_retry_interval,
        300,
        shell_hook['parameters']['cwd']
      )
      .returns(:data => {:exit_code => 0})

      hooks.process
    end

    it 'should limit nodes processing in parallel' do
      Astute.config.max_nodes_per_call = 2

      hooks = Astute::NailgunHooks.new([shell_hook], ctx)
      hooks.expects(:run_shell_command).once.with(
        ctx,
        ['1', '2'],
        regexp_matches(/deploy/),
        Astute.config.mc_retries,
        Astute.config.mc_retry_interval,
        shell_hook['parameters']['timeout'],
        shell_hook['parameters']['cwd']
      )
      .returns(:data => {:exit_code => 0})

      hooks.expects(:run_shell_command).once.with(
        ctx,
        ['3'],
        regexp_matches(/deploy/),
        Astute.config.mc_retries,
        Astute.config.mc_retry_interval,
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
        hooks.expects(:run_shell_command).returns(nil).once

        expect {hooks.process}.to_not raise_error
      end

      it 'if exit code not eql 0 -> raise error' do
        hooks = Astute::NailgunHooks.new([shell_hook], ctx)
        hooks.expects(:run_shell_command).returns("err").once

        expect {hooks.process}.to raise_error(Astute::DeploymentEngineError, /Failed to execute hook/)
      end

      it 'if exit code not presence -> raise error' do
        hooks = Astute::NailgunHooks.new([shell_hook], ctx)
        hooks.expects(:run_shell_command).returns("err").once

        expect {hooks.process}.to raise_error(Astute::DeploymentEngineError, /Failed to execute hook/)
      end

      it 'if timeout -> raise error' do
        hooks = Astute::NailgunHooks.new([shell_hook], ctx)
        hooks.expects(:run_shell_command).raises(Timeout::Error)

        expect {hooks.process}.to raise_error(Astute::DeploymentEngineError, /Failed to execute hook/)
      end
    end #context

    context "#run_shell_command" do

      let(:hooks) { Astute::NailgunHooks.new([shell_hook], ctx) }

      let(:mclient) do
        mclient = mock_rpcclient
        Astute::MClient.any_instance.stubs(:rpcclient).returns(mclient)
        Astute::MClient.any_instance.stubs(:log_result).returns(mclient)
        Astute::MClient.any_instance.stubs(:check_results_with_retries).returns(mclient)
        mclient
      end

      def mc_result(sender, succeed=true)
        {
          :sender => sender,
          :data => { :exit_code => succeed ? 0 : 1}
        }
      end

      before(:each) do
        ctx.stubs(:report_and_update_status)
        shell_hook['fail_on_error'] = true
      end

      it 'should use retries' do
        mclient.expects(:execute).times(2).returns([
          mc_result('1', true),
          mc_result('2', false),
          mc_result('3', true)
        ]).then.returns([mc_result('2', true)])

        hooks.process
      end

      it 'should fail if retries end' do
        Astute.config.mc_retries = 1

        mclient.expects(:execute).times(2).returns([
          mc_result('1', true),
          mc_result('2', false),
          mc_result('3', true)
        ]).then.returns([mc_result('2', false)])

        expect {hooks.process}.to raise_error(Astute::DeploymentEngineError)
      end

      it 'should fail if retries end and some nodes never answered' do
        Astute.config.mc_retries = 1

        mclient.expects(:execute).times(2)
          .returns([mc_result('1', true)])
          .then.returns([mc_result('2', true)])

        expect {hooks.process}.to raise_error(Astute::DeploymentEngineError)
      end

      it 'should retry if raise error' do
        Astute.config.mc_retries = 3

        mclient.expects(:execute).times(4)
          .returns([mc_result('1', true), mc_result('2', true)])
          .then.raises(Astute::MClientTimeout)
          .then.raises(Astute::MClientError)
          .then.returns([mc_result('3', true)])

        expect {
          hooks.process
        }.not_to raise_error
      end

      it 'should fail if it still raise error after retries' do
        Astute.config.mc_retries = 1

        # we retry 3 times on every mc retries (1 main + 1 retries) * 3 = 6
        mclient.expects(:execute).times(6)
          .then.raises(Astute::MClientTimeout)
          .then.raises(Astute::MClientError)

        expect {hooks.process}.to raise_error(Astute::DeploymentEngineError)
      end
    end

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
      Astute.config.max_nodes_per_call = 1
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

        expect {hooks.process}.to raise_error(Astute::DeploymentEngineError, /Failed to execute hook/)
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
        10,
        Astute.config.mc_retry_interval,
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
        10,
        Astute.config.mc_retry_interval,
        300
      )
      .returns(:data => {:exit_code => 0})

      hooks.process
    end

    it 'should limit nodes processing in parallel' do
      Astute.config.max_nodes_per_call = 1

      hooks = Astute::NailgunHooks.new([sync_hook], ctx)
      hooks.expects(:run_shell_command).once.with(
        ctx,
        ['1'],
        regexp_matches(/rsync/),
        10,
        Astute.config.mc_retry_interval,
        is_a(Integer)
      )
      .returns(:data => {:exit_code => 0})

      hooks.expects(:run_shell_command).once.with(
        ctx,
        ['2'],
        regexp_matches(/rsync/),
        10,
        Astute.config.mc_retry_interval,
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
        hooks.expects(:run_shell_command).returns(nil).once

        expect {hooks.process}.to_not raise_error
      end

      it 'if exit code not eql 0 -> raise error' do
        hooks = Astute::NailgunHooks.new([sync_hook], ctx)
        hooks.expects(:run_shell_command).returns("err").once

        expect {hooks.process}.to raise_error(Astute::DeploymentEngineError, /Failed to execute hook/)
      end

      it 'if exit code not presence -> raise error' do
        hooks = Astute::NailgunHooks.new([sync_hook], ctx)
        hooks.expects(:run_shell_command).returns("err").once

        expect {hooks.process}.to raise_error(Astute::DeploymentEngineError, /Failed to execute hook/)
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
        _retries=puppet_hook['parameters']['retries'],
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
        puppet_hook['parameters']['timeout'],
        puppet_hook['parameters']['retries']
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
        300,
        puppet_hook['parameters']['retries']
      ).returns(true)
      Astute::Context.any_instance.stubs(:status).returns({'1' => 'success', '3' => 'success'})

      hooks.process
    end

    it 'should use default retries if it does not set' do
      puppet_hook['parameters'].delete('retries')
      hooks = Astute::NailgunHooks.new([puppet_hook], ctx)
      hooks.expects(:run_puppet).once.with(
        ctx,
        ['1','3'],
        puppet_hook['parameters']['puppet_manifest'],
        puppet_hook['parameters']['puppet_modules'],
        puppet_hook['parameters']['cwd'],
        puppet_hook['parameters']['timeout'],
        Astute.config.puppet_retries,
      ).returns(true)
      Astute::Context.any_instance.stubs(:status).returns({'1' => 'success', '3' => 'success'})

      hooks.process
    end

    it 'should limit nodes processing in parallel' do
      Astute.config.max_nodes_per_call = 1

      hooks = Astute::NailgunHooks.new([puppet_hook], ctx)
      hooks.expects(:run_puppet).once.with(
        ctx,
        ['1'],
        puppet_hook['parameters']['puppet_manifest'],
        puppet_hook['parameters']['puppet_modules'],
        puppet_hook['parameters']['cwd'],
        puppet_hook['parameters']['timeout'],
        puppet_hook['parameters']['retries']
      ).returns(true)

      hooks.expects(:run_puppet).once.with(
        ctx,
        ['3'],
        puppet_hook['parameters']['puppet_manifest'],
        puppet_hook['parameters']['puppet_modules'],
        puppet_hook['parameters']['cwd'],
        puppet_hook['parameters']['timeout'],
        puppet_hook['parameters']['retries']
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

        expect {hooks.process}.to raise_error(Astute::DeploymentEngineError, /Failed to execute hook/)
      end

      it 'if mclient failed -> raise error' do
        hooks = Astute::NailgunHooks.new([puppet_hook], ctx)
        error_msg = "Puppet run failed. Check puppet logs for details"
        PuppetdDeployer.expects(:deploy).once.raises(Astute::MClientError)
        ctx.expects(:report_and_update_status).with(
          {'nodes' =>
            [
              { 'uid' => '1',
                'status' => 'error',
                'error_type' => 'deploy',
                'role' => 'hook',
                'hook' => "puppet-example-1.0",
                'error_msg' => error_msg
              },
              { 'uid' => '3',
                'status' => 'error',
                'error_type' => 'deploy',
                'role' => 'hook',
                'hook' => "puppet-example-1.0",
                'error_msg' => error_msg
              },
            ],
            'error' => "Failed to execute hook 'puppet-example-1.0' #{error_msg}"
          }
        )

        expect {hooks.process}.to raise_error(Astute::DeploymentEngineError, /Failed to execute hook/)
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
        regexp_matches(/reboot/),
        60,
      )
      .returns('2' => '', '3' => '')

      hooks.expects(:run_shell_without_check).once.with(
        ctx,
        ['2','3'],
        regexp_matches(/nailgun-agent/),
        60,
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
        60,
      )
      .returns('2' => '', '3' => '')

      hooks.stubs(:update_node_status).once
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
        60,
      )
      .returns('2' => '', '3' => '')

      hooks.stubs(:update_node_status).once

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
        60,
      )
      .returns('2' => '', '3' => '')
      hooks.stubs(:update_node_status).once

      hooks.expects(:sleep).with(300/10)

      hooks.process
    end

    it 'should limit nodes processing in parallel' do
      Astute.config.max_nodes_per_call = 1

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
        60,
      )
      .returns('2' => '')

      hooks.expects(:run_shell_without_check).once.with(
        ctx,
        ['3'],
        regexp_matches(/reboot/),
        60,
      )
      .returns('3' => '')

      hooks.stubs(:sleep)
      hooks.stubs(:update_node_status).once

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
          60,
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
        hooks.stubs(:update_node_status).once
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
        .returns('2' => time.to_s, '3' => (time - 5).to_s)

        hooks.stubs(:run_shell_without_check).with(
          ctx,
          ['2'],
          regexp_matches(/stat/),
          10,
        )
        .returns('2' => (time - 5).to_s, '3' => time.to_s)
        hooks.expects(:update_node_status).with([])

        expect {hooks.process}.to raise_error(Astute::DeploymentEngineError, /Failed to execute hook/)
      end

      it 'should successed if creation time is smaller' do
        time = Time.now.to_i
        hooks.stubs(:run_shell_without_check).twice.with(
          ctx,
          ['2','3'],
          regexp_matches(/stat/),
          10,
        )
        .returns('2' => time.to_s, '3' => time.to_s).then
        .returns('2' => (time - 1).to_s, '3' => (time - 2).to_s)
        hooks.expects(:update_node_status).with(['2', '3'])
        expect {hooks.process}.to_not raise_error
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
        hooks.stubs(:update_node_status)

        expect {hooks.process}.to raise_error(Astute::DeploymentEngineError, /Failed to execute hook/)
      end
    end #context

  end #reboot_hook

  context '#cobbler_sync_hook' do

    it 'should validate presence of provisioning_info' do
      cobbler_sync_hook['parameters']['provisioning_info'] = {}
      hooks = Astute::NailgunHooks.new([cobbler_sync_hook], ctx)

      expect {hooks.process}.to raise_error(StandardError, /Missing a required parameter/)
    end

    it 'should call Astute::CobblerManager sync method ' do
      hooks = Astute::NailgunHooks.new([cobbler_sync_hook], ctx)
      Astute::CobblerManager.any_instance.expects(:sync).once

      hooks.process
    end

  end #cobbler_sync_hook

  context '#cobbler_sync_nodes_hook' do

    it 'should validate presence of provisioning_info' do
      cobbler_sync_hook['parameters']['provisioning_info'] = {}
      hooks = Astute::NailgunHooks.new([cobbler_sync_hook], ctx)

      expect {hooks.process}.to raise_error(StandardError, /Missing a required parameter/)
    end

    it 'should validate presence of nodes' do
      cobbler_sync_hook['parameters']['nodes'] = []
      hooks = Astute::NailgunHooks.new([cobbler_sync_hook], ctx)

      expect {hooks.process}.to raise_error(StandardError, /Missing a required parameter/)
    end

    it 'should call Astute::CobblerManager add_nodes and get_existent_nodes methods' do
      hooks = Astute::NailgunHooks.new([cobbler_sync_hook], ctx)
      Astute::CobblerManager.any_instance.expects(:add_nodes).once
      Astute::CobblerManager.any_instance.expects(:get_existent_nodes).once

      hooks.process
    end

  end #cobbler_sync_hook

end # 'describe'
