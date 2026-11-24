# ============================================================
# TRIPLE WAN PCC - MIKROTIK RouterOS 7
# RouterOS 7.x Compatible
#
# WAN1 = ether1 = [YOUR_WAN1_IP]/24
# GW1  = [YOUR_WAN1_GATEWAY]
#
# WAN2 = ether2 = [YOUR_WAN2_IP]/24
# GW2  = [YOUR_WAN2_GATEWAY]
#
# WAN3 = lte1 = [YOUR_LTE_IP]/24
# GW3  = [YOUR_LTE_GATEWAY]
#
# LAN  = bridge-LAN = 10.10.10.1/24
# LAN PORTS = ether4 + ether5
#
# PCC = 33/33/33
# Gateway health checks
# Independent failover across all three WANs
# IPv4 configuration
# ============================================================


# ------------------------------------------------------------
# 1. BACKUP BEFORE APPLYING
# ------------------------------------------------------------
# Always backup before making changes:
# /system backup save name=before-triple-wan-pcc
# /export file=before-triple-wan-pcc-export


# ------------------------------------------------------------
# 2. SYSTEM IDENTITY AND INTERFACE NAMES
# ------------------------------------------------------------

/system identity set name=Triple-WAN-PCC-Router

/interface ethernet
set [find default-name=ether1] name=ether1 comment="WAN1"
set [find default-name=ether2] name=ether2 comment="WAN2"
set [find default-name=ether4] name=ether4 comment="LAN Port 1"
set [find default-name=ether5] name=ether5 comment="LAN Port 2"


# ------------------------------------------------------------
# 3. LAN BRIDGE
# ------------------------------------------------------------

/interface bridge
add name=bridge-LAN protocol-mode=rstp comment="LAN bridge for ether4 and ether5"

/interface bridge port
add bridge=bridge-LAN interface=ether4
add bridge=bridge-LAN interface=ether5


# ------------------------------------------------------------
# 4. IP ADDRESS CONFIGURATION
# Update these with your actual WAN IPs and LAN subnet
# ------------------------------------------------------------

/ip address
add address=[YOUR_WAN1_IP]/24 interface=ether1 comment="WAN1 IP"
add address=[YOUR_WAN2_IP]/24 interface=ether2 comment="WAN2 IP"
add address=[YOUR_LTE_IP]/24 interface=lte1 comment="WAN3 LTE IP"
add address=10.10.10.1/24 interface=bridge-LAN comment="LAN Gateway"


# ------------------------------------------------------------
# 5. ROUTING TABLES
# ------------------------------------------------------------

/routing table
add name=to-WAN1 fib
add name=to-WAN2 fib
add name=to-WAN3 fib


# ------------------------------------------------------------
# 6. MAIN DEFAULT ROUTES AND FAILOVER
# ------------------------------------------------------------

/ip route
add dst-address=0.0.0.0/0 gateway=[YOUR_WAN1_GATEWAY] distance=1 check-gateway=ping comment="Main default via WAN1"
add dst-address=0.0.0.0/0 gateway=[YOUR_WAN2_GATEWAY] distance=2 check-gateway=ping comment="Backup default via WAN2"
add dst-address=0.0.0.0/0 gateway=[YOUR_LTE_GATEWAY] distance=3 check-gateway=ping comment="Backup default via WAN3 LTE"


# ------------------------------------------------------------
# 7. PCC CONNECTION MARKING
# Split LAN connections into three buckets: WAN1, WAN2, WAN3
# ------------------------------------------------------------

/ip firewall mangle
add chain=prerouting connection-state=established,related action=accept comment="Accept established/related"

add chain=prerouting in-interface=bridge-LAN connection-mark=no-mark \
    per-connection-classifier=both-addresses-and-ports:3/0 \
    action=mark-connection new-connection-mark=WAN1-conn passthrough=yes \
    comment="PCC bucket 0 to WAN1"

