# -*- coding: utf-8 -*-

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


require 'erb'

module Astute
  module LogParser
    LOG_PORTION = 10000
    # Default values. Can be overrided by pattern_spec.
    # E.g. pattern_spec = {'separator' => 'new_separator', ...}
    PATH_PREFIX = '/var/log/remote/'
    SEPARATOR = "SEPARATOR\n"

    class NoParsing
      def initialize(*args)
      end

      def method_missing(*args)
        # We just eat the call if we don't want to deal with logs
      end

      def progress_calculate(*args)
        []
      end
    end

    class DirSizeCalculation
      attr_reader :nodes

      def initialize(nodes)
        @nodes = nodes.map{|n| n.dup}
        @nodes.each{|node| node[:path_items] = weight_reassignment(node[:path_items])}
      end

      def deploy_type=(*args)
        # Because we mimic the DeploymentParser, we should define all auxiliary method
        # even they do nothing.
      end

      def prepare(nodes)
        # Because we mimic the DeploymentParser, we should define all auxiliary method
        # even they do nothing.
      end

      def progress_calculate(uids_to_calc, nodes)
        uids_to_calc.map do |uid|
          node = @nodes.find{|n| n[:uid] == uid}
          node[:path_items] ||= []
          progress = 0
          node[:path_items].each do |item|
            size = recursive_size(item[:path])
            sub_progress = 100 * size / item[:max_size]
            sub_progress = 0 if sub_progress < 0
            sub_progress = 100 if sub_progress > 100
            progress += sub_progress * item[:weight]
          end
          {'uid' => uid, 'progress' => progress.to_i}
        end
      end

      private
      def recursive_size(path, opts={})
        return File.size?(path).to_i if not File.directory?(path)

        total_size = 0
        Dir[File.join("#{path}", '**/*')].each do |f|
          # Option :files_only used when you want to calculate total size of
          # regular files only. The default :files_only is false, so the function will
          # include inode size of each dir (4096 bytes in most cases) to total value
          # as the unix util 'du' does it.
          total_size += File.size?(f).to_i if File.file?(f) || ! opts[:files_only]
        end
        total_size
      end

      def weight_reassignment(items)
        # The finction normalizes the weights of each item in order to make sum of
        # all weights equal to one.
        # It divides items as wighted and unweighted depending on the existence of
        # the :weight key in the item.
        #   - Each unweighted item will be weighted as a one N-th part of the total number of items.
        #   - All weights of weighted items are summed up and then each weighted item
        #     gets a new weight as a multiplication of a relative weight among all
        #     weighted items and the ratio of the number of the weighted items to
        #     the total number of items.
        # E.g. we have four items: one with weight 0.5, another with weight 1.5, and
        # two others as unweighted. All unweighted items will get the weight 1/4.
        # Weight's sum of weighted items is 2. So the first item will get the weight:
        # (relative weight 0.5/2) * (weighted items ratio 2/4) = 1/8.
        # Finally all items will be normalised with next weights:
        # 1/8, 3/8, 1/4, and 1/4.

        ret_items = items.reject do |item|
          weight = item[:weight]
          # Save an item if it unweighted.
          next if weight.nil?
          raise "Weight should be a non-negative number" unless [Fixnum, Float].include?(weight.class) && weight >= 0
          # Drop an item if it weighted as zero.
          item[:weight] == 0
        end
        return [] if ret_items.empty?
        ret_items.map!{|n| n.dup}

        partial_weight = 1.0 / ret_items.length
        weighted_items = ret_items.select{|n| n[:weight]}
        weighted_sum = 0.0
        weighted_items.each{|n| weighted_sum += n[:weight]}
        weighted_sum = weighted_sum * ret_items.length / weighted_items.length if weighted_items.any?
        raise "Unexpectedly a summary weight of weighted items is a non-positive" if weighted_items.any? && weighted_sum <= 0
        ret_items.each do |item|
          weight = item[:weight]
          item[:weight] = weight ? weight / weighted_sum : partial_weight
        end

        ret_items
      end
    end

    class ParseNodeLogs
      attr_reader :pattern_spec

      def initialize
        @pattern_spec = {}
        @pattern_spec['path_prefix'] ||= PATH_PREFIX.to_s
        @pattern_spec['separator'] ||= SEPARATOR.to_s
        @nodes_patterns = {}
      end

      def progress_calculate(uids_to_calc, nodes)
        nodes_progress = []

        patterns = patterns_for_nodes(nodes, uids_to_calc)
        uids_to_calc.each do |uid|
          node = nodes.find {|n| n['uid'] == uid}
          @nodes_patterns[uid] ||= patterns[uid]
          node_pattern_spec = @nodes_patterns[uid]
          # FIXME(eli): this var is required for binding() below
          @pattern_spec = @nodes_patterns[uid]

          erb_path = node_pattern_spec['path_format']
          path = ERB.new(erb_path).result(binding())

          progress = 0
          begin
            # Return percent of progress
            progress = (get_log_progress(path, node_pattern_spec) * 100).to_i
          rescue => e
            Astute.logger.warn "Some error occurred when calculate progress " \
              "for node '#{uid}': #{e.message}, trace: #{e.format_backtrace}"
          end

          nodes_progress << {
            'uid' => uid,
            'progress' => progress
          }
        end

        nodes_progress
      end

      def prepare(nodes)
        patterns = patterns_for_nodes(nodes)
        nodes.each do |node|
          pattern = patterns[node['uid']]
          path = "#{pattern['path_prefix']}#{node['ip']}/#{pattern['filename']}"
          File.open(path, 'a') { |fo| fo.write pattern['separator'] } if File.writable?(path)
        end
      end

      # Get patterns for selected nodes
      # if uids_to_calc is nil, then
      # patterns for all nodes will be returned
      def patterns_for_nodes(nodes, uids_to_calc=nil)
        uids_to_calc = nodes.map { |node| node['uid'] } if uids_to_calc.nil?
        nodes_to_calc = nodes.select { |node| uids_to_calc.include?(node['uid']) }

        patterns = {}
        nodes_to_calc.map do |node|
          patterns[node['uid']] = get_pattern_for_node(node)
        end

        patterns
      end

      private

      def get_log_progress(path, node_pattern_spec)
        unless File.readable?(path)
          Astute.logger.debug "Can't read file with logs: #{path}"
          return 0
        end
        if node_pattern_spec.nil?
          Astute.logger.warn "Can't parse logs. Pattern_spec is empty."
          return 0
        end
        progress = nil
        File.open(path) do |fo|
          # Try to find well-known ends of log.
          endlog = find_endlog_patterns(fo, node_pattern_spec)
          return endlog if endlog
          # Start reading from end of file.
          fo.pos = fo.stat.size

          # Method 'calculate' should be defined at child classes.
          progress = calculate(fo, node_pattern_spec)
          node_pattern_spec['file_pos'] = fo.pos
        end
        unless progress
          Astute.logger.warn("Wrong pattern #{node_pattern_spec.inspect} defined for calculating progress via logs.")
          return 0
        end
        progress
      end

      def find_endlog_patterns(fo, pattern_spec)
        # Pattern example:
        # pattern_spec = {...,
        #   'endlog_patterns' => [{'pattern' => /Finished catalog run in [0-9]+\.[0-9]* seconds\n/, 'progress' => 1.0}],
        # }
        endlog_patterns = pattern_spec['endlog_patterns']
        return nil unless endlog_patterns
        fo.pos = fo.stat.size
        chunk = get_chunk(fo, 100)
        return nil unless chunk
        endlog_patterns.each do |pattern|
          return pattern['progress'] if Regexp.new("#{pattern['pattern']}$").match(chunk)
        end
        nil
      end

      def get_chunk(fo, size=nil, pos=nil)
        if pos
          fo.pos = pos
          return fo.read
        end
        size = LOG_PORTION unless size
        return nil if fo.pos == 0
        size = fo.pos if fo.pos < size
        next_pos = fo.pos - size
        fo.pos = next_pos
        block = fo.read(size)
        fo.pos = next_pos
        block
      end
    end
  end
end
