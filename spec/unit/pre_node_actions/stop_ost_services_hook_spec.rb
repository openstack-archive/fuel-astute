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

# TODO rewrite old spec

require File.join(File.dirname(__FILE__), '../../spec_helper')

describe Astute::StopOSTServices do
  include SpecHelpers

  let(:ctx) do
    ctx = mock('context')
    ctx.stubs(:task_id)
    ctx.stubs(:reporter)
    ctx.stubs(:status).returns('1' => 'success', '2' => 'success')
    ctx
  end

  let(:deploy_data) { [
                        {'uid' => '1',
                         'role' => 'controller',
                         'openstack_version_prev' => 'old_version',
                         'cobbler' => {
                            'profile' => 'centos-x86_64'
                          }
                        },
                        {'uid' => '2',
                         'role' => 'compute'
                        }
                      ]
                    }

  let(:stop_ost_services) { Astute::StopOSTServices.new }

  it 'should run if upgrade/downgrade env' do
    stop_ost_services.expects(:run_shell_command).once.returns(:data => {:exit_code => 0})
    stop_ost_services.process(deploy_data, ctx)
  end

  it 'should not run if deploy new env' do
    deploy_data.first.delete('openstack_version_prev')
    stop_ost_services.process(deploy_data, ctx)
    stop_ost_services.expects(:run_shell_command).never

    stop_ost_services.process(deploy_data, ctx)
  end

  it 'should not change deployment status if command fail' do
    stop_ost_services.expects(:run_shell_command).once.returns(:data => {:exit_code => 1})
    ctx.expects(:report_and_update_status).never

    stop_ost_services.process(deploy_data, ctx)
  end

  it 'should not change deployment status if shell exec using mcollective fail' do
    stop_ost_services.expects(:run_shell_command).once.returns(:data => {})

    stop_ost_services.process(deploy_data, ctx)
    ctx.expects(:report_and_update_status).never
  end

  describe '#getstop_cmd' do

    it 'should use delimiter "running", pos $1 for CentOS system' do
      services_list = 'nova|cinder|glance|keystone|neutron|sahara|murano|ceilometer|heat|swift|apache2|httpd'
      expected_cmd = <<-CMD
        echo "1st, try to stop given services gracefully";
        service --status-all 2>&1|egrep '#{services_list}'|awk '/running/ {print $1}'|
        xargs -n1 -I {} service {} stop >/dev/null 2>&1;
        echo "2nd, check for related running python processes, if any left";
        pids=$(ps aux|egrep '#{services_list}'|awk '!/grep/ {print $2}');
        echo "for every pid discovered, find all its childs";
        for p in `echo $pids`; do pids_to_kill=$(pstree -Alp $p|
        perl -e \"while(<>){ push @r, /((\\d+))/sg};
        print join(\\\"\\n\\\",@r), \\\"\\n\\\"\"|uniq);
        echo "and send SIGKILL";
        for pid in `echo $pids_to_kill`; do [ $pid -gt 1 ] && kill -9 $pid; done; done||true
        CMD
      expected_cmd.tr!("\n"," ")
      stop_ost_services.expects(:run_shell_command).once.with(
        ctx,
        ['1', '2'],
        includes(expected_cmd)
      )
      .returns(:data => {:exit_code => 0})

      stop_ost_services.process(deploy_data, ctx)
    end

    it 'should use delimiter "+", pos $4 for Ubuntu system' do
      services_list = 'nova|cinder|glance|keystone|neutron|sahara|murano|ceilometer|heat|swift|apache2|httpd'
      deploy_data.first['cobbler']['profile'] = 'ubuntu_1204_x86_64'
      expected_cmd = <<-CMD
        echo "1st, try to stop given services gracefully";
        service --status-all 2>&1|egrep '#{services_list}'|awk '/+/ {print $4}'|
        xargs -n1 -I {} service {} stop >/dev/null 2>&1;
        echo "2nd, check for related running python processes, if any left";
        pids=$(ps aux|egrep '#{services_list}'|awk '!/grep/ {print $2}');
        echo "for every pid discovered, find all its childs";
        for p in `echo $pids`; do pids_to_kill=$(pstree -Alp $p|
        perl -e \"while(<>){ push @r, /((\\d+))/sg};
        print join(\\\"\\n\\\",@r), \\\"\\n\\\"\"|uniq);
        echo "and send SIGKILL";
        for pid in `echo $pids_to_kill`; do [ $pid -gt 1 ] && kill -9 $pid; done; done||true
        CMD
      expected_cmd.tr!("\n"," ")
      stop_ost_services.expects(:run_shell_command).once.with(
        ctx,
        ['1', '2'],
        includes(expected_cmd)
      )
      .returns(:data => {:exit_code => 0})

      stop_ost_services.process(deploy_data, ctx)
    end

  end # getremovepackage_cmd

end
