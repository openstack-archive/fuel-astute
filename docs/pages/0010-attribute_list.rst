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

**Description:** Array of hashes of controllers hostnames and IP addresses for Swift

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