add chain=prerouting in-interface=bridge-LAN connection-mark=no-mark \
    per-connection-classifier=both-addresses-and-ports:3/1 \
    action=mark-connection new-connection-mark=WAN2-conn passthrough=yes \
    comment="PCC bucket 1 to WAN2"

add chain=prerouting in-interface=bridge-LAN connection-mark=no-mark \
    per-connection-classifier=both-addresses-and-ports:3/2 \
    action=mark-connection new-connection-mark=WAN3-conn passthrough=yes \
    comment="PCC bucket 2 to WAN3 LTE"


# ------------------------------------------------------------
# 8. ROUTING MARKING
# ------------------------------------------------------------

/ip firewall mangle
add chain=prerouting in-interface=bridge-LAN connection-mark=WAN1-conn \
    action=mark-routing new-routing-mark=to-WAN1 passthrough=no \
    comment="Route marked WAN1 connections via table to-WAN1"

add chain=prerouting in-interface=bridge-LAN connection-mark=WAN2-conn \
    action=mark-routing new-routing-mark=to-WAN2 passthrough=no \
    comment="Route marked WAN2 connections via table to-WAN2"

add chain=prerouting in-interface=bridge-LAN connection-mark=WAN3-conn \
    action=mark-routing new-routing-mark=to-WAN3 passthrough=no \
    comment="Route marked WAN3 connections via table to-WAN3"


# ------------------------------------------------------------
# 9. ROUTER-ORIGINATED TRAFFIC MARKING (OPTIONAL)
# Uncomment if you want router's own traffic load balanced
# ------------------------------------------------------------

# /ip firewall mangle
# add chain=output connection-mark=no-mark \
#     per-connection-classifier=both-addresses-and-ports:3/0 \
#     action=mark-connection new-connection-mark=WAN1-conn passthrough=yes \
#     comment="Router output PCC bucket 0 to WAN1"
# 
# add chain=output connection-mark=no-mark \
#     per-connection-classifier=both-addresses-and-ports:3/1 \
#     action=mark-connection new-connection-mark=WAN2-conn passthrough=yes \
#     comment="Router output PCC bucket 1 to WAN2"
# 
# add chain=output connection-mark=no-mark \
#     per-connection-classifier=both-addresses-and-ports:3/2 \
#     action=mark-connection new-connection-mark=WAN3-conn passthrough=yes \
#     comment="Router output PCC bucket 2 to WAN3"
# 
# add chain=output connection-mark=WAN1-conn \
#     action=mark-routing new-routing-mark=to-WAN1 passthrough=no
# 
# add chain=output connection-mark=WAN2-conn \
#     action=mark-routing new-routing-mark=to-WAN2 passthrough=no
# 
# add chain=output connection-mark=WAN3-conn \
#     action=mark-routing new-routing-mark=to-WAN3 passthrough=no


# ------------------------------------------------------------
# 10. POLICY ROUTES FOR PCC TABLES
# Each table gets its preferred WAN plus fallback routes
# ------------------------------------------------------------

/ip route
# to-WAN1 table
add dst-address=0.0.0.0/0 gateway=[YOUR_WAN1_GATEWAY] routing-table=to-WAN1 distance=1 check-gateway=ping comment="to-WAN1 primary via WAN1"
add dst-address=0.0.0.0/0 gateway=[YOUR_WAN2_GATEWAY] routing-table=to-WAN1 distance=2 check-gateway=ping comment="to-WAN1 fallback via WAN2"
add dst-address=0.0.0.0/0 gateway=[YOUR_LTE_GATEWAY] routing-table=to-WAN1 distance=3 check-gateway=ping comment="to-WAN1 fallback via WAN3 LTE"

