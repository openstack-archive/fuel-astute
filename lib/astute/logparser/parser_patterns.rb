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


module Astute
  module LogParser
    module Patterns
      def self.get_default_pattern(key)
        pattern_key = key
        pattern_key = 'default' unless @default_patterns.has_key?(key)
        deep_copy(@default_patterns[pattern_key])
      end

      def self.list_default_patterns
        return @default_patterns.keys
      end

      @default_patterns = {
        'provisioning-image-building' =>
        {'type' => 'supposed-time',
         'chunk_size' => 10000,
         'date_format' => '%Y-%m-%d %H:%M:%S',
         'date_regexp' => '^\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}',
         'pattern_list' => [
           {'pattern' => '--- Building image (do_build_image) ---', 'supposed_time' => 12},
           {'pattern' => '*** Shipping image content ***', 'supposed_time' => 12},
           {'pattern' => 'Running deboostrap completed', 'supposed_time' => 270},
           {'pattern' => 'Running apt-get install completed', 'supposed_time' => 480},
           {'pattern' => '--- Building image END (do_build_image) ---', 'supposed_time' => 240},
           {'pattern' => 'All necessary images are available.', 'supposed_time' => 10}
         ].reverse,
         'filename' => "fuel-agent-env",
         'path_format' => "<%= @pattern_spec['path_prefix']%><%= @pattern_spec['filename']%>-<%= @pattern_spec['cluster_id']%>.log"
        },

        'image-based-provisioning' =>
          {'type' => 'pattern-list',
           'chunk_size' => 10000,
           'pattern_list' => [
             {'pattern' => '--- Provisioning (do_provisioning) ---', 'progress' => 0.81},
             {'pattern' => '--- Partitioning disks (do_partitioning) ---', 'progress' => 0.82},
             {'pattern' => '--- Creating configdrive (do_configdrive) ---', 'progress' => 0.92},
             {'pattern' => 'Next chunk',
              'number' => 600,
              'p_min' => 0.92,
              'p_max' => 0.98},
             {'pattern' => '--- Installing bootloader (do_bootloader) ---', 'progress' => 0.99},
             {'pattern' => '--- Provisioning END (do_provisioning) ---', 'progress' => 1}
          ],
          'filename' => 'bootstrap/fuel-agent.log',
          'path_format' => "<%= @pattern_spec['path_prefix'] %><%= node['hostname'] %>/<%= @pattern_spec['filename'] %>",
        },

        'default' => {
          'type' => 'count-lines',
          'endlog_patterns' => [{'pattern' => /Finished catalog run in [0-9]+\.[0-9]* seconds\n/, 'progress' => 1.0}],
          'expected_line_number' => 345,
          'filename' => 'puppet-apply.log',
          'path_format' => "<%= @pattern_spec['path_prefix'] %><%= node['fqdn'] %>/<%= @pattern_spec['filename'] %>"
        },
      }
    end
  end
end
