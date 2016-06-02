#!/usr/bin/env ruby

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
