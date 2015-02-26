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

describe Astute::GenerateKeys do
  include SpecHelpers

  before(:each) do
    Astute.config.puppet_keys = ['mongodb']
  end

  let(:ctx) do
    tctx = mock_ctx
    tctx.stubs(:status).returns({})
    tctx
  end

  let(:deploy_data) { [{'uid' => 1, 'deployment_id' => 1}, {'uid' => 2}] }
  let(:generate_keys) { Astute::GenerateKeys.new }

  around(:each) do |example|
    old_keys_dir = Astute.config.keys_src_dir
    old_puppet_keys = Astute.config.puppet_keys
    example.run
    Astute.config.keys_src_dir = old_keys_dir
    Astute.config.puppet_keys = old_puppet_keys
  end

  it 'should raise error if deployment_id is not set' do
    nodes = [{'uid' => 1}, {'uid' => 2}]
    expect { generate_keys.process(nodes, ctx) }.to raise_error('Deployment_id is missing')
  end


  it 'should save files in correct place: KEY_DIR/<name of key>/' do
    generate_keys.stubs(:run_system_command).returns([0, "", ""])

    Dir.mktmpdir do |temp_dir|
      Astute.config.keys_src_dir = temp_dir
      generate_keys.process(deploy_data, ctx)

      expect { File.directory? File.join(temp_dir, 'mongodb.key') }.to be_true
    end
  end

  it 'should raise error if directory for key was not created' do
    FileUtils.stubs(:mkdir_p).returns(false)
    File.stubs(:directory?).returns(false)

    expect { generate_keys.process(deploy_data, ctx) }.to raise_error(Astute::DeploymentEngineError,
                                                     /Could not create directory/)
  end

  it 'should raise error if key generation fail' do
    FileUtils.stubs(:mkdir_p).returns(true)
    File.stubs(:directory?).returns(true)
    generate_keys.stubs(:run_system_command).returns([1, "", ""])

    expect { generate_keys.process(deploy_data, ctx) }.to raise_error(Astute::DeploymentEngineError,
                                                     /Could not generate key! Command:/)
  end

  it 'should raise error if key generation command not found' do
    FileUtils.stubs(:mkdir_p).returns(true)
    File.stubs(:directory?).returns(true)
    generate_keys.stubs(:run_system_command).returns([127, "Command not found", ""])

    expect { generate_keys.process(deploy_data, ctx) }.to raise_error(Astute::DeploymentEngineError,
                                                     /Command not found/)
  end

  it 'should run key generation with correct command' do
    FileUtils.stubs(:mkdir_p).returns(true)
    File.stubs(:directory?).returns(true)

    key_path = File.join(
      Astute.config.keys_src_dir,
      deploy_data.first['deployment_id'].to_s,
      'mongodb',
      'mongodb.key'
    )
    cmd = "openssl rand -base64 741 > #{key_path} 2>&1"
    generate_keys.expects(:run_system_command).with(cmd).returns([0, "", ""])

    generate_keys.process(deploy_data, ctx)
  end

  it 'should not overwrite files' do
    Dir.mktmpdir do |temp_dir|
      Astute.config.keys_src_dir = temp_dir
      key_path = File.join(temp_dir,'mongodb', 'mongodb.key')
      FileUtils.mkdir_p File.join(temp_dir, 'mongodb')
      File.open(key_path, 'w') { |file| file.write("say no overwrite") }
      generate_keys.process(deploy_data, ctx)

      expect { File.exist? File.join(key_path, 'mongodb', 'mongodb.key') }.to be_true
      expect { File.read File.join(key_path, 'mongodb', 'mongodb.key') == "say no overwrite" }.to be_true
    end
  end

  it 'should check next key if find existing' do
    Astute.config.puppet_keys = ['mongodb', 'test']
    mongodb_key_path = File.join(
      Astute.config.keys_src_dir,
      deploy_data.first['deployment_id'].to_s,
      'mongodb',
      'mongodb.key'
    )
    test_key_path = File.join(
      Astute.config.keys_src_dir,
      deploy_data.first['deployment_id'].to_s,
      'test',
      'test.key'
    )

    FileUtils.stubs(:mkdir_p).returns(true).twice
    File.stubs(:directory?).returns(true).twice

    File.stubs(:exist?).with(mongodb_key_path).returns(true)
    File.stubs(:exist?).with(test_key_path).returns(false)

    generate_keys.expects(:run_system_command).returns([0, "", ""])

    generate_keys.process(deploy_data, ctx)
  end

end