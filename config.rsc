# ============================================================
# RouterOS 7.x - Dual WAN PCC Load Balancing with Failover
# ============================================================
#
# This configuration provides Per-Connection Classifier (PCC) load
# balancing across two WAN connections with automatic failover.
#
# WHAT IS PCC:
# PCC distributes connections (not packets) across multiple WANs.
# Each connection is hashed and assigned to one WAN link, ensuring
# that packets from the same connection always use the same path.
# This maintains session stability while distributing load.
#
# TOPOLOGY:
# WAN1: ether1 → 192.168.2.100/24 (gateway 192.168.2.1)
# WAN2: ether2 → 192.168.0.100/24 (gateway 192.168.0.1)
# LAN:  bridge2 (ether4 + ether5) → 192.168.10.1/24
#
# FEATURES:
# - 50/50 connection distribution between WANs
# - Gateway health monitoring with automatic failover
# - Independent routing tables for each WAN
# - Full firewall protection
# - NAT for both WAN interfaces
# ============================================================

# ============================================================
# INTERFACE BRIDGE CONFIGURATION
# ============================================================
# Creates a Layer-2 bridge to combine ether4 and ether5 into a
# single LAN interface. This simplifies PCC rules since all LAN
# traffic enters through one logical interface.
#
/interface bridge
add comment="LAN bridge" name=bridge2

# ============================================================
# DHCP POOL AND SERVER CONFIGURATION
# ============================================================
# Configures DHCP to automatically assign IP addresses to LAN clients.
# Pool: 192.168.10.100-250 (150 addresses available)
# Reserves .1-.99 for static assignments (servers, printers, etc.)
#
/ip pool
add name=lan-pool ranges=192.168.10.100-192.168.10.250

/ip dhcp-server
add address-pool=lan-pool interface=bridge2 lease-time=12h name=dhcp-lan

# ============================================================
# POLICY ROUTING TABLES
# ============================================================
# RouterOS 7 uses named routing tables for policy-based routing.
# Each WAN gets its own routing table with independent failover.
#
# to-wan1: Routes for connections marked to use WAN1
# to-wan2: Routes for connections marked to use WAN2
# main:    Default routing table (router's own traffic)
#
/routing table
add fib name=to-wan1
add fib name=to-wan2

# ============================================================
# BRIDGE PORTS - LAN INTERFACE MEMBERS
# ============================================================
# Adds ether4 and ether5 to the LAN bridge.
# All LAN devices connected to these ports are on the same network.
#
/interface bridge port
add bridge=bridge2 interface=ether4
add bridge=bridge2 interface=ether5

# ============================================================
# IP ADDRESS CONFIGURATION
# ============================================================
# Assigns static IP addresses to WAN and LAN interfaces.
# Replace WAN IPs and networks with your actual ISP assignments.
#
/ip address
add address=192.168.2.100/24 comment="WAN1 IP" interface=ether1 network=192.168.2.0
add address=192.168.0.100/24 comment="WAN2 IP" interface=ether2 network=192.168.0.0
add address=192.168.10.1/24 comment="LAN IP" interface=bridge2 network=192.168.10.0

# ============================================================
# DHCP SERVER NETWORK SETTINGS
# ============================================================
# Tells DHCP clients what gateway and DNS servers to use.
# Clients will use this router (192.168.10.1) as their gateway.
# Primary DNS: router itself (.1), Secondary: Cloudflare (1.1.1.1)
#
/ip dhcp-server network
add address=192.168.10.0/24 dns-server=192.168.10.1,1.1.1.1 gateway=192.168.10.1

# ============================================================
# DNS CONFIGURATION
# ============================================================
# Upstream DNS servers: Cloudflare (1.1.1.1) and Google (8.8.8.8)
# allow-remote-requests=yes: Allows LAN clients to use router as DNS
#
/ip dns
set allow-remote-requests=yes servers=1.1.1.1,8.8.8.8

