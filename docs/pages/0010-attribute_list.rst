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

**FUEL way:** not used, passed directly to controller class {vlan_start=>$vlan_start}

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

**OSNF way:** use to determine primary controller and primary swift_proxy ::

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

