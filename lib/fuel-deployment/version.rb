# The Deployment module is a library for task based deployment
# Tasks are represented as a graph for each node. During the deployment
# each node is visited and given a next ready task from its graph until
# all nodes have no more tasks to run.
module Deployment
  # The current module version
  VERSION = '0.2.1'

  # Get the current module version
  # @return [String]
  def version
    VERSION
  end
end
