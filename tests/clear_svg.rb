#!/usr/bin/env ruby
#    Copyright 2016 Mirantis, Inc.
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

require 'find'

def root
  File.expand_path File.join File.dirname(__FILE__), '..'
end

def svg_files
  return to_enum(:svg_files) unless block_given?
  Find.find(root) do |file|
    next unless File.file? file
    next unless file.end_with? '.svg'
    yield file
  end
end

svg_files do |file|
  puts "Remove: #{file}"
  File.unlink file if File.file? file
end
