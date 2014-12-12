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

module Astute

	class TaskManager
	  def initialize(nodes)
	    @tasks = nodes.inject({}) do |h, n|
        h.merge({n['uid'] => n['tasks'].sort_by{ |f| f['priority'] }.each})
      end

	    @current_task = {}
	    Astute.logger.info "The following tasks will be performed on nodes: " \
	      "#{@tasks.map {|k, v| {k => v.to_a}}.to_yaml}"
	  end

	  def current_task(node_id)
	    @current_task[node_id]
	  end

	  def next_task(node_id)
	    @current_task[node_id] = @tasks[node_id].next
	  rescue StopIteration
	    @current_task[node_id] = nil
	    delete_node(node_id)
	  end

	  def delete_node(node_id)
	    @tasks[node_id] = nil
	  end

	  def task_in_queue?
	    @tasks.select{ |_k,v| v }.present?
	  end

	  def node_uids
	    @tasks.select{ |_k,v| v }.keys
	  end
	end
end