#!/usr/bin/env ruby
require 'json'
require 'yaml'

public_iface = "eth0"
internal_iface = "eth1"
private_iface = "eth2"
default_gateway = "172.18.94.33"
master_ip = "172.18.94.34"
dns1 = default_gateway
internal_net = '10.107.2.0'

internal_net_prefix = internal_net.split('.')[0..2].join(".")


nodes = {"compute-01" => '64:c3:54:54:d2:66',
         "controller-01" => "64:48:7a:14:83:e8",
         "controller-02" => "64:b7:37:b1:1d:c9",
         "controller-03" => "64:f4:64:e7:50:d3",
         "swift-01"      => "64:57:26:83:1d:ca",
         "swift-02"      => "64:dc:fd:ad:eb:4e",
         "swift-03"      => "64:ea:df:59:79:39",
         "swiftproxy-01" => "64:bc:c3:9c:07:26",
         "swiftproxy-02" => "64:97:93:5f:b2:dc"
}

template = YAML.load(File.open('example_new.yaml'))
template_node = template['node_01']
newyaml = template
newyaml['nodes'] = []
newyaml.delete('node_01')
cluster = JSON.load(File.open('full.json'))
nodes.each do |node,macaddr| 
    result = template_node.clone
    json_node = cluster.select {|n| n['mac'].to_s == macaddr.to_s.upcase}[0]
    mac = json_node['mac'].to_s
    ip = json_node['ip'].to_s
    l_octet = ip.split('.')[3]
    id = json_node['id'].to_s
    uid = id
    if node == nodes.select{ |n,m| n.to_s =~ /controller/ }.map{|n,m| n}.first
        role = 'primary-controller'
    elsif node =~ /controller/
        role = 'controller'
    elsif node == nodes.select { |n,m| n.to_s =~ /swiftproxy/ }.map{|n,m| n}.first
        role = 'primary-swift-proxy'
    elsif node =~ /swiftproxy/
        role = 'swift-proxy'
    elsif node =~ /swift-\d+/
        role = 'storage'
    else
        role = 'compute'
    end

    cobbler_dnsname = "#{node}.domain.tld"
    cobbler_interfaces = {
        public_iface => {"ip_address"=>ip, "netmask"=> "255.255.255.0", "dns_name"=>cobbler_dnsname, "static"=> "1", "mac_address" => mac}
    }
    cobbler_interfaces_extra = {
        public_iface => {'onboot'=>'yes','peerdns'=>'no'},
        internal_iface => {'onboot'=>'no','peerdns'=>'no'},
        private_iface => {'onboot'=>'no','peerdns'=>'no'}
    }
    result['interfaces'] = cobbler_interfaces
    result['interfaces_extra'] = cobbler_interfaces_extra
    result['power_address'] = ip
    result['mac'] = mac
    result['default_gateway'] = default_gateway
    result['name'] = node
    result['ip'] = ip
    result['id'] = id
    result['uid'] = uid
    result['name_servers'] = master_ip
    result['role'] = role
    result['fqdn'] = cobbler_dnsname
    system_disk=json_node['meta']['disks'].select {|disk| disk['name'] == 'vda'}.first
    cinder_disk=json_node['meta']['disks'].select {|disk| disk['name'] == 'vdb'}.first

    system_disk_path = system_disk['disk']
    system_disk_size = (system_disk['size']/1048756.0).floor
    cinder_disk_path = cinder_disk['disk']
    cinder_disk_size = (cinder_disk['size']/1048756.0).floor

    system_pv_size = system_disk_size - 201
    swap_size = 1024
    free_vg_size = system_pv_size - swap_size
    free_extents = (free_vg_size/32.0).floor
    system_disk_size = 32 * free_extents


#    ks_spaces: '"[{\"type\": \"disk\", \"id\": \"disk/by-path/pci-0000:00:06.0-virtio-pci-virtio3\",
#     \"volumes\": [{\"mount\": \"/boot\", \"type\": \"partition\", \"size\": 200},
#     {\"type\": \"mbr\"}, {\"size\": 20000, \"type\": \"pv\", \"vg\": \"os\"}],
#     \"size\": 20480}, {\"type\": \"vg\", \"id\": \"os\", \"volumes\": [{\"mount\":
#     \"/\", \"type\": \"lv\", \"name\": \"root\", \"size\": 10240 }, {\"mount\":
#     \"swap\", \"type\": \"lv\", \"name\": \"swap\", \"size\": 2048}]}]"'
 

    ks_spaces = '"[{\"type\": \"disk\", \"id\": \"' +
      system_disk_path.to_s +
      '\",\"volumes\": [{\"mount\": \"/boot\", \"type\": \"partition\", \"size\": 200}, {\"type\": \"mbr\"}, {\"size\": ' +
      system_pv_size.to_s +
      ', \"type\": \"pv\", \"vg\": \"os\"}],\"size\": ' +
      system_disk_size.to_s +
      '},{\"type\": \"vg\", \"id\": \"os\", \"volumes\": [{\"mount\": \"/\", \"type\": \"lv\", \"name\": \"root\", \"size\": ' +
      system_disk_size.to_s +
      '},  {\"mount\": \"swap\", \"type\": \"lv\", \"name\": \"swap\", \"size\": '+
      swap_size.to_s +
      '}]}, {\"type\": \"disk\", \"id\": \"' + cinder_disk_path + '\", \"volumes\":  [{\"type\": \"mbr\"}, {\"size\": ' +
      cinder_disk_size.to_s +
      ', \"type\": \"pv\", \"vg\": \"cinder-volumes\"}], \"size\": ' +
      cinder_disk_size.to_s + '}]"'
  
        
    cobbler_ks_meta={"ks_spaces"=>ks_spaces,"mco_host"=>master_ip}

    result['ks_meta'] = result['ks_meta'].update(cobbler_ks_meta)
    puppet_network_data = [
        {"name" => 'public', 'ip'=>ip, "dev" => public_iface, 'netmask' => "255.255.255.0", "gateway" => default_gateway },
        {"name" => ['management','storage'], 'ip'=>"#{internal_net_prefix.to_s}.#{l_octet}", "dev" => public_iface, 'netmask' => "255.255.255.0"},
        {"name" => 'fixed', "dev" => private_iface},
    ]
    result['network_data'] = puppet_network_data
#    puts result.to_yaml
    newyaml['nodes'].push(result)
end

   newyaml['attributes']['dns_nameservers'] = master_ip
   newyaml['attributes']['libvirt_type'] = 'kvm'
   newyaml['attributes']['public_vip'] = '172.18.94.46' 
   newyaml['attributes']['management_vip'] = '10.107.2.254' 
   newyaml['attributes']['floating_network_range'] = '172.18.94.48/28' 
   newyaml['attributes']['fixed_network_range'] = '10.107.2.0/24' 
   newyaml['attributes']['base_syslog']['syslog_server'] = master_ip

puts newyaml.to_yaml