# ============================================================
# ADDRESS LIST - PCC EXCLUSIONS
# ============================================================
# Defines private/local destinations that should NOT be load balanced.
# Traffic to these addresses bypasses PCC and uses direct routing.
# Prevents LAN-to-LAN traffic from being routed out WAN interfaces.
#
/ip firewall address-list
add address=0.0.0.0/8 comment=Invalid list=no-pcc
add address=10.0.0.0/8 comment=Private list=no-pcc
add address=127.0.0.0/8 comment=Loopback list=no-pcc
add address=169.254.0.0/16 comment="Link local" list=no-pcc
add address=172.16.0.0/12 comment=Private list=no-pcc
add address=192.168.0.0/16 comment=Private list=no-pcc
add address=224.0.0.0/4 comment=Multicast list=no-pcc

# ============================================================
# FIREWALL FILTER RULES
# ============================================================
# INPUT CHAIN: Controls access TO the router itself
# FORWARD CHAIN: Controls traffic THROUGH the router (LAN to WAN)
#
# Security model:
# - LAN clients can access everything
# - WAN cannot access router (management protection)
# - Only established connections and port forwards allowed from WAN
#

/ip firewall filter

# --- INPUT CHAIN RULES ---
# Allow established connections (responses to router's requests)
add action=accept chain=input comment="Accept established/related input" connection-state=established,related,untracked

# Drop malformed or invalid packets
add action=drop chain=input comment="Drop invalid input" connection-state=invalid

# Allow full access from LAN (management, DNS, DHCP, etc.)
add action=accept chain=input comment="Allow LAN access to router" in-interface=bridge2

# Allow ping from anywhere (useful for troubleshooting)
add action=accept chain=input comment="Allow ping" protocol=icmp

# Block all other WAN access (protects against unauthorized access)
add action=drop chain=input comment="Drop WAN1 access to router" in-interface=ether1
add action=drop chain=input comment="Drop WAN2 access to router" in-interface=ether2

# --- FORWARD CHAIN RULES ---
# Allow established connections (ongoing communications)
add action=accept chain=forward comment="Accept established/related forward" connection-state=established,related,untracked

# Drop invalid forwarded packets
add action=drop chain=forward comment="Drop invalid forward" connection-state=invalid

# Allow LAN to access internet via both WANs
add action=accept chain=forward comment="Allow LAN to WAN1" in-interface=bridge2 out-interface=ether1
add action=accept chain=forward comment="Allow LAN to WAN2" in-interface=bridge2 out-interface=ether2

# Only allow WAN→LAN if it's a port forward (dstnat rule)
add action=drop chain=forward comment="Drop unwanted WAN1 forward" connection-nat-state=!dstnat in-interface=ether1
add action=drop chain=forward comment="Drop unwanted WAN2 forward" connection-nat-state=!dstnat in-interface=ether2

# ============================================================
# MANGLE RULES - PCC LOAD BALANCING
# ============================================================
# Mangle rules modify packet marks to control routing decisions.
# PCC (Per Connection Classifier) uses these marks to distribute
# connections across multiple WANs while keeping each connection
# on the same path for its entire lifetime.
#
# HOW PCC WORKS:
# 1. Skip private/local destinations (no-pcc list)
# 2. Hash new connections using src/dst address+port
# 3. Assign connection mark (wan1-conn or wan2-conn)
# 4. Apply routing mark to force use of specific routing table
#
# HASH EXPLANATION:
# both-addresses-and-ports:2/0 means:
#   - Use source IP, dest IP, source port, dest port for hash
#   - Divide hash space into 2 buckets (0 and 1)
#   - This rule catches bucket 0 → WAN1 (50%)
#   - Next rule catches bucket 1 → WAN2 (50%)
#

/ip firewall mangle

# Skip PCC for traffic to private networks (stays on LAN)
add action=accept chain=prerouting comment="Skip PCC for local/private destinations" dst-address-list=no-pcc in-interface=bridge2

# PCC CLASSIFICATION: Assign connections to WAN1 or WAN2
# new connection-mark=no-mark ensures we only mark NEW connections
# dst-address-type=!local excludes traffic to router itself
add action=mark-connection chain=prerouting comment="PCC classify connections to WAN1" \
    connection-mark=no-mark connection-state=new dst-address-type=!local in-interface=bridge2 \
    new-connection-mark=wan1-conn per-connection-classifier=both-addresses-and-ports:2/0

