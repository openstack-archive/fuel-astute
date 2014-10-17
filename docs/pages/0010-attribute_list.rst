Attributes list
---------------

$controller_internal_addresses
------------------------------


**Type:**       Array of hashes

**Scheme:**     [<hostname1>=>IP1,<hostname2>=>IP2 ... ]

**Description:** Array of hashes of controllers  hostnames and internal IP addresses

**FUEL way:**   nodes_to_hash($controllers,'name','internal_address')

**OSNF way:**   parsejson($ctrl_management_addresses)

**Generation**: :: 

 /home/vvk/git/astute/lib/astute/deployment_engine.rb:112:
 112 attrs['ctrl_management_addresses'] = ctrl_manag_addrs

 /home/vvk/git/astute/lib/astute/deployment_engine.rb:
   81        # TODO(mihgen): we should report error back if there are not enough metadata passed
   82        ctrl_nodes = attrs['controller_nodes']
   83:       ctrl_manag_addrs = {}
   84        ctrl_public_addrs = {}
   85        ctrl_storage_addrs = {}
   ..
   87          # current puppet modules require `hostname -s`
   88          hostname = n['fqdn'].split(/\./)[0]
   89:         ctrl_manag_addrs.merge!({hostname =>
   90                     n['network_data'].select {|nd| nd['name'] == 'management'}
   [0]['ip'].split(/\//)[0]})




YAML fields: ::

 interfaces:
  - name: management
    ip: 192.168.6.5/24
    vlan: 125
    dev: eth0
    netmask: 255.255.255.0
    brd: 192.168.6.255
    gateway: 192.168.6.1

$controller_public_addresses
----------------------------


**Type:**       Array of hashes

**Scheme:**     [<hostname1>=>IP1,<hostname2>=>IP2 ... ]

**Description:** Array of hashes of controllers hostnames and public IP addresses

**FUEL way:**   nodes_to_hash($controllers,'name','public_address')

**OSNF way:**   parsejson($ctrl_public_addresses)

**Generation**: :: 

 /home/vvk/git/astute/lib/astute/deployment_engine.rb:
 111:       attrs['ctrl_public_addresses'] = ctrl_public_addrs

 /home/vvk/git/astute/lib/astute/deployment_engine.rb:
   81        # TODO(mihgen): we should report error back if there are not enough metadata passed
   82        ctrl_nodes = attrs['controller_nodes']
   83:       ctrl_manag_addrs = {}
   84        ctrl_public_addrs = {}
   85        ctrl_storage_addrs = {}
   ..
   87          # current puppet modules require `hostname -s`
   88          hostname = n['fqdn'].split(/\./)[0]
   89:         ctrl_public_addrs.merge!({hostname =>
   90                     n['network_data'].select {|nd| nd['name'] == 'public'}
   [0]['ip'].split(/\//)[0]})




YAML fields: ::

 interfaces:
  - ** name: public **
    ** ip: 192.168.6.5/24 **
    vlan: 125
    dev: eth0
    netmask: 255.255.255.0
    brd: 192.168.6.255
    gateway: 192.168.6.1


$controller_storage_addresses
-----------------------------


**Type:**       Array of hashes

**Scheme:**     [<hostname1>=>IP1,<hostname2>=>IP2 ... ]

**Description:** Array of hashes of controllers hostnames and IP addresses for Swift.

**FUEL way:**   **NOT USED**

**OSNF way:**   parsejson($ctrl_storage_addresses)

**Generation**: :: 

 /home/vvk/git/astute/lib/astute/deployment_engine.rb:
 113:       attrs['ctrl_storage_addresses'] = ctrl_storage_addrs

 /home/vvk/git/astute/lib/astute/deployment_engine.rb:
   81        # TODO(mihgen): we should report error back if there are not enough metadata passed
   82        ctrl_nodes = attrs['controller_nodes']
   83:       ctrl_manag_addrs = {}
   84        ctrl_public_addrs = {}
   85        ctrl_storage_addrs = {}
   ..
   87          # current puppet modules require `hostname -s`
   88          hostname = n['fqdn'].split(/\./)[0]
   89:         ctrl_storage_addrs.merge!({hostname =>
   90                     n['network_data'].select {|nd| nd['name'] == 'storage'}
   [0]['ip'].split(/\//)[0]})




YAML fields: ::

 interfaces:
  - ** name: storage **
    ** ip: 192.168.6.5/24 **
    vlan: 125
    dev: eth0
    netmask: 255.255.255.0
    brd: 192.168.6.255
    gateway: 192.168.6.1

$controller_hostnames
---------------------

**Type:** Array of strings

**Description:** Array of hostnames of controllers

**FUEL way:** keys($controller_internal_addresses)

**OSNF way:** keys($controller_internal_addresses)

**Generation:** derived from $controller_internal_addresses

$controller_nodes
-----------------

**Type:** Array of strings

**Description:** Array of internal IPs of controllers

**FUEL way:** ** NOT USED **

**OSNF way:** $controller_nodes = values($controller_internal_addresses)

**Generation:** derived from $controller_internal_addresses

$auto_assign_floating_ip
-----------------------

**Type:** Boolean

**Description:** Floating IP association boolean

**FUEL way:** simple setting

**OSNF way:** string to boolean convertation to $bool_auto_assign_floating_ip

YAML ::

auto_assign_floating_ip: false

$create_networks
----------------

**Type:** Boolean

**Description:** Whether network manager should create networks

**FUEL way:** simple setting

**OSNF way:** simple setting

**Generation:** Always *true*

$fixed_range
------------

**Type:** String with CIDR

**Description:** Fixed ip addresses range

**FUEL way:** Simple setting

**OSNF way:** Not used

$fixed_network_range
------------

**Type:** String with CIDR

**Description:** Fixed ip addresses range

**FUEL way:** Not used

**OSNF way:** Simple setting

YAML ::

fixed_network_range: 10.0.6.0/24

$network_config
---------------

**Type**: Hash

**Scheme**: Depends on Network Manager used by nova-network

**Description**: hash of parameters passed for Network manager configuration

**FUEL way:** not used, passed directly to controller class as {vlan_start=>$vlan_start}

**OSNF way:** {vlan_start=>$vlan_start}

$vlan_start
-----------

**Type**: integer or string with integer

**Description**: starting vlan for fixed networks with VlanManager

**FUEL way:** simple setting

**OSNF way:** ::

/home/vvk/git/product/nailgun/nailgun/task/task.py:
  161          if cluster_attrs['network_manager'] == 'VlanManager':
  162              cluster_attrs['num_networks'] = fixed_net.amount
  163:             cluster_attrs['vlan_start'] = fixed_net.vlan_start
  164              cls.__add_vlan_interfaces(nodes_with_attrs)

YAML ::

vlan_start = 300

$external_ipinfo
----------------

**NOT USED**

$multi_host
-----------

**Type:** Boolean

**Description:** Whether deployment is multi_host

**FUEL way:** always *true* for multi_host deployments

**OSNF way:** always *true* for multi_host deployments

$quantum
--------

**Type:** Boolean

**Description:** Whether deployment uses Quantum

**FUEL way:** always *true* except singlenode scenario

**OSNF way:** always *false*

$manage_volumes
---------------

**Type:** Boolean

**Description:** Whether create cinder volume group during deployment

**FUEL way:** always *true*

**OSNF way:** always *false*

$glance_backend
---------------

**Type:** enum of strings

**Scheme:** "file|swift"

**Description:** Which backend for glance to use

**FUEL way:** swift for swift scenario, file for minimal, simple and single

**OSNF way:** swift for HA scenario, file for simple

$master_hostname
----------------

**Type:** String

**Description:** which host to use as primary controller

**FUEL way:** **NOT USED** 

**OSNF way:** used to determine primary controller and primary swift_proxy ::

cluster_ha.pp

if $::hostname == $master_hostname {
  $primary_proxy = true
  $primary_controller = true
} else {
  $primary_proxy = false
  $primary_controller = false
}

deployment_engine.rb

      attrs['master_hostname'] = ctrl_nodes[0]['fqdn'].split(/\./)[0]


$network_manager
----------------

**Type:** String

**Description:** which network manager to use for nova-network

**FUEL way:** simple setting. *deprecated as quantum is used instead.*. always set to *'nova.network.manager.FlatDHCPManager'* 

**OSNF way:** simple setting

YAML ::

network_manager: FlatDHCPManager

$nova_hash
----------

**Type:** Hash

**Description:** hash of nova parameters

**FUEL way:** **DOES NOT EXIST**

**OSNF way:** parsejson($nova)

YAML ::

  nova:
    db_password: vlY5FhkA
    user_password: UeVjkUxq


$cinder_hash
----------

**Type:** Hash

**Description:** hash of cinder parameters

**FUEL way:** **DOES NOT EXIST**

**OSNF way:** parsejson($cinder)

YAML ::

  cinder:
    db_password: vlY5FhkA
    user_password: UeVjkUxq


$mysql_hash
----------

**Type:** Hash

**Description:** hash of mysqk parameters

**FUEL way:** **DOES NOT EXIST**

**OSNF way:** parsejson($mysql)

YAML ::

  mysql:
    root_password: X1HWFL2i

$rabbit_hash
----------

**Type:** Hash

**Description:** hash of rabbit parameters

**FUEL way:** **DOES NOT EXIST**

**OSNF way:** parsejson($rabbit)

YAML ::

  rabbit:
    password: UeVjkUxq

$keystone_hash
----------

**Type:** Hash

**Description:** hash of keystone parameters

**FUEL way:** **DOES NOT EXIST**

**OSNF way:** parsejson($keystone)

YAML ::

  keystone:
    db_password: XjwwZsBU
    admin_token: giVDBp05

$swift_hash
----------

**Type:** Hash

**Description:** hash of cinder parameters

**FUEL way:** **DOES NOT EXIST**

**OSNF way:** parsejson($cinder)

YAML ::

  swift:
    user_password: ODwuK9ij

$access_hash
----------

**Type:** Hash

**Description:** hash of admin user parameters

**FUEL way:** **DOES NOT EXIST**

**OSNF way:** parsejson($access)

YAML ::

  access:
    password: admin
    user: admin
    tenant: admin
    email: admin@example.org

$floating_hash
--------------

**Type:** Hash

**Scheme:** array of hashes (only keys used)

**Description:** array of floating IPs created during deployment

**FUEL way:** **DOES NOT EXIST**

**OSNF way:** simple setting from *floating_network_range*

YAML ::

floating_network_range:
  - 240.0.12.10
  - 240.0.12.11



$primary_controller
--------------

**Type:** boolean

**Description:** if current node is primary controller

**FUEL way:** ::

if $node[0]['role'] == 'primary-controller' {
  $primary_proxy = true
} else {
  $primary_proxy = false
}

**OSNF way:** :: 

if $::hostname == $master_hostname {
  $primary_proxy = true
  $primary_controller = true
} else {
  $primary_proxy = false
  $primary_controller = false
}


$primary_proxy
--------------

**Type:** boolean

**Description:** if current node is primary proxy

**FUEL way:** ::

if $node[0]['role'] == 'primary-proxy' {
  $primary_proxy = true
} else {
  $primary_proxy = false
}

**OSNF way:** :: 

if $::hostname == $master_hostname {
  $primary_proxy = true
  $primary_controller = true
} else {
  $primary_proxy = false
  $primary_controller = false
}


$base_syslog_hash
-----------------

**Type:** Hash

**Description:** hash for base syslog server config.

**FUEL way:** **DOES NOT EXIST**

**OSNF way:** $base_syslog_hash  = parsejson($base_syslog)

YAML ::

syslog:
    syslog_port: '514'
    syslog_transport: udp
    syslog_server: ''



$syslog_hash
-----------------

**Type:** Hash

**Description:** hash for additional syslog server config.

**FUEL way:** **DOES NOT EXIST**

**OSNF way:** $syslog_hash  = parsejson($syslog)

YAML ::

  base_syslog:
    syslog_port: '514'
    syslog_server: 10.20.0.2

$rservers
---------

**Type:** Array

**Description:** array of hostnames/IPs of remote syslog servers.

**FUEL way:** **DOES NOT EXIST**

**OSNF way:** ::

if $syslog_hash['syslog_server'] != "" and $syslog_hash['syslog_port'] != "" and $syslog_hash['syslog_transport'] != "" {
  $rservers = [$base_syslog_rserver, $syslog_rserver]
}
else {
  $rservers = [$base_syslog_rserver]
}

$rabbit_user
------------

**Type:** String

**Description:** rabbitmq username

**FUEL way:** simple setting.

**OSNF way:** simple setting. set to *nova*

$quantum_user_password
----------------------

**Type:** String

**Description:** quantum user password

**FUEL way:** simple setting

**OSNF way:** simple setting.

$quantum_user_password
----------------------

**Type:** String

**Description:** quantum user password

**FUEL way:** simple setting

**OSNF way:** simple setting.

$quantum_db_user
----------------------

**Type:** String

**Description:** quantum db user

**FUEL way:** simple setting

**OSNF way:** simple setting.

$quantum_db_password
----------------------

**Type:** String

**Description:** quantum db password

**FUEL way:** simple setting

**OSNF way:** simple setting.

$quantum_db_dbname
----------------------

**Type:** String

**Description:** quantum db name

**FUEL way:** simple setting

**OSNF way:** simple setting

$tenant_network_type
--------------------

**Type:** enum

**Scheme:** 'gre|vlan'

**Description:** which type of network segmentation to use in Quantum

**FUEL way:** simple setting

**OSNF way:** simple setting

$segment_range
--------------------

**Type:** range of integers 

**Scheme:** '<int>-<int>'

**Description:** range of vlans/"gre tunnels IDs" to use in network segmentation

**FUEL way:** simple setting

**OSNF way:** simple setting


$quantum_host
-------------

**Type:** String

**Description:** Quantum host for compute nova.conf

**FUEL way:** equals to $internal_virtual_ip

**OSNF way:** equals to $management_vip

$mirror_type
------------

**Type:** enum

**Description:** 'default|custom'

**FUEL way:** simple setting

**OSNF way:** simple setting. **OUTDATED: defaults to** *'external'* 

$quantum_sql_connection
-----------------------

**Type:** SQLAlchemy connection string

**Description:** sql connection string passed to compute node ovs quantum plugin

**FUEL way:** ::

$quantum_sql_connection  = "mysql://${quantum_db_user}:${quantum_db_password}@${quantum_host}/${quantum_db_dbname}"

**OSNF way:** ::

$quantum_sql_connection  = "mysql://${quantum_db_user}:${quantum_db_password}@${quantum_host}/${quantum_db_dbname}"

$verbose
--------

**Type:** Boolean

**Description:** verbosity setting

**FUEL way:** simple setting. defaults to *true*

**OSNF way:** simple setting. defaults to *true*

$debug
--------

**Type:** Boolean

**Description:** debug setting

**FUEL way:** simple setting. defaults to *false*

**OSNF way:** **DOES NOT EXIST**


$internal_address
-----------------

**Type:** IP

**Description:** internal IP of the node

**FUEL way:** ::

$internal_address = $node[0]['internal_address']

**OSNF way:** ::

nailyfact.rb

    node_network_data.each do |iface|
      device = if iface['vlan'] && iface['vlan'] > 0
        [iface['dev'], iface['vlan']].join('.')
      else
        iface['dev']
      end
      metadata["#{iface['name']}_interface"] = device
      if iface['ip']
        metadata["#{iface['name']}_address"] = iface['ip'].split('/')[0]
      end
    end

    # internal_address is required for HA..
    ** metadata['internal_address'] = node['network_data'].select{|nd| nd['name'] == 'management' }[0]['ip'].split('/')[0]**


** The following is duplicating garbage from deployment_engine.rb to fill *nodes* hash. Needs to be rewritten **
      attrs['nodes'] = ctrl_nodes.map do |n|
        {
          'internal_address'     => n['network_data'].select {|nd| nd['name'] == 'management'}[0]['ip'].split(/\//)[0]         
        }

YAML ::

 network_data:
  - ** name: management **
    ** ip: 192.168.6.2/24 **
    vlan: 125
    dev: eth0
    netmask: 255.255.255.0
    brd: 192.168.6.255
    gateway: 192.168.6.1

$public_address
-----------------

**Type:** IP

**Description:** public IP of the node

**FUEL way:** ::

$public_address = $node[0]['public_address']

**OSNF way:** ::

nailyfact.rb:


    node_network_data.each do |iface|
      device = if iface['vlan'] && iface['vlan'] > 0
        [iface['dev'], iface['vlan']].join('.')
      else
        iface['dev']
      end
      metadata["#{iface['name']}_interface"] = device 
      if iface['ip']
   **     metadata["#{iface['name']}_address"] = iface['ip'].split('/')[0] **
      end
    end

    # internal_address is required for HA..
    metadata['internal_address'] = node['network_data'].select{|nd| nd['name'] == 'management' }[0]['ip'].split('/')[0]

** The following is duplicating garbage from deployment_engine.rb to fill *nodes* hash. Needs to be rewritten **
      attrs['nodes'] = ctrl_nodes.map do |n|
        {
          'public_address'       => n['network_data'].select {|nd| nd['name'] == 'public'}[0]['ip'].split(/\//)[0],        
        }

YAML ::

 network_data:
  - ** name: public **
    ** ip: 192.168.6.2/24 **
    vlan: 126
    dev: eth0
    netmask: 255.255.255.0
    brd: 192.168.6.255
    gateway: 192.168.6.1


$public_interface
-----------------

**Type:** String

**Description:** Public interface name

**FUEL way:** Simple setting.

**OSNF way:**

node_network_data.each do |iface|
      device = if iface['vlan'] && iface['vlan'] > 0
        [iface['dev'], iface['vlan']].join('.')
      else
        iface['dev']
      end
      ** metadata["#{iface['name']}_interface"] = device **
      if iface['ip']
        metadata["#{iface['name']}_address"] = iface['ip'].split('/')[0] **
      end
    end

YAML :: 

network_data:
  - ** name: public **
    ip: 192.168.6.2/24
    **vlan: 126**
    **dev: eth0**
    netmask: 255.255.255.0
    brd: 192.168.6.255
    gateway: 192.168.6.1

$internal_interface
-----------------

**Type:** String

**Description:** internal interface name

**FUEL way:** Simple setting.

**OSNF way:** **DOES NOT EXIST**.

YAML :: 


$management_interface
-----------------

**Type:** String

**Description:** internal interface name, duplicates $internal_interface in FUEL

**FUEL way:** **DOES NOT EXIST**.

**OSNF way:** ::

node_network_data.each do |iface|
      device = if iface['vlan'] && iface['vlan'] > 0
        [iface['dev'], iface['vlan']].join('.')
      else
        iface['dev']
      end
      ** metadata["#{iface['name']}_interface"] = device **
      if iface['ip']
        metadata["#{iface['name']}_address"] = iface['ip'].split('/')[0] **
      end
    end

$private_interface
------------------

**Type:** String

**Description:** private interface name

**FUEL way:** simple setting

**OSNF way:** **DOES NOT EXIST**


$fixed_interface
------------------

**Type:** String

**Description:** private interface name, duplicates $private_interface in FUEL

**FUEL way:** **DOES NOT EXIST**

**OSNF way:** :: 

node_network_data.each do |iface|
      device = if iface['vlan'] && iface['vlan'] > 0
        [iface['dev'], iface['vlan']].join('.')
      else
        iface['dev']
      end
      ** metadata["#{iface['name']}_interface"] = device **
      if iface['ip']
        metadata["#{iface['name']}_address"] = iface['ip'].split('/')[0] **
      end
    end

$management_vip
---------------

**Type:** IP address

**Description:** Internal virtual IP. Duplicate of $internal_virtual_ip in FUEL

**FUEL way:** **DOES NOT EXIST**

**OSNF way:** ::

/home/vvk/git/product/nailgun/nailgun/task/task.py:
  166          if task.cluster.mode == 'ha':
  167              logger.info("HA mode chosen, creating VIP addresses for it..")
  168:             cluster_attrs['management_vip'] = netmanager.assign_vip(
  169                  cluster_id, "management")
  170              cluster_attrs['public_vip'] = netmanager.assign_vip(


$public_vip
---------------

**Type:** IP address

**Description:** Internal virtual IP. Duplicate of $public_virtual_ip in FUEL

**FUEL way:** **DOES NOT EXIST**

**OSNF way:** ::

/home/vvk/git/product/nailgun/nailgun/task/task.py:
  168              cluster_attrs['management_vip'] = netmanager.assign_vip(
  169                  cluster_id, "management")
  170:             cluster_attrs['public_vip'] = netmanager.assign_vip(
  171                  cluster_id, "public")
  172  

$uid
----

**Type:** Unsigned Integer

**Description::** Node UID. (also used for swift zone)

**FUEL way:** **DOES NOT EXIST**

**OSNF way:** simple setting

YAML ::

uid: 22

$deployment_id
--------------

**Type:** Unsigned integer

**Description:** deployment id used to separate deployments

**FUEL way:** simple setting

**OSNF way:** simple setting

YAML::

deployment_id: 29

$storage_address
----------------

**Type:** IP

**Description:** IP address configured on node storage interface

**FUEL way:** **DOES NOT EXIST**

**OSNF way:** ::

    node_network_data.each do |iface|
      device = if iface['vlan'] && iface['vlan'] > 0
        [iface['dev'], iface['vlan']].join('.')
      else
        iface['dev']
      end
      metadata["#{iface['name']}_interface"] = device
      if iface['ip']
      **  metadata["#{iface['name']}_address"] = iface['ip'].split('/')[0] **
      end
    end

YAML::

 - **name: storage**
   ** ip: 172.16.6.5/24 **
    vlan: 126
    dev: eth0
    netmask: 255.255.255.0
    brd: 172.16.6.255
    gateway: 172.16.6.1

$nodes
------

**Type:** Hash

**Description:** Hash of node attributes

**FUEL way:** simple setting

**OSNF way:** 

**this is really garbaged. osnailyfacter adds only controllers to *nodes* hash, thus cluster_ha.pp calls ring_devices with storages set to 'all'. This should be fixed ASAP **

::

      attrs['nodes'] = ctrl_nodes.map do |n|
        {
          'name'                 => n['fqdn'].split(/\./)[0],
          'role'                 => 'controller',
          'internal_address'     => n['network_data'].select {|nd| nd['name'] == 'management'}[0]['ip'].split(/\//)[0],
          'public_address'       => n['network_data'].select {|nd| nd['name'] == 'public'}[0]['ip'].split(/\//)[0],
          'mountpoints'          => "1 1\n2 2",
          'zone'                 => n['id'],
          'storage_local_net_ip' => n['network_data'].select {|nd| nd['name'] == 'storage'}[0]['ip'].split(/\//)[0],
        }
      end
      attrs['nodes'].first['role'] = 'primary-controller'

$start_guests_on_host_boot
--------------------------

**Type:** boolean

**Description:** obvious

**FUEL way:** **DOES NOT EXIST**

**OSNF way:** simple setting

YAML ::

start_guests_on_host_boot: true

$use_cow_images
---------------

**Type:** boolean

**Description:** obvious

**FUEL way:** **DOES NOT EXIST**

**OSNF way:** simple setting

YAML ::

use_cow_images: true

compute_scheduler_driver
------------------------

**Type:** boolean

**Description:** obvious

**FUEL way:** **DOES NOT EXIST**

**OSNF way:** simple setting

YAML ::

compute_scheduler_driver: true


$controller_node_address
-------------------------

**Type:** IP

**Description:** Controller internal address. Used in non-HA mode. Duplicate of $controller_internal_address in FUEL

**FUEL way:** **DOES NOT EXIST**

**OSNF way:** ::

      ctrl_nodes.each do |n|
        ** ctrl_management_ips << n['network_data'].select {|nd| nd['name'] == 'management'}[0]['ip'] **
        ctrl_public_ips << n['network_data'].select {|nd| nd['name'] == 'public'}[0]['ip']
      end

      attrs['controller_node_address'] = ctrl_management_ips[0].split('/')[0]
      attrs['controller_node_public'] = ctrl_public_ips[0].split('/')[0]

$controller_node_public
-------------------------

**Type:** IP

**Description:** Controller public address. Used in non-HA mode. Duplicate of $controller_public_address in FUEL

**FUEL way:** **DOES NOT EXIST**

**OSNF way:** ::

      ctrl_nodes.each do |n|
        ctrl_management_ips << n['network_data'].select {|nd| nd['name'] == 'management'}[0]['ip'] 
        ** ctrl_public_ips << n['network_data'].select {|nd| nd['name'] == 'public'}[0]['ip'] **
      end

      attrs['controller_node_address'] = ctrl_management_ips[0].split('/')[0]
      ** attrs['controller_node_public'] = ctrl_public_ips[0].split('/')[0] **

$public_br
----------

**Type:** String

**Description:** Name of public bridge to which attach $public_interface. Used only in quantum mode

**FUEL way:** simple setting

**OSNF way:** does not exist

$internal_br
----------

**Type:** String

**Description:** Name of public bridge to which attach $public_interface. Used only in quantum mode

**FUEL way:** simple setting

**OSNF way:** does not exist

$default_gateway
----------------

**Type:** IP

**Description:** default gateway for the node

**FUEL way:** simple setting

**OSNF way:** DOES NOT EXIST

$dns_nameservers
----------------

**Type:** Array of  IPs

**Description:** DNS nameservers for the node

**FUEL way:** simple setting

**OSNF way:** DOES NOT EXIST

$internal_netmask
-----------------

**Type:** Network mask

**Description:** network mask for internal interface/bridge configuration

**FUEL way:** simple setting

**OSNF way:** ** DOES NOT EXIST **

$public_netmask
-----------------

**Type:** Network mask

**Description:** network mask for public interface/bridge configuration

**FUEL way:** simple setting

**OSNF way:** ** DOES NOT EXIST **

$node
-----

**Type:** Hash

**Description:** Hash of node attributes

**FUEL way:** ::

$node = filter_nodes($nodes,'name',$::hostname)

**OSNF way:** **DOES NOT EXIST*

$ha_provider
------------

**Type:** enum of strings

**Description:** 'generic|pacemaker'

**FUEL way:** pacemaker for HA, not set (defaults to *generic*) in non-HA

**OSNF way:** **DOES NOT EXIST**

$use_unicast_corosync
---------------------

**Type:** Boolean

**Description:** which type of corosync configuration to use. True for unicast, false for multicast

**FUEL way:** simple setting. *unicast* by default

**OSNF way:** **DOES NOT EXIST**

$nagios
-------

**Type:** Boolean

**Description:** whether to enable nagios clients

**FUEL way:** simple setting. defaults to *true*

**OSNF way:** **DOES NOT EXIST**

$nagios_master
--------------

**Type:** String

**Description:** nagios master server

**FUEL way:** simple setting

**OSNF way:** **DOES NOT EXIST**


$proj_name
--------------

**Type:** String

**Description:** nagios project name

**FUEL way:** simple setting

**OSNF way:** **DOES NOT EXIST**

$quantum_netnode_on_cnt
-----------------------

**Type:** Boolean

**Description:** whether to install quantum nodes on controller

**FUEL way:** simple setting. defaults to *true*

**OSNF way:** **DOES NOT EXIST**

$quantum_gre_bind_addr
----------------------
 
**Type:** String

**Description:** which interface to use endpoint for Quantum GRE interface

**FUEL way:** simple setting. defaults to *internal_interface*

**OSNF way:** **DOES NOT EXIST**

$cinder_nodes
-------------

**Type:** Array of strings

**Description:** Specify nodes hostnames, IPs or role names on which to deploy cinder volumes services

**FUEL way:** simple setting. ::

$cinder_nodes          = ['controller']

**OSNF way:** **DOES NOT EXIST**

$cinder_iscsi_bind_addr
-----------------------

**Type:** IP

**Description:** IP address on which to bind iscsi target on cinder volume nodes. Partially duplicated by $storage_address.

**FUEL way:** ::

$cinder_iscsi_bind_addr = $internal_address

$nv_physical_volume
-------------------

**Type:** Array

**Description:** array of block devices passed to LVM manifests during deployment stage to create cinder volume VGs. Can be empty in case VG is created during provisioning stage.

**FUEL way:** ::

$nv_physical_volume     = ['/dev/sdz', '/dev/sdy', '/dev/sdx']

**OSNF way:** **DOES NOT EXIST**

$is_cinder_node
---------------

**Type:** Boolean

**Description:** whether current node is cinder-volume node.

**FUEL-way:** ::

if ($cinder) {
  if (member($cinder_nodes,'all')) {
    $is_cinder_node = true
  } elsif (member($cinder_nodes,$::hostname)) {
    $is_cinder_node = true
  } elsif (member($cinder_nodes,$internal_address)) {
    $is_cinder_node = true
  } elsif ($node[0]['role'] =~ /controller/ ) {
    $is_cinder_node = member($cinder_nodes,'controller')
  } else {
    $is_cinder_node = member($cinder_nodes,$node[0]['role'])
  }
} else {
  $is_cinder_node = false
}

**OSNF way:** **DOES NOT EXIST**

$swift_loopback
---------------

**Type:** String enum

**Description:** 'loopback|false'. Whether to use loopbacks for swift partitions

**FUEL way:** simple setting. defaults to *loopback*

**OSNF way:** DOES NOT EXIST


$swift_local_net_ip
-------------------

**Type:** IP

**Description:** IP address on which to bind swift storage node on cinder volume nodes. Partially duplicated by $storage_address.

**FUEL way:** ::

$swift_local_net_ip      = $internal_address

**OSNF way:** **DOES NOT EXIST**

$swift_proxies
--------------

**Type:** Array of IPs

**Description:** Array of swift proxies


**FUEL way:** ::

*FULL*

$swift_proxy_nodes = merge_arrays(filter_nodes($nodes,'role','primary-swift-proxy'),filter_nodes($nodes,'role','swift-proxy'))
$swift_proxies = nodes_to_hash($swift_proxy_nodes,'name','internal_address')

*COMPACT*

$swift_proxies = $controller_internal_addresses

**OSNF way:** **DOES NOT EXIST**

$master_swift_proxy_nodes
-------------------------

**Type:** Array of IPs

**Description:** Array of swift primary proxies

**FUEL way:** ::

*COMPACT*

$master_swift_proxy_nodes = filter_nodes($nodes,'role','primary-controller')
$master_swift_proxy_ip = $master_swift_proxy_nodes[0]['internal_address']

*FULL*

$master_swift_proxy_nodes = filter_nodes($nodes,'role','primary-swift-proxy')
$master_swift_proxy_ip = $master_swift_proxy_nodes[0]['internal_address']

**OSNF way:** **DOES NOT EXIST**


$use_syslog
-----------

**Type:** Boolean

**Description:** Whether to use syslog for logging.

**FUEL way:** simple setting. set to *true* by default

**OSNF way:** **DOES NOT EXIST**

$syslog_log_level
-----------------
**Type:** String

**Description:** Default log level would have been used, if non verbose and non debug

**FUEL way:** simple setting ::

$syslog_log_level             = 'ERROR'

**OSNF way:** **DOES NOT EXIST**

$syslog_log_facility_glance|cinder|quantum|nova|keystone
---------------------------

**FUEL way:** ::

$syslog_log_facility_glance   = 'LOCAL2'
$syslog_log_facility_cinder   = 'LOCAL3'
$syslog_log_facility_quantum  = 'LOCAL4'
$syslog_log_facility_nova     = 'LOCAL6'
$syslog_log_facility_keystone = 'LOCAL7'

**OSNF way:** **DOES NOT EXIST**

$enable_test_repo
-----------------

**Type:** Boolean

**Description:** whether to attach test repo. used in tests

**FUEL way:** simple setting. defaults to false

**OSNF way:** **DOES NOT EXIST**



$repo_proxy
-----------

**Type:** String

**Description:** address of repository proxy.

**FUEL way:** ::

$repo_proxy = undef

**OSNF way:** **DOES NOT EXIST**

$ntp_servers
------------

**Type:** Array of IPs/hostnames

**Description:** Array of ntp servers

**FUEL way:** ::

$ntp_servers = ['pool.ntp.org']

**OSNF way:** **DOES NOT EXIST**

$horizon_use_ssl
----------------

**Type:** enum 

**Description:** whether and how to use horizon SSL. 'false|"exist"|"default"|"custom"'

false: normal mode with no encryption
'default': uses keys supplied with the ssl module package
'exist': assumes that the keys (domain name based certificate) are provisioned in advance
'custom': require fileserver static mount point [ssl_certs] and hostname based certificate existence

**FUEL way: ::

$horizon_use_ssl = false

**OSNF way:** **DOES NOT EXIST**

$vips
-----

**Type:** Hash

**Description:** hash of parameters of virtual IP addresses

**FUEL way:** ::
$vips = { # Do not convert to ARRAY, It can't work in 2.7
  public => {
    nic    => $public_int,
    ip     => $public_virtual_ip,
  },
  management => {
    nic    => $internal_int,
    ip     => $internal_virtual_ip,
  },
}

**OSNF way:** :: 

*exists in consolidated code*

$vips = { # Do not convert to ARRAY, It can't work in 2.7
  public => {
    nic    => $public_int,
    ip     => $public_virtual_ip,
  },
  management => {
    nic    => $internal_int,
    ip     => $internal_virtual_ip,
  },
}

$vip_keys
---------

**Type:** array of strings

**Description:** array of names for virtual ip resources

**FUEL way:** ::

$vip_keys = keys($vips)

**OSNF way:** the same in consolidated (fuel-777 branch) code


$nova_rate_limits
-----------------

**Type:** Hash

**Description:** hash of nova rate limits

**FUEL way:** ::

$nova_rate_limits = {
  'POST' => 1000,
  'POST_SERVERS' => 1000,
  'PUT' => 1000, 'GET' => 1000,
  'DELETE' => 1000
}

**OSNF way:** **DOES NOT EXIST**

$cinder_rate_limits
-----------------

**Type:** Hash

**Description:** hash of cinder rate limits

**FUEL way:** ::

$cinder_rate_limits = {
  'POST' => 1000,
  'POST_SERVERS' => 1000,
  'PUT' => 1000, 'GET' => 1000,
  'DELETE' => 1000
}

**OSNF way:** **DOES NOT EXIST**
