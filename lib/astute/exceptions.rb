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
require 'timeout'

module Astute

  # Base class for all errors
  class AstuteError < StandardError; end

  # Provisioning log errors
  class ParseProvisionLogsError < AstuteError; end
  # Image provisioning errors
  class FailedImageProvisionError < AstuteError; end
  # Failed to reboot nodes
  class FailedToRebootNodesError < AstuteError; end
  # Deployment engine error
  class DeploymentEngineError < AstuteError; end
  # MClient errors
  class MClientError < AstuteError; end
  # MClient timeout error
  class MClientTimeout < Timeout::Error; end

end
