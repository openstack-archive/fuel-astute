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
      "uids" =>  [2, 3],
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
      "uids" =>  [1, 2],
      "parameters" =>  {
        "src" =>  "rsync => //10.20.0.2 => /plugins/fuel_awesome_plugin-0.1.0/deployment_scripts/",
        "dst" =>  "/etc/fuel/plugins/fuel_awesome_plugin-0.1.0/"
      }
    }
  end

  let(:shell_hook) do
    {
      "priority" =>  100,
      "type" =>  "shell",
      "uids" =>  [1,2,3],
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
      "uids" =>  [1, 3],
      "parameters" =>  {
        "puppet_manifest" =>  "cinder_glusterfs.pp",
        "puppet_modules" =>  "modules",
        "cwd" => "/etc/fuel/plugins/plugin_name-1.0",
        "timeout" =>  42
      }
    }
  end

  let(:hooks_data) do
    [
      upload_file_hook,
      sync_hook,
      shell_hook,
      puppet_hook
    ]
  end

  context "#process" do
    it 'should process known hook type' do
      hooks = Astute::NailgunHooks.new(hooks_data, ctx)

      hooks.expects(:upload_file_hook)
      hooks.expects(:puppet_hook)
      hooks.expects(:shell_hook)
      hooks.expects(:sync_hook)

      hooks.process
    end

    it 'should raise exception if hook type is unknown' do
      wrong_hook = [{
        "priority" =>  300,
        "type" =>  "unknown",
        "uids" =>  [1, 3],
        "parameters" =>  {
          "parameter" => "1"
        }
        }]
      hooks = Astute::NailgunHooks.new(wrong_hook, ctx)

      expect {hooks.process}.to raise_error(StandardError, /Unknown hook type/)
    end

    it 'should run hooks by priority order' do
      hooks = Astute::NailgunHooks.new(hooks_data, ctx)

      hook_order = sequence('hook_order')

      hooks.expects(:upload_file_hook).in_sequence(hook_order)
      hooks.expects(:shell_hook).in_sequence(hook_order)
      hooks.expects(:sync_hook).in_sequence(hook_order)
      hooks.expects(:puppet_hook).in_sequence(hook_order)

      hooks.process
    end

  end #process

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
        [1,2,3],
        regexp_matches(/deploy/),
        shell_hook['parameters']['timeout']
      )
      .returns(:data => {:exit_code => 0})

      hooks.process
    end

    it 'should use default timeout if it does not set' do
      shell_hook['parameters'].delete('timeout')
      hooks = Astute::NailgunHooks.new([shell_hook], ctx)
      hooks.expects(:run_shell_command).once.with(
        ctx,
        [1,2,3],
        regexp_matches(/deploy/),
        300
      )
      .returns(:data => {:exit_code => 0})

      hooks.process
    end

    it 'should limit nodes processing in parallel' do
      Astute.config.MAX_NODES_PER_CALL = 2

      hooks = Astute::NailgunHooks.new([shell_hook], ctx)
      hooks.expects(:run_shell_command).once.with(
        ctx,
        [1, 2],
        regexp_matches(/deploy/),
        shell_hook['parameters']['timeout']
      )
      .returns(:data => {:exit_code => 0})

      hooks.expects(:run_shell_command).once.with(
        ctx,
        [3],
        regexp_matches(/deploy/),
        shell_hook['parameters']['timeout']
      )
      .returns(:data => {:exit_code => 0})

      hooks.process
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
        [2, 3],
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
        [2],
        has_entries(
          'content' => upload_file_hook['parameters']['data'],
          'path' => upload_file_hook['parameters']['path']
        )
      )

      hooks.expects(:upload_file).once.with(
        ctx,
        [3],
        has_entries(
          'content' => upload_file_hook['parameters']['data'],
          'path' => upload_file_hook['parameters']['path']
        )
      )

      hooks.process
    end

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
        [1,2],
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
        [1,2],
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
        [1],
        regexp_matches(/rsync/),
        is_a(Integer)
      )
      .returns(:data => {:exit_code => 0})

      hooks.expects(:run_shell_command).once.with(
        ctx,
        [2],
        regexp_matches(/rsync/),
        is_a(Integer)
      )
      .returns(:data => {:exit_code => 0})

      hooks.process
    end
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

     it 'should run puppet command with timeout' do
      hooks = Astute::NailgunHooks.new([puppet_hook], ctx)
      hooks.expects(:run_shell_command).once.with(
        ctx,
        [1,3],
        regexp_matches(/puppet/),
        puppet_hook['parameters']['timeout']
      )
      .returns(:data => {:exit_code => 0})

      hooks.process
    end

    it 'should use default timeout if it does not set' do
      puppet_hook['parameters'].delete('timeout')
      hooks = Astute::NailgunHooks.new([puppet_hook], ctx)
      hooks.expects(:run_shell_command).once.with(
        ctx,
        [1,3],
        regexp_matches(/puppet/),
        300
      )
      .returns(:data => {:exit_code => 0})

      hooks.process
    end

    it 'should limit nodes processing in parallel' do
      Astute.config.MAX_NODES_PER_CALL = 1

      hooks = Astute::NailgunHooks.new([puppet_hook], ctx)
      hooks.expects(:run_shell_command).once.with(
        ctx,
        [1],
        regexp_matches(/puppet/),
        puppet_hook['parameters']['timeout']
      )
      .returns(:data => {:exit_code => 0})

      hooks.expects(:run_shell_command).once.with(
        ctx,
        [3],
        regexp_matches(/puppet/),
        puppet_hook['parameters']['timeout']
      )
      .returns(:data => {:exit_code => 0})

      hooks.process
    end
  end

end # 'describe'
