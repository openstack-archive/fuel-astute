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

# The Deployment module is a library for task based deployment
# Tasks are represented as a graph for each node. During the deployment
# each node is visited and given a next ready task from its graph until
# all nodes have no more tasks to run.
module Deployment
  # The current module version
  VERSION = '0.2.2'

  # Get the current module version
  # @return [String]
  def version
    VERSION
  end
end
