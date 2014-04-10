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

describe Astute::UploadCirrosImage do
  include SpecHelpers

  let(:ctx) do
    ctx = mock('context')
    ctx.stubs(:task_id)
    ctx.stubs(:reporter)
    ctx.stubs(:status).returns(1 => 'success', 2 => 'success')
    ctx
  end

  let(:deploy_data) { [
                        {'uid' => 1,
                         'role' => 'controller',
                         'access' => {},
                         'test_vm_image' => {
                            'disk_format'       => 'qcow2',
                            'container_format'  => 'bare',
                            'public'            => 'true',
                            'img_name'          => 'TestVM',
                            'os_name'           => 'cirros',
                            'img_path'          => '/opt/vm/cirros-x86_64-disk.img',
                            'glance_properties' =>
                              '--property murano_image_info=\'{\"title\": \"Murano Demo\", \"type\": \"cirros.demo\"}\''
                         }
                        },
                        {'uid' => 2,
                         'role' => 'compute'
                        }
                      ]
                    }

  let(:upload_cirros_image) { Astute::UploadCirrosImage.new }

  it 'should not add cirros image if deploy fail' do
    ctx.expects(:status).returns(1 => 'error', 2 => 'success')
    upload_cirros_image.expects(:run_shell_command).never

    upload_cirros_image.process(deploy_data, ctx)
  end

  it 'should not add image again if we only add new nodes \
      to existing cluster' do
    deploy_data = [{'uid' => 2, 'role' => 'compute'}]
    upload_cirros_image.expects(:run_shell_command).never
    upload_cirros_image.process(deploy_data, ctx)
  end

  it 'should not add new image if it already added' do
    upload_cirros_image.expects(:run_shell_command)
                       .returns(:data => {:exit_code => 0}).once
    expect(upload_cirros_image.process(deploy_data, ctx)).to be_true
  end

  it 'should add new image if cluster deploy success and \
      no image was added before' do
    upload_cirros_image.stubs(:run_shell_command)
                       .returns(:data => {:exit_code => 1})
                       .then.returns(:data => {:exit_code => 0})
    expect(upload_cirros_image.process(deploy_data, ctx)).to be_true
  end

  it 'should send node error status for controller and raise if deploy \
      success and no image was added before and fail to add image' do
    ctx.expects(:report_and_update_status)
       .with('nodes' => [{
                          'uid' => 1,
                          'role' => 'controller',
                          'status' => 'error',
                          'error_type' => 'deploy'
                         }])
    upload_cirros_image.stubs(:run_shell_command)
                       .returns(:data => {:exit_code => 1})
                       .then.returns(:data => {:exit_code => 1})
    expect {upload_cirros_image.process(deploy_data, ctx)}
            .to raise_error(Astute::CirrosError, 'Upload cirros "TestVM" image failed')
  end

  it 'should run only in controller node' do
    upload_cirros_image.expects(:run_shell_command).once
                  .with(ctx, [1], anything)
                  .returns(:data => {:exit_code => 0})
    upload_cirros_image.process(deploy_data, ctx)
  end

end #'upload_cirros_image'