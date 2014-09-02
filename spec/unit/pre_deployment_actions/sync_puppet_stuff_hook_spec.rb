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

describe Astute::SyncPuppetStuff do
  include SpecHelpers

  let(:ctx) do
    tctx = mock_ctx
    tctx.stubs(:status).returns({})
    tctx
  end

  let(:sync_puppet_stuff) { Astute::SyncPuppetStuff.new }

  let(:nodes) { [
                  {'uid' => 1,
                   'deployment_id' => 1,
                   'master_ip' => '10.20.0.2',
                   'puppet_modules_source' => 'rsync://10.20.0.2:/puppet/modules/',
                   'puppet_manifests_source' => 'rsync://10.20.0.2:/puppet/manifests/'
                  },
                  {'uid' => 2}
                ]
              }

  let(:mclient) do
    mclient = mock_rpcclient(nodes)
    Astute::MClient.any_instance.stubs(:rpcclient).returns(mclient)
    Astute::MClient.any_instance.stubs(:log_result).returns(mclient)
    Astute::MClient.any_instance.stubs(:check_results_with_retries).returns(mclient)
    mclient
  end

  let(:master_ip) { nodes.first['master_ip'] }

  it "should sync puppet modules and manifests mcollective client 'puppetsync'" do
    mclient.expects(:rsync).with(:modules_source => "rsync://10.20.0.2:/puppet/modules/",
                                 :manifests_source => "rsync://10.20.0.2:/puppet/manifests/"
                                 )
    sync_puppet_stuff.process(nodes, ctx)
  end

  it 'should able to customize path for puppet modules and manifests' do
    modules_source = 'rsync://10.20.0.2:/puppet/vX/modules/'
    manifests_source = 'rsync://10.20.0.2:/puppet/vX/manifests/'
    nodes.first['puppet_modules_source'] = modules_source
    nodes.first['puppet_manifests_source'] = manifests_source
    mclient.expects(:rsync).with(:modules_source => modules_source,
                                 :manifests_source => manifests_source
                                 )
    sync_puppet_stuff.process(nodes, ctx)
  end


  context 'retry sync if mcollective raise error and' do
    it 'raise error if retry fail SYNC_RETRIES times' do
      mclient.stubs(:rsync)
      Astute::MClient.any_instance.stubs(:check_results_with_retries)
                                  .raises(Astute::MClientError)
                                  .times(Astute::DeploymentEngine::SYNC_RETRIES)
      expect { sync_puppet_stuff.process(nodes, ctx) }.to raise_error(Astute::MClientError)
    end

    it 'not raise error if mcollective return success less than SYNC_RETRIES attempts' do
      mclient.stubs(:rsync)
      Astute::MClient.any_instance.stubs(:check_results_with_retries)
                                  .raises(Astute::MClientError)
                                  .then.returns("")
      expect { sync_puppet_stuff.process(nodes, ctx) }.to_not raise_error(Astute::MClientError)
    end
  end

  it 'should raise exception if modules/manifests schema of uri is not equal' do
    nodes.first['puppet_manifests_source'] = 'rsync://10.20.0.2:/puppet/vX/modules/'
    nodes.first['puppet_manifests_source'] = 'http://10.20.0.2:/puppet/vX/manifests/'
    expect { sync_puppet_stuff.process(nodes, ctx) }.to raise_error(Astute::DeploymentEngineError,
        /Scheme for puppet_modules_source 'rsync' and puppet_manifests_source/)
  end

  it 'should raise exception if modules/manifests source uri is incorrect' do
    nodes.first['puppet_manifests_source'] = ':/puppet/modules/'
    expect { sync_puppet_stuff.process(nodes, ctx) }.to raise_error(Astute::DeploymentEngineError,
                                                       /bad URI/)
  end

  it 'should raise exception if schema of uri is incorrect' do
    nodes.first['puppet_modules_source'] = 'http2://localhost/puppet/modules/'
    nodes.first['puppet_manifests_source'] = 'http2://localhost/puppet/manifests/'
    mclient.expects(:rsync).never
    expect { sync_puppet_stuff.process(nodes, ctx) }.to raise_error(Astute::DeploymentEngineError,
                                                       /Unknown scheme /)
  end
end