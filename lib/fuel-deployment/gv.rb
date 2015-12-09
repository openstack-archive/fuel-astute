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

require 'graphviz'

module Deployment
  # This module can be loaded to visualize the current graph as an image
  module GV

    # Set graph filter to one node
    # @param [Deployment::Node] value
    def gv_filter_node=(value)
      @gv_filter_node = value
    end

    # Get the node filter
    # @return [Deployment::Node]
    def gv_filter_node
      @gv_filter_node
    end

    # Generate a name for the graph file
    # @return [String]
    def gv_graph_name
      [:name, :id].each do |method|
        return send method if respond_to? method and send method
      end
      'graph'
    end

    # Choose a color for a task vertex
    # according to the tasks status
    # @param [Deployment::Task] task
    # @return [Symbol]
    def gv_task_color(task)
      case task.status
        when :pending;
          :white
        when :ready
          :yellow
        when :successful;
          :green
        when :failed;
          :red
        when :dep_failed;
          :rose
        when :skipped;
          :purple
        when :running;
          :blue
        else
          :white
      end
    end

    # Remove the saved object
    def gv_reset
      @gv_object = nil
    end

    # Generate a GraphViz object with graph data
    # @return [GraphViz]
    def gv_object
      return @gv_object if @gv_object
      return unless defined? GraphViz
      @gv_object = GraphViz.new gv_graph_name, :type => :digraph
      @gv_object.node_attrs[:style] = 'filled, solid'

      each_task do |task|
        next unless task.node == gv_filter_node if gv_filter_node
        gv_node = @gv_object.add_node task.to_s
        gv_node.fillcolor = gv_task_color(task)
      end

      each_task do |task|
        task.each_dependency do |dep_task|
          next unless dep_task.node == gv_filter_node if gv_filter_node
          next unless @gv_object.find_node dep_task.to_s and @gv_object.find_node task.to_s
          @gv_object.add_edges dep_task.to_s, task.to_s
        end
      end
      @gv_object
    end

    # Generate the graph representation in the dot language
    # @return [String]
    def to_dot
      return unless gv_object
      gv_object.to_s
    end

    # This method allows you to make series of images during the deployment
    # It can be used to illustrate how the deployment is going on each deployment step
    def gv_make_step_image
      gv_reset
      return unless gv_object
      @step = 1 unless @step
      name = "#{gv_object.name}-#{@step.to_s.rjust 5, '0'}"
      file = gv_make_image name
      @step += 1
      gv_reset
      file
    end

    # Write the graph state to image file
    # @param [String] name File name
    def gv_make_image(name=nil)
      return unless gv_object
      name = gv_object.name unless name
      file = "#{name}.png"
      gv_object.output(:png => file)
      file
    end
  end
end
