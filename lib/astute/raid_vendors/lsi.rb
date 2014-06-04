module Astute
  module RaidVendors
    class Lsi
      EXEC = '/opt/MegaRAID/nytrocli/nytrocli64'
      CURL = '/usr/bin/curl -f'

      def initialize(context, nodes, interface, command)
        @context = context
        @node_uids = nodes.map{|v| v['uid']}
        @action = command['action']
        @interface = interface
        @controller_id = command['controller_id']
        @raid_lvl = command['raid_lvl']
        @phys_devices = command['phys_devices']*',' if command['phys_devices']
        @raw_phys_devices = command['phys_devices']
        @virtual_device = command['vitrual_device']
        @eid = command['eid']
        @name = command['raid_name']
        @options = command['options'] || {}
      end

      def create
        options = {'write_cache' => :wb, 'strip_size' => 128, 'cachevd' => false}
        options.merge! @options
        if @interface == 'cli'
          # Convert options to string for cli
          options = options.to_a.flatten* ' '
            cmd = "#{EXEC} /c#{@controller_id} add vd type=r#{@raid_lvl} drives=#{@eid}:#{@phys_devices}
            pdperarray=#{pd_per_array} #{options} J"
        elsif @interface == 'api'

          data = {drives: [], raid_level: @raid_lvl, name: @name}
          drive_struct = {controller_id: @controller_id, enclosure: @eid, slot: nil}

          @raw_phys_devices.each do |v|
            drive_struct[:slot] = v
            data[:drives] << drive_struct.clone
          end

          cmd = "#{CURL} -H 'Accept: Application/json' -H 'Content-Type: application/json'
            http://127.0.0.1:8080/v0.5/controllers/#{@controller_id}/virtualdevices -d '#{JSON.generate data.merge(options)}'"
        end

        run_shell_command(cmd.tr("\n", ' ').squeeze(' '))
      end

      def delete
        if @interface == 'cli'
          cmd = "#{EXEC} /c#{@controller_id}/v#{@vitrual_device} del J"
        elsif @interface == 'api'
          cmd = "#{CURL} -X DELETE http://127.0.0.1:8080/v0.5/controllers/#{@controller_id}/virtualdevices/#{@vitrual_device}"
        end

        run_shell_command(cmd)
      end

      def clear_all
        if @interface == 'cli'
          cmd = "#{EXEC} /c#{@controller_id}/vall del force J"
        elsif @interface == 'api'
          cmd = "#{CURL} -X DELETE http://127.0.0.1:8080/v0.5/controllers/#{@controller_id}/virtualdevices"
        end

        run_shell_command(cmd)
      end

      def create_cachecade
        options = {'write_cache' => 'wt'}
        options.merge! @options
        if @interface == 'cli'
          # Convert options to string for cli
          options = options.to_a.flatten* ' '
          cmd = "#{EXEC} /c#{@controller_id} add VD cachecade type=r#{@raid_lvl} drives=#{@eid}:#{@phys_devices} #{options} J"
        elsif @interface == 'api'

          data = {drives: [], raid_level: @raid_lvl}
          drive_struct = {controller_id: @controller_id, enclosure: @eid, slot: nil }


          @raw_phys_devices.each do |v|
            drive_struct[:slot] = v
            data[:drives] << drive_struct.clone
          end

          cmd = "#{CURL} -H 'Accept: Application/json' -H 'Content-Type: application/json'
            http://127.0.0.1:8080/v0.5/controllers/#{@controller_id}/virtualdevices/cachecade
            -d '#{JSON.generate data.merge(options)}'"
        end

        run_shell_command(cmd.tr("\n", ' ').squeeze(' '))
      end

      def delete_cachecade
        if @interface == 'cli'
          cmd "#{EXEC} /c#{@controller_id}/v#{@virtual_device} del cc"
        elsif @interface == 'api'
          cmd = "#{CURL} -X DELETE http://127.0.0.1:8080/v0.5/controllers/#{@controller_id}/cachecade/#{@virtual_device}"
        end

        run_shell_command(cmd)
      end

      def create_nytrocache
        options = {'write_cache' => 'wt'}
        options.merge! @options
        if @interface == 'cli'
          # Convert options to string for cli
          options = options.to_a.flatten* ' '
          cmd = "#{EXEC} /c#{@controller_id} add VD nytrocache type=r#{@raid_lvl} drives=#{@eid}:#{@phys_devices} J"
        elsif @interface == 'api'
          data = {drives: [], raid_level: @raid_lvl}
          drive_struct = {controller_id: @controller_id, enclosure: @eid, slot: nil }

          @raw_phys_devices.each do |v|
            drive_struct[:slot] = v
            data[:drives] << drive_struct.clone
          end

          cmd = "#{CURL} -H 'Accept: Application/json' -H 'Content-Type: application/json'
            http://127.0.0.1:8080/v0.5/controllers/#{@controller_id}/virtualdevices/nytrocache
            -d '#{JSON.generate data.merge(options)}'"
        end

        run_shell_command(cmd.tr("\n", ' ').squeeze(' '))
      end

      def delete_nytrocache
        if @interface == 'cli'
          cmd "#{EXEC} /c#{@controller_id}/v#{@virtual_device} del nytrocache"
        elsif @interface == 'api'
          cmd = "#{CURL} -X DELETE http://127.0.0.1:8080/v0.5/controllers/#{@controller_id}/nytrocache/#{@virtual_device}"
        end

        run_shell_command(cmd)
      end

      def enable_ssd_caching
        if @interface == 'cli'
          cmd "#{EXEC} /c#{@controller_id}/v#{@virtual_device} set ssdcaching=on J"
        elsif @interface == 'api'
          options = {ssd_caching: true}
          cmd = "#{CURL} -H 'Accept: Application/json' -H 'Content-Type: application/json'
            http://127.0.0.1:8080/v0.5/controllers/#{@controller_id}/virtualdevices/#{@virtual_device}
            -d '#{JSON.generate options}'"
        end

        run_shell_command(cmd.tr("\n", ' ').squeeze(' '))
      end

      def disable_ssd_caching
        if @interface == 'cli'
          cmd "#{EXEC} /c#{@controller_id}/v#{@virtual_device} set ssdcaching=off J"
        elsif @interface == 'api'
          options = {ssd_caching: false}
          cmd = "#{CURL} -H 'Accept: Application/json' -H 'Content-Type: application/json'
            http://127.0.0.1:8080/v0.5/controllers/#{@controller_id}/virtualdevices/#{@virtual_device}
            -d '#{JSON.generate options}'"
        end

        run_shell_command(cmd.tr("\n", ' ').squeeze(' '))
      end

      def add_hotspare
        if @interface == 'cli'
          # Convert options to string for cli
          options = @options.to_a.flatten* ' '
          cmd = "#{EXEC} /c#{@controller_id}/e#{@eid}/s#{@phys_devices} add hotsparedrive #{options} J"

          run_shell_command(cmd)
        elsif @interface == 'api'
          @raw_phys_devices.each do |dev|
            cmd = "#{CURL} -H 'Accept: Application/json' -H 'Content-Type: application/json'
              http://127.0.0.1:8080/v0.5/controllers/#{@controller_id}/physicaldevices/#{@eid}/#{dev}/hotspare
              -d '#{JSON.generate @options}'"

          run_shell_command(cmd.tr("\n", ' ').squeeze(' '))
          end
        end
      end

      def delete_hotspare
        if @interface == 'cli'
          cmd = "#{EXEC} /c#{@controller_id}/e#{@eid}/s#{@phys_devices} delete hotsparedrive J"

          run_shell_command(cmd)
        elsif @interface == 'api'
          @raw_phys_devices.each do |dev|
            cmd = "#{CURL} -X DELETE http://127.0.0.1:8080/v0.5/controllers/#{@controller_id}/#{@eid}/#{dev}/hotspare"

          run_shell_command(cmd)
          end
        end

      end

      def create_nwd
        if @interface == 'cli'
        cmd = "#{EXEC} /c#{@controller_id}/sall start format J"
        elsif @interface == 'api'
          cmd = "#{CURL} -H 'Accept: Application/json' -H 'Content-Type: application/json'
            http://127.0.0.1:8080/v0.5/controllers/#{@controller_id}/virtualdevices/warpdrive
            -d '#{JSON.generate @options}'"
        end

        run_shell_command(cmd.tr("\n", ' ').squeeze(' '))
      end

      def modify
      end

      def start_rebuild
      end

      def nailgun_agent
        run_shell_command('/opt/nailgun/bin/agent sleep-off > /dev/null')
      end

      def run_shell_command(cmd)
        shell = MClient.new(@context,
                            'execute_shell_command',
                            @node_uids,
                            check_result=true,
                            timeout=60,
                            retries=1)

        #TODO: return result for all nodes not only for first
        response = shell.execute(:cmd => cmd).first
        Astute.logger.debug("#{@context.task_id}: cmd: #{cmd}
          stdout: #{response[:data][:stdout]}
          stderr: #{response[:data][:stderr]}
          exit code: #{response[:data][:exit_code]}")

        error_msg = "Raid action #{@action} is failed"
        if response[:data][:exit_code] != 0
          raise Astute::RaidError, error_msg
        else
          response[:data][:stdout]
        end
      end

      private

      def pd_per_array
        raid_lvl = @raid_lvl.to_i
        case
        when raid_lvl == 10
          return 2
        when raid_lvl == 50
          return 3
        when raid_lvl == 60
          return 4
        else
          return 0
        end
      end
    end
  end # Raid
end # Astute
