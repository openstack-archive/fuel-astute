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


# -*- coding: utf-8 -*-
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

    class ParseNodeLogs
      attr_reader :pattern_spec

      def initialize(pattern_spec)
        @nodes_states = {}
        @pattern_spec = pattern_spec
        @pattern_spec['path_prefix'] ||= PATH_PREFIX.to_s
        @pattern_spec['separator'] ||= SEPARATOR.to_s
      end

      def progress_calculate(uids_to_calc, nodes)
        nodes_progress = []
        uids_to_calc.each do |uid|
          node = nodes.select {|n| n['uid'] == uid}[0]  # NOTE: use nodes hash
          node_pattern_spec = @nodes_states[uid]
          unless node_pattern_spec
            node_pattern_spec = Marshal.load(Marshal.dump(@pattern_spec))
            @nodes_states[uid] = node_pattern_spec
          end
          erb_template = @pattern_spec['path_format']
          renderer = ERB.new(erb_template)
          path = renderer.result(binding())
          begin
            progress = (get_log_progress(path, node_pattern_spec)*100).to_i # Return percent of progress
          rescue Exception => e
            Astute.logger.warn "Some error occurred when calculate progress for node '#{uid}': #{e.message}, trace: #{e.backtrace.inspect}"
            progress = 0
          end

          nodes_progress << {
            'uid' => uid,
            'progress' => progress
          }
        end
        nodes_progress
      end

      def prepare(nodes)
        @nodes_states = {}
        nodes.each do |node|
          path = "#{@pattern_spec['path_prefix']}#{node['ip']}/#{@pattern_spec['filename']}"
          File.open(path, 'a') {|fo| fo.write @pattern_spec['separator'] } if File.writable?(path)
        end
      end

      def pattern_spec= (pattern_spec)
        initialise(pattern_spec) # NOTE: bug?
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
          return pattern['progress'] if chunk.end_with?(pattern['pattern'])
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
