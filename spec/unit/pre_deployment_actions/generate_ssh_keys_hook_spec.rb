#    Copyright 2014 Mirantis, Inc.
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

require File.join(File.dirname(__FILE__), '../../spec_helper')

describe Astute::GenerateSshKeys do
  include SpecHelpers

  around(:each) do |example|
    old_puppet_ssh_keys = Astute.config.puppet_keys
    old_ssh_keys_dir = Astute.config.keys_src_dir
    example.run
    Astute.config.keys_src_dir = old_ssh_keys_dir
    Astute.config.puppet_keys = old_puppet_ssh_keys
  end

  before(:each) do
    Astute.config.puppet_ssh_keys = ['nova']
  end

  let(:ctx) do
    tctx = mock_ctx
    tctx.stubs(:status).returns({})
    tctx
  end

  let(:deploy_data) { [{'uid' => 1, 'deployment_id' => 1}, {'uid' => 2}] }
  let(:generate_ssh_keys) { Astute::GenerateSshKeys.new }

  it 'should raise error if deployment_id is not set' do
    nodes = [{'uid' => 1}, {'uid' => 2}]
    expect { generate_ssh_keys.process(nodes, ctx) }.to raise_error('Deployment_id is missing')
  end


  it 'should save files in correct place: KEY_DIR/<uid>/<name of key>/' do
    generate_ssh_keys.stubs(:run_system_command).returns([0, "", ""])

    Dir.mktmpdir do |temp_dir|
      Astute.config.keys_src_dir = temp_dir
      generate_ssh_keys.process(deploy_data, ctx)
      key_dir = File.join(temp_dir, deploy_data.first['uid'].to_s, 'nova')

      expect(File.directory? key_dir).to eq true
    end
  end

  it 'should raise error if directory for key was not created' do
    FileUtils.stubs(:mkdir_p).returns(false)
    File.stubs(:directory?).returns(false)

    expect { generate_ssh_keys.process(deploy_data, ctx) }.to raise_error(Astute::DeploymentEngineError,
                                                     /Could not create directory/)
  end

  it 'should raise error if ssh key generation fail' do
    FileUtils.stubs(:mkdir_p).returns(true)
    File.stubs(:directory?).returns(true)
    generate_ssh_keys.stubs(:run_system_command).returns([1, "", ""])

    expect { generate_ssh_keys.process(deploy_data, ctx) }.to raise_error(Astute::DeploymentEngineError,
                                                     /Could not generate ssh key! Command:/)
  end

  it 'should raise error if ssh key generation command not found' do
    FileUtils.stubs(:mkdir_p).returns(true)
    File.stubs(:directory?).returns(true)
    generate_ssh_keys.stubs(:run_system_command).returns([127, "Command not found", ""])

    expect { generate_ssh_keys.process(deploy_data, ctx) }.to raise_error(Astute::DeploymentEngineError,
                                                     /Command not found/)
  end

  it 'should run ssh key generation with correct command' do
    FileUtils.stubs(:mkdir_p).returns(true)
    File.stubs(:directory?).returns(true)

    key_path = File.join(Astute.config.keys_src_dir, deploy_data.first['deployment_id'].to_s, 'nova', 'nova')
    cmd = "ssh-keygen -b 2048 -t rsa -N '' -f #{key_path} 2>&1"
    generate_ssh_keys.expects(:run_system_command).with(cmd).returns([0, "", ""])

    generate_ssh_keys.process(deploy_data, ctx)
  end

  it 'should not overwrite files' do
    Dir.mktmpdir do |temp_dir|
      Astute.config.keys_src_dir = temp_dir
      key_dir = File.join(temp_dir, deploy_data.first['uid'].to_s, 'nova')
      key_path = File.join(key_dir, 'nova')
      FileUtils.mkdir_p key_dir
      File.open(key_path, 'w') { |file| file.write("say no overwrite") }
      generate_ssh_keys.process(deploy_data, ctx)

      expect(File.exist? key_path).to eq true
      expect(File.read key_path).to eq 'say no overwrite'
    end
  end

  it 'should check next key if find existing' do
    Astute.config.puppet_ssh_keys = ['nova', 'test']
    nova_key_path = File.join(Astute.config.keys_src_dir, deploy_data.first['deployment_id'].to_s, 'nova', 'nova')
    test_key_path = File.join(Astute.config.keys_src_dir, deploy_data.first['deployment_id'].to_s, 'test', 'test')

    FileUtils.stubs(:mkdir_p).returns(true).twice
    File.stubs(:directory?).returns(true).twice

    File.stubs(:exist?).with(nova_key_path).returns(true)
    File.stubs(:exist?).with(test_key_path).returns(false)

    generate_ssh_keys.expects(:run_system_command).returns([0, "", ""])

    generate_ssh_keys.process(deploy_data, ctx)
  end

end
