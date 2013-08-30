Astute
======

Astute is orchestrator, which is using data about nodes and deployment settings performs two things:
- provision
- deploy

Provision
-----

OS installation on selected nodes.

Provisioning is done using Cobbler. Astute orchestrator collects data about nodes and creates corresponding Cobbler systems using parameters specified in engine section of provision data. After the systems are created, it connects to Cobbler engine and reboots nodes according to the power management parameters of the node.

Deploy
-----

OpenStack installation in the desired configuration on the selected nodes.

Astute uses data about nodes and deployment settings and recalculates parameters needed for deployment. Calculated parameters are passed to the nodes being deployed by use of nailyfact MCollective agent that uploads these attributes to `/etc/naily.facts` file of the node. Then puppet parses this file using Facter plugin and uploads these facts into puppet. These facts are used during catalog compilation phase by puppet master. Finally catalog is executed and Astute orchestrator passes to the next node in deployment sequence. Fuel Library provides puppet modules for Astute.

Using as library
-----

```ruby
require 'astute'

class ConsoleReporter
  def report(msg)
    puts msg.inspect
  end
end

reporter = ConsoleReporter.new

deploy_engine = Astute::DeploymentEngine::NailyFact
orchestrator = Astute::Orchestrator.new(deploy_engine, log_parsing=false)

# Add systems to cobbler, reboot and start installation process.
orchestrator.fast_provision(reporter, environment['engine'], environment['nodes'])

# Observation OS installation 
orchestrator.provision(reporter, environment['task_uuid'], environment['nodes'])

# Deploy OpenStack
orchestrator.deploy(reporter, environment['task_uuid'], environment['nodes'], environment['attributes'])

```

More information about expected content of environment you can find here:
http://docs.mirantis.com/fuel/3.1/installation-fuel-cli.html#yaml-high-level-structure

Simple example of using Astute as library: https://github.com/Mirantis/astute/blob/master/bin/astute



Using as CLI
-----

Provision:
    
    astute -f simple.yaml -c provision
    
Deploy:

    astute -f simple.yaml -c deploy

More information about content of `simple.yaml` you can find here: http://docs.mirantis.com/fuel/3.1/installation-fuel-cli.html#yaml-high-level-structure

Additional materials
-----

- ISO, other materials: http://fuel.mirantis.com/
- User guide: http://docs.mirantis.com/
- Development documentation: http://docs.mirantis.com/fuel-dev/


License
------

Licensed under the Apache License, Version 2.0 (the "License"); you may
not use this file except in compliance with the License. You may obtain
a copy of the License at http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
License for the specific language governing permissions and limitations
under the License.
