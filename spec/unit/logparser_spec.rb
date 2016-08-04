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


require File.join(File.dirname(__FILE__), '../spec_helper')

include Astute

describe LogParser do
  def get_statistics_variables(progress_table)
    # Calculate some statistics variables: expectancy, standart deviation and
    # correlation coefficient between real and ideal progress calculation.
    total_time = 0
    real_expectancy = 0
    real_sqr_expectancy = 0
    prev_event_date = nil
    progress_table.each do |el|
      date = el[:date]
      prev_event_date = date unless prev_event_date
      progress = el[:progress].to_f
      period = date - prev_event_date
      hours, mins, secs, frac = Date::day_fraction_to_time(period)
      period_in_sec = hours * 60 * 60 + mins * 60 + secs
      total_time += period_in_sec
      real_expectancy += period_in_sec * progress
      real_sqr_expectancy += period_in_sec * progress ** 2
      el[:time_delta] = period_in_sec
      prev_event_date = date
    end

    # Calculate standart deviation for real progress distibution.
    real_expectancy = real_expectancy.to_f / total_time
    real_sqr_expectancy = real_sqr_expectancy.to_f / total_time
    real_standart_deviation = Math.sqrt(real_sqr_expectancy - real_expectancy ** 2)

    # Calculate PCC (correlation coefficient).
    ideal_sqr_expectancy = 0
    ideal_expectancy = 0
    t = 0
    ideal_delta = 100.0 / total_time
    mixed_expectancy = 0
    progress_table.each do |el|
      t += el[:time_delta]
      ideal_progress = t * ideal_delta
      ideal_expectancy += ideal_progress * el[:time_delta]
      ideal_sqr_expectancy += ideal_progress ** 2 * el[:time_delta]
      el[:ideal_progress] = ideal_progress
      mixed_expectancy += el[:progress] * ideal_progress * el[:time_delta]
    end

    ideal_expectancy = ideal_expectancy / total_time
    ideal_sqr_expectancy = ideal_sqr_expectancy / total_time
    mixed_expectancy = mixed_expectancy / total_time
    ideal_standart_deviation = Math.sqrt(ideal_sqr_expectancy - ideal_expectancy ** 2)
    covariance = mixed_expectancy - ideal_expectancy * real_expectancy
    pcc = covariance / (ideal_standart_deviation * real_standart_deviation)

    statistics = {
      'real_expectancy' => real_expectancy,
      'real_sqr_expectancy' => real_sqr_expectancy,
      'real_standart_deviation' => real_standart_deviation,
      'ideal_expectancy' => ideal_expectancy,
      'ideal_sqr_expectancy' => ideal_sqr_expectancy,
      'ideal_standart_deviation' => ideal_standart_deviation,
      'mixed_expectancy' => mixed_expectancy,
      'covariance' => covariance,
      'pcc' => pcc,
      'total_time' => total_time,
    }

    return statistics
  end

  def get_next_line(fo, date_regexp, date_format)
    until fo.eof?
      line = fo.readline
      date_string = line.match(date_regexp)
      if date_string
        date = DateTime.strptime(date_string[0], date_format)
        return line, date
      end
    end
  end

  def get_next_lines_by_date(fo, now, date_regexp, date_format)
    lines = ''
    until fo.eof?
      pos = fo.pos
      line, date = get_next_line(fo, date_regexp, date_format)
      if date <= now
        lines += line
      else
        fo.pos = pos
        return lines
      end
    end
    return lines
  end

  context "Correlation coeff. (PCC) of Provisioning progress bar calculation" do
    def provision_parser_wrapper(
        node,
        deploy_parser=Astute::LogParser::ParseProvisionLogs.new,
        date_regexp = '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}',
        date_format = '%Y-%m-%dT%H:%M:%S',
        path = nil
        )
      uids = [node['uid']]
      nodes = [node]
      time_delta = 5.0/24/60/60
      log_delay = 6*time_delta

      Dir.mktmpdir do |dir|
        Astute::LogParser::PATH_PREFIX.replace("#{dir}/")
        Astute::LogParser::ParseImageBuildLogs::PATH_PREFIX.replace("#{dir}/")
        pattern_spec = deploy_parser.get_pattern_for_node(node)
        # Create temp log files and structures.
        path = "#{pattern_spec['path_prefix']}" + (path || "#{node['hostname']}/#{pattern_spec['filename']}")
        FileUtils.mkdir_p(File.dirname(path))
        node['file'] = File.open(path, 'w')
        src_filename = File.join(File.dirname(__FILE__), "..", "example-logs", node['src_filename'])
        node['src'] = File.open(src_filename)
        line, date = get_next_line(node['src'], date_regexp, date_format)
        node['src'].pos = 0
        node['now'] = date - log_delay
        node['progress_table'] ||= []

        # End 'while' cycle if reach EOF at all src files.
        until node['src'].eof?
          # Copy logs line by line from example logfile to tempfile and collect progress for each step.
          lines, date = get_next_lines_by_date(node['src'], node['now'], date_regexp, date_format)
          node['file'].write(lines)
          node['file'].flush
          node['last_lines'] = lines

          DateTime.stubs(:now).returns(node['now'])
          node_progress = deploy_parser.progress_calculate(uids, nodes)[0]
          node['progress_table'] << {:date => node['now'], :progress => node_progress['progress']}
          node['now'] += time_delta
        end

        nodes.each do |node|
          node['statistics'] = get_statistics_variables(node['progress_table'])
        end
        # Clear temp files.
        node['file'].close
        File.unlink(node['file'].path)
      end

      return node
    end

    it "should be greather than 0.98 for Image Based Provisioning building" do
      node = {
        'uid' => '1',
        'ip' => '1.0.0.1',
        'hostname' => 'slave-1.domain.tld',
        'role' => 'controller',
        'src_filename' => 'fuel-agent-env-1.log_',
        'profile' => 'ubuntu_1404_x86_64'}

      deploy_parser = Astute::LogParser::ParseImageBuildLogs.new
      deploy_parser.cluster_id = 1
      calculated_node = provision_parser_wrapper(
        node,
        deploy_parser,
        date_regexp = '^\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}',
        date_format = '%Y-%m-%d %H:%M:%S',
        path="fuel-agent-env-1.log")
      calculated_node['statistics']['pcc'].should > 0.98
    end

    it "should be greather than 0.80 for Image Based Provisioning" do
      node = {
        'uid' => '1',
        'ip' => '1.0.0.1',
        'hostname' => 'slave-1.domain.tld',
        'role' => 'controller',
        'src_filename' => 'fuel-agent.log_',
        'profile' => 'ubuntu_1404_x86_64',
        'ks_meta' => {'image_data'=>[]}
      }
      calculated_node = provision_parser_wrapper(node)
      calculated_node['statistics']['pcc'].should > 0.80
    end

  end

  context "Dirsize-based progress calculation" do
    def create_dir_with_size(size, given_opts={})
      raise "The required size should be a non-negative number" if size < 0
      default_opts = {
        :chunksize => 10000,
        :tmpdir => Dir::tmpdir,
        :objects => [],
      }
      opts = default_opts.merge(given_opts)
      if !opts[:chunksize].instance_of?(Fixnum) || opts[:chunksize] <= 0
        raise "The 'chunksize' option should be a positive number"
      end
      raise "The 'tmpdir' option should be a path to a existent directory" if !opts[:tmpdir].instance_of?(String)
      raise "The 'objects' option should be an array" if !opts[:objects].instance_of?(Array)

      dir = Dir::mktmpdir(nil, opts[:tmpdir])
      opts[:objects] << dir
      chunk = 'A' * opts[:chunksize]
      while size >= opts[:chunksize]
        file = Tempfile::new('prefix', dir)
        file.write(chunk)
        file.close
        opts[:objects] << file
        size -= opts[:chunksize]
      end
      if size > 0
        file = Tempfile::new('prefix', dir)
        file.write('A' * size)
        file.close
        opts[:objects] << file
      end

      return {:path => dir, :objects => opts[:objects]}
    end

    it "should correctly calculate size of directory" do
      size = 10**6
      dir_info = create_dir_with_size(size)
      dir = dir_info[:path]
      nodes = [
        {:uid => '1',
          :path_items => [
            {:max_size => size*100/75,
             :path => dir}
          ]
        }
      ]
      correct_progress = [
        {'uid' => '1',
        'progress' => 75}
      ]
      dirsize_parser = Astute::LogParser::DirSizeCalculation.new(nodes)
      dirsize_parser.progress_calculate(['1'], nil).should eql(correct_progress)
      FileUtils::remove_entry_secure dir
    end

    it "should correctly calculate size of nested directories" do
      size = 10**6
      dir_info = create_dir_with_size(size)
      dir = dir_info[:path]
      dir_info = create_dir_with_size(size, {:tmpdir => dir, :objects => dir_info[:objects]})
      nodes = [
        {:uid => '1',
          :path_items => [
            {:max_size => size*4,
             :path => dir}
          ]
        }
      ]
      correct_progress = [
        {'uid' => '1',
        'progress' => 50}
      ]
      dirsize_parser = Astute::LogParser::DirSizeCalculation.new(nodes)
      dirsize_parser.progress_calculate(['1'], nil).should eql(correct_progress)
      FileUtils::remove_entry_secure dir
    end

    it "should return zero if there is no directory" do
      nodes = [
        {:uid => '1',
          :path_items => [
            {:max_size => 10000,
             :path => '/the-dir-that-should-not-exist'}
          ]
        }
      ]
      correct_progress = [
        {'uid' => '1',
        'progress' => 0}
      ]
      dirsize_parser = Astute::LogParser::DirSizeCalculation.new(nodes)
      dirsize_parser.progress_calculate(['1'], nil).should eql(correct_progress)
    end

    it "should return zero if no items is propagated" do
      nodes = [
        {:uid => '1',
          :path_items => []
        }
      ]
      correct_progress = [
        {'uid' => '1',
        'progress' => 0}
      ]
      dirsize_parser = Astute::LogParser::DirSizeCalculation.new(nodes)
      dirsize_parser.progress_calculate(['1'], nil).should eql(correct_progress)
    end
  end

  context "Dirsize-based weight reassignment" do
    it "should correctly assign weights to unweighted items" do
      nodes = [
        {:uid => '1',
          :path_items => [{}, {}, {}, {}]
        }
      ]
      dirsize_parser = Astute::LogParser::DirSizeCalculation.new(nodes)
      dirsize_parser.nodes.first[:path_items].each{|n| n[:weight].should eql(0.25)}
    end

    it "should correctly recalculate weights of weighted items" do
      nodes = [
        {:uid => '1',
          :path_items => [
            {:weight => 10},
            {:weight => 30},
          ]
        }
      ]
      dirsize_parser = Astute::LogParser::DirSizeCalculation.new(nodes)
      items = dirsize_parser.nodes.first[:path_items]
      items[0][:weight].should eql(0.25)
      items[1][:weight].should eql(0.75)
    end

    it "should correctly recalculate weights of mixed items" do
      nodes = [
        {:uid => '1',
          :path_items => [
            {:weight => 10},
            {:weight => 30},
            {}, {}
          ]
        }
      ]
      dirsize_parser = Astute::LogParser::DirSizeCalculation.new(nodes)
      items = dirsize_parser.nodes.first[:path_items]
      items[0][:weight].should eql(0.125)
      items[1][:weight].should eql(0.375)
      items[2][:weight].should eql(0.25)
      items[3][:weight].should eql(0.25)
    end

    it "should raise exception if a negative weight propagated" do
      nodes = [
        {:uid => '1',
          :path_items => [
            {:weight => -10},
          ]
        }
      ]
      expect{Astute::LogParser::DirSizeCalculation.new(nodes)}.to \
        raise_error("Weight should be a non-negative number")
    end

    it "should drop items with zero weight" do
      nodes = [
        {:uid => '1',
          :path_items => [
            {:weight => 0},
            {:weight => 0},
          ]
        }
      ]
      dirsize_parser = Astute::LogParser::DirSizeCalculation.new(nodes)
      dirsize_parser.nodes.first[:path_items].length.should eql(0)
    end

    it "should not change initialization attribute" do
      nodes = [
        {:uid => '1',
          :path_items => [
            {:weight => 0},
            {:weight => 5},
            {}
          ]
        }
      ]
      dirsize_parser = Astute::LogParser::DirSizeCalculation.new(nodes)
      dirsize_parser.nodes.should_not eql(nodes)
    end
  end

end