# to-WAN2 table
add dst-address=0.0.0.0/0 gateway=[YOUR_WAN2_GATEWAY] routing-table=to-WAN2 distance=1 check-gateway=ping comment="to-WAN2 primary via WAN2"
add dst-address=0.0.0.0/0 gateway=[YOUR_WAN1_GATEWAY] routing-table=to-WAN2 distance=2 check-gateway=ping comment="to-WAN2 fallback via WAN1"
add dst-address=0.0.0.0/0 gateway=[YOUR_LTE_GATEWAY] routing-table=to-WAN2 distance=3 check-gateway=ping comment="to-WAN2 fallback via WAN3 LTE"

# to-WAN3 table
add dst-address=0.0.0.0/0 gateway=[YOUR_LTE_GATEWAY] routing-table=to-WAN3 distance=1 check-gateway=ping comment="to-WAN3 primary via WAN3 LTE"
add dst-address=0.0.0.0/0 gateway=[YOUR_WAN1_GATEWAY] routing-table=to-WAN3 distance=2 check-gateway=ping comment="to-WAN3 fallback via WAN1"
add dst-address=0.0.0.0/0 gateway=[YOUR_WAN2_GATEWAY] routing-table=to-WAN3 distance=3 check-gateway=ping comment="to-WAN3 fallback via WAN2"


# ------------------------------------------------------------
# 11. NAT MASQUERADE
# ------------------------------------------------------------

/ip firewall nat
add chain=srcnat out-interface=ether1 action=masquerade comment="NAT via WAN1"
add chain=srcnat out-interface=ether2 action=masquerade comment="NAT via WAN2"
add chain=srcnat out-interface=lte1 action=masquerade comment="NAT via WAN3 LTE"


# ------------------------------------------------------------
# 12. DNS
# ------------------------------------------------------------

/ip dns
set servers=1.1.1.1,8.8.8.8 allow-remote-requests=yes


# ------------------------------------------------------------
# 13. DHCP SERVER FOR LAN (OPTIONAL)
# ------------------------------------------------------------

/ip pool
add name=LAN-pool ranges=10.10.10.100-10.10.10.250

/ip dhcp-server
add name=LAN-DHCP interface=bridge-LAN address-pool=LAN-pool disabled=no

/ip dhcp-server network
add address=10.10.10.0/24 gateway=10.10.10.1 dns-server=10.10.10.1,1.1.1.1


# ------------------------------------------------------------
# 14. NETWATCH FAST FAILOVER (OPTIONAL)
# Clears existing connections when a WAN gateway goes down
# ------------------------------------------------------------

/tool netwatch
add host=[YOUR_WAN1_GATEWAY] interval=5s timeout=2s \
    down-script="/ip firewall connection remove [find connection-mark=WAN1-conn]" \
    comment="Monitor WAN1 gateway"

add host=[YOUR_WAN2_GATEWAY] interval=5s timeout=2s \
    down-script="/ip firewall connection remove [find connection-mark=WAN2-conn]" \
    comment="Monitor WAN2 gateway"

add host=[YOUR_LTE_GATEWAY] interval=5s timeout=2s \
    down-script="/ip firewall connection remove [find connection-mark=WAN3-conn]" \
    comment="Monitor WAN3 LTE gateway"


# ------------------------------------------------------------
# 15. BASIC FIREWALL (OPTIONAL)
# Uncomment if you need basic protection
# ------------------------------------------------------------

# /ip firewall filter
# add chain=input action=accept connection-state=established,related,untracked comment="Accept established/related input"
# add chain=input action=drop connection-state=invalid comment="Drop invalid input"
# add chain=input action=accept in-interface=bridge-LAN comment="Allow LAN access to router"
# add chain=input action=drop comment="Drop all other input"
# 
# add chain=forward action=accept connection-state=established,related,untracked comment="Accept established/related forward"
# add chain=forward action=drop connection-state=invalid comment="Drop invalid forward"
# add chain=forward action=accept in-interface=bridge-LAN comment="Allow LAN to WAN"
# add chain=forward action=drop comment="Drop all other forward"


# ------------------------------------------------------------
# 16. COMPLETE
# ------------------------------------------------------------

:put "TRIPLE WAN PCC CONFIGURATION APPLIED"