add action=mark-connection chain=prerouting comment="PCC classify connections to WAN2" \
    connection-mark=no-mark connection-state=new dst-address-type=!local in-interface=bridge2 \
    new-connection-mark=wan2-conn per-connection-classifier=both-addresses-and-ports:2/1

# ROUTING MARKS: Force marked connections into policy routing tables
# passthrough=no stops processing here (optimization)
add action=mark-routing chain=prerouting comment="Route WAN1-marked traffic via to-wan1" \
    connection-mark=wan1-conn in-interface=bridge2 new-routing-mark=to-wan1 passthrough=no

add action=mark-routing chain=prerouting comment="Route WAN2-marked traffic via to-wan2" \
    connection-mark=wan2-conn in-interface=bridge2 new-routing-mark=to-wan2 passthrough=no

# ============================================================
# NAT (NETWORK ADDRESS TRANSLATION)
# ============================================================
# Masquerade rewrites source IP of outgoing packets to match
# the WAN interface IP, allowing private LAN IPs to access internet.
#
# Why separate rules per interface:
# - Ensures correct source IP for each WAN
# - Required for ISPs that filter by source address
# - Maintains proper return routing
#
/ip firewall nat
add action=masquerade chain=srcnat comment="NAT WAN1" out-interface=ether1
add action=masquerade chain=srcnat comment="NAT WAN2" out-interface=ether2

# ============================================================
# ROUTING - POLICY TABLES WITH FAILOVER
# ============================================================
# Each routing table contains default routes with different priorities.
# check-gateway=ping monitors gateway health via ICMP ping.
# If primary gateway becomes unreachable, backup route activates.
#
# DISTANCE VALUES:
# Lower distance = higher priority
# distance=1: Primary route (used first)
# distance=2: Backup route (used if primary fails)
#
# ROUTING TABLE STRATEGY:
# to-wan1 table: Prefers WAN1, falls back to WAN2
# to-wan2 table: Prefers WAN2, falls back to WAN1
# main table: Router's own traffic (DNS, NTP, updates)
#

/ip route

# --- TO-WAN1 TABLE ---
# Traffic marked for WAN1 uses these routes
add check-gateway=ping comment="to-wan1 primary via WAN1" \
    distance=1 dst-address=0.0.0.0/0 gateway=192.168.2.1 routing-table=to-wan1

add check-gateway=ping comment="to-wan1 backup via WAN2" \
    distance=2 dst-address=0.0.0.0/0 gateway=192.168.0.1 routing-table=to-wan1

# --- TO-WAN2 TABLE ---
# Traffic marked for WAN2 uses these routes
add check-gateway=ping comment="to-wan2 primary via WAN2" \
    distance=1 dst-address=0.0.0.0/0 gateway=192.168.0.1 routing-table=to-wan2

add check-gateway=ping comment="to-wan2 backup via WAN1" \
    distance=2 dst-address=0.0.0.0/0 gateway=192.168.2.1 routing-table=to-wan2

# --- MAIN TABLE ---
# Router's own traffic (not load balanced by default)
add check-gateway=ping comment="main primary via WAN1" \
    distance=1 dst-address=0.0.0.0/0 gateway=192.168.2.1

add check-gateway=ping comment="main backup via WAN2" \
    distance=2 dst-address=0.0.0.0/0 gateway=192.168.0.1

# ============================================================
# SYSTEM IDENTITY
# ============================================================
/system identity
set name=hEX-PCC-DualWAN

# ============================================================
# CONFIGURATION COMPLETE
# ============================================================
# This configuration provides:
# ✓ 50/50 load balancing via PCC
# ✓ Automatic failover with gateway monitoring
# ✓ Independent routing per WAN
# ✓ Full firewall protection
# ✓ Proper NAT for both WANs
#
# NEXT STEPS:
# 1. Update WAN IP addresses and gateways for your ISPs
# 2. Optionally change LAN subnet (currently 192.168.10.0/24)
# 3. Test failover by unplugging one WAN
# 4. Monitor with: /ip firewall mangle print stats
#
# VERIFICATION COMMANDS:
# /ip address print
# /ip route print where check-gateway=ping
# /ip firewall mangle print stats
# /ip firewall connection print where connection-mark~"wan"
# ============================================================