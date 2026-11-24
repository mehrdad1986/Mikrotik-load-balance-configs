# ============================================================
# BEST PCC DUAL WAN - MIKROTIK RouterOS 7
# RouterOS 7.x Compatible
#
# WAN1 = ether1 = [YOUR_WAN1_IP]/24
# GW1  = [YOUR_WAN1_GATEWAY]
#
# WAN2 = ether2 = [YOUR_WAN2_IP]/24
# GW2  = [YOUR_WAN2_GATEWAY]
#
# LAN  = bridge2 = 192.168.10.1/24
# LAN PORTS = ether4 + ether5
#
# PCC = 50/50
# Recursive health checks = 2 per WAN
# Independent failover in both PCC tables
# IPv4 configuration
# ============================================================


# ------------------------------------------------------------
# 1. ENSURE POLICY ROUTING TABLES EXIST
# ------------------------------------------------------------

:if ([:len [/routing table find where name="to-wan1"]] = 0) do={
    /routing table add name=to-wan1 fib
}

:if ([:len [/routing table find where name="to-wan2"]] = 0) do={
    /routing table add name=to-wan2 fib
}


# ------------------------------------------------------------
# 2. REMOVE OLD PCC FIREWALL RULES
# ------------------------------------------------------------

/ip firewall filter remove [find]
/ip firewall mangle remove [find]


# ------------------------------------------------------------
# 3. REMOVE OLD WAN SOURCE NAT RULES
# Preserve existing destination NAT / port forwarding.
# ------------------------------------------------------------

/ip firewall nat
remove [find where comment="NAT WAN1"]
remove [find where comment="NAT WAN2"]
remove [find where comment="NAT out of whichever WAN is used"]
remove [find where comment="Masquerade traffic on both WANs"]
remove [find where comment="BEST-PCC-NAT-WAN1"]
remove [find where comment="BEST-PCC-NAT-WAN2"]


# ------------------------------------------------------------
# 4. REMOVE OLD PCC ROUTES
# Preserve unrelated static and dynamic routes.
# ------------------------------------------------------------

/ip route
remove [find where comment~"BEST-PCC-"]

# Original uploaded configuration
remove [find where comment="to-wan1 primary via WAN1"]
remove [find where comment="to-wan1 backup via WAN2"]
remove [find where comment="to-wan2 primary via WAN2"]
remove [find where comment="to-wan2 backup via WAN1"]
remove [find where comment="main primary via WAN1"]
remove [find where comment="main backup via WAN2"]

# Previously proposed configuration
remove [find where comment="probe host pinned to WAN1"]
remove [find where comment="probe host pinned to WAN2"]
remove [find where comment="main: WAN1 primary"]
remove [find where comment="main: WAN2 backup"]
remove [find where comment="to-wan1: WAN1 primary"]
remove [find where comment="to-wan1: WAN2 backup"]
remove [find where comment="to-wan2: WAN2 primary"]
remove [find where comment="to-wan2: WAN1 backup"]


# ------------------------------------------------------------
# 5. PCC DESTINATION EXCLUSIONS
# ------------------------------------------------------------

/ip firewall address-list
remove [find where list="no-pcc"]

add list=no-pcc address=0.0.0.0/8 comment="BEST-PCC-INVALID"
add list=no-pcc address=10.0.0.0/8 comment="BEST-PCC-PRIVATE"
add list=no-pcc address=100.64.0.0/10 comment="BEST-PCC-CGNAT"
add list=no-pcc address=127.0.0.0/8 comment="BEST-PCC-LOOPBACK"
add list=no-pcc address=169.254.0.0/16 comment="BEST-PCC-LINKLOCAL"
add list=no-pcc address=172.16.0.0/12 comment="BEST-PCC-PRIVATE"
add list=no-pcc address=192.168.0.0/16 comment="BEST-PCC-PRIVATE"
add list=no-pcc address=198.18.0.0/15 comment="BEST-PCC-BENCHMARK"
add list=no-pcc address=224.0.0.0/4 comment="BEST-PCC-MULTICAST"
add list=no-pcc address=240.0.0.0/4 comment="BEST-PCC-RESERVED"
add list=no-pcc address=255.255.255.255/32 comment="BEST-PCC-BROADCAST"


# ------------------------------------------------------------
# 6. ROUTER DNS
# DNS IPs are deliberately NOT the WAN health-check IPs.
# DNS follows the main routing table and its WAN failover.
# ------------------------------------------------------------

/ip dns
set allow-remote-requests=yes servers=1.0.0.1,149.112.112.112 cache-size=4096KiB

/ip dhcp-server network
set [find where address=192.168.10.0/24] gateway=192.168.10.1 dns-server=192.168.10.1


# ------------------------------------------------------------
# 7. RECURSIVE WAN HEALTH-CHECK HOST ROUTES
#
# WAN1:
# Cloudflare 1.1.1.1
# Google     8.8.8.8
#
# WAN2:
# Quad9      9.9.9.9
# OpenDNS    208.67.222.222
#
# Each host is pinned to its own WAN.
# ------------------------------------------------------------

/ip route

add dst-address=1.1.1.1/32 gateway=[YOUR_WAN1_GATEWAY] routing-table=main scope=10 comment="BEST-PCC-PROBE-W1-CLOUDFLARE"

add dst-address=8.8.8.8/32 gateway=[YOUR_WAN1_GATEWAY] routing-table=main scope=10 comment="BEST-PCC-PROBE-W1-GOOGLE"

add dst-address=9.9.9.9/32 gateway=[YOUR_WAN2_GATEWAY] routing-table=main scope=10 comment="BEST-PCC-PROBE-W2-QUAD9"

add dst-address=208.67.222.222/32 gateway=[YOUR_WAN2_GATEWAY] routing-table=main scope=10 comment="BEST-PCC-PROBE-W2-OPENDNS"


# ------------------------------------------------------------
# 8. MAIN ROUTING TABLE
#
# WAN1 primary: distance 1
# WAN2 backup:  distance 2
#
# Two equal-cost primary routes per WAN.
# If one probe fails, the other can remain active.
# ------------------------------------------------------------

/ip route

# MAIN WAN1 PRIMARY

add dst-address=0.0.0.0/0 gateway=1.1.1.1 routing-table=main distance=1 scope=30 target-scope=11 check-gateway=ping comment="BEST-PCC-MAIN-W1-CF"

add dst-address=0.0.0.0/0 gateway=8.8.8.8 routing-table=main distance=1 scope=30 target-scope=11 check-gateway=ping comment="BEST-PCC-MAIN-W1-GOOGLE"

# MAIN WAN2 BACKUP

add dst-address=0.0.0.0/0 gateway=9.9.9.9 routing-table=main distance=2 scope=30 target-scope=11 check-gateway=ping comment="BEST-PCC-MAIN-W2-QUAD9"

add dst-address=0.0.0.0/0 gateway=208.67.222.222 routing-table=main distance=2 scope=30 target-scope=11 check-gateway=ping comment="BEST-PCC-MAIN-W2-OPENDNS"


# ------------------------------------------------------------
# 9. WAN1 POLICY TABLE
#
# WAN1 primary
# WAN2 backup
#
# @main explicitly resolves recursive next-hops.
# ------------------------------------------------------------

/ip route

# WAN1 PRIMARY

add dst-address=0.0.0.0/0 gateway=1.1.1.1@main routing-table=to-wan1 distance=1 scope=30 target-scope=11 check-gateway=ping comment="BEST-PCC-W1-PRIMARY-CF"

add dst-address=0.0.0.0/0 gateway=8.8.8.8@main routing-table=to-wan1 distance=1 scope=30 target-scope=11 check-gateway=ping comment="BEST-PCC-W1-PRIMARY-GOOGLE"

# WAN2 BACKUP

add dst-address=0.0.0.0/0 gateway=9.9.9.9@main routing-table=to-wan1 distance=2 scope=30 target-scope=11 check-gateway=ping comment="BEST-PCC-W1-BACKUP-QUAD9"

add dst-address=0.0.0.0/0 gateway=208.67.222.222@main routing-table=to-wan1 distance=2 scope=30 target-scope=11 check-gateway=ping comment="BEST-PCC-W1-BACKUP-OPENDNS"


# ------------------------------------------------------------
# 10. WAN2 POLICY TABLE
#
# WAN2 primary
# WAN1 backup
# ------------------------------------------------------------

/ip route

# WAN2 PRIMARY

add dst-address=0.0.0.0/0 gateway=9.9.9.9@main routing-table=to-wan2 distance=1 scope=30 target-scope=11 check-gateway=ping comment="BEST-PCC-W2-PRIMARY-QUAD9"

add dst-address=0.0.0.0/0 gateway=208.67.222.222@main routing-table=to-wan2 distance=1 scope=30 target-scope=11 check-gateway=ping comment="BEST-PCC-W2-PRIMARY-OPENDNS"

# WAN1 BACKUP

add dst-address=0.0.0.0/0 gateway=1.1.1.1@main routing-table=to-wan2 distance=2 scope=30 target-scope=11 check-gateway=ping comment="BEST-PCC-W2-BACKUP-CF"

add dst-address=0.0.0.0/0 gateway=8.8.8.8@main routing-table=to-wan2 distance=2 scope=30 target-scope=11 check-gateway=ping comment="BEST-PCC-W2-BACKUP-GOOGLE"


# ------------------------------------------------------------
# 11. INBOUND CONNECTION MARKING
#
# Remember which WAN received each new connection.
# This is important for port forwarding and router services.
# ------------------------------------------------------------

/ip firewall mangle

add chain=prerouting in-interface=ether1 connection-state=new connection-mark=no-mark action=mark-connection new-connection-mark=wan1-conn passthrough=yes comment="BEST-PCC-INBOUND-WAN1"

add chain=prerouting in-interface=ether2 connection-state=new connection-mark=no-mark action=mark-connection new-connection-mark=wan2-conn passthrough=yes comment="BEST-PCC-INBOUND-WAN2"


# ------------------------------------------------------------
# 12. BYPASS PCC FOR LOCAL AND PRIVATE DESTINATIONS
# ------------------------------------------------------------

add chain=prerouting in-interface=bridge2 dst-address-type=local action=accept comment="BEST-PCC-LOCAL-BYPASS"

add chain=prerouting in-interface=bridge2 dst-address-list=no-pcc action=accept comment="BEST-PCC-PRIVATE-BYPASS"


# ------------------------------------------------------------
# 13. PCC CLASSIFICATION
#
# 2/0 = WAN1
# 2/1 = WAN2
#
# both-addresses-and-ports gives granular connection
# distribution across the two links.
# ------------------------------------------------------------

add chain=prerouting in-interface=bridge2 connection-state=new connection-mark=no-mark dst-address-type=!local per-connection-classifier=both-addresses-and-ports:2/0 action=mark-connection new-connection-mark=wan1-conn passthrough=yes comment="BEST-PCC-CLASSIFY-WAN1"

add chain=prerouting in-interface=bridge2 connection-state=new connection-mark=no-mark dst-address-type=!local per-connection-classifier=both-addresses-and-ports:2/1 action=mark-connection new-connection-mark=wan2-conn passthrough=yes comment="BEST-PCC-CLASSIFY-WAN2"


# ------------------------------------------------------------
# 14. ROUTING MARKS FOR LAN CLIENTS
# ------------------------------------------------------------

add chain=prerouting in-interface=bridge2 connection-mark=wan1-conn action=mark-routing new-routing-mark=to-wan1 passthrough=no comment="BEST-PCC-ROUTE-WAN1"

add chain=prerouting in-interface=bridge2 connection-mark=wan2-conn action=mark-routing new-routing-mark=to-wan2 passthrough=no comment="BEST-PCC-ROUTE-WAN2"


# ------------------------------------------------------------
# 15. ROUTER-ORIGINATED REPLIES
# ------------------------------------------------------------

add chain=output connection-mark=wan1-conn action=mark-routing new-routing-mark=to-wan1 passthrough=no comment="BEST-PCC-OUTPUT-WAN1"

add chain=output connection-mark=wan2-conn action=mark-routing new-routing-mark=to-wan2 passthrough=no comment="BEST-PCC-OUTPUT-WAN2"


# ------------------------------------------------------------
# 16. SOURCE NAT
#
# Replace [YOUR_WAN1_IP] and [YOUR_WAN2_IP] with actual IPs
# ------------------------------------------------------------

/ip firewall nat

add chain=srcnat out-interface=ether1 action=src-nat to-addresses=[YOUR_WAN1_IP] comment="BEST-PCC-NAT-WAN1"

add chain=srcnat out-interface=ether2 action=src-nat to-addresses=[YOUR_WAN2_IP] comment="BEST-PCC-NAT-WAN2"


# ------------------------------------------------------------
# 17. INPUT FIREWALL
#
# LAN can access router services.
# New incoming WAN connections to router itself are blocked.
# ------------------------------------------------------------

/ip firewall filter

add chain=input action=accept connection-state=established,related,untracked comment="BEST-PCC-INPUT-ESTABLISHED"

add chain=input action=drop connection-state=invalid comment="BEST-PCC-INPUT-INVALID"

add chain=input action=accept in-interface=bridge2 comment="BEST-PCC-INPUT-LAN"

add chain=input action=drop comment="BEST-PCC-INPUT-DROP-OTHER"


# ------------------------------------------------------------
# 18. FORWARD FIREWALL
# ------------------------------------------------------------

add chain=forward action=accept connection-state=established,related,untracked comment="BEST-PCC-FORWARD-ESTABLISHED"

add chain=forward action=drop connection-state=invalid comment="BEST-PCC-FORWARD-INVALID"

# LAN to WAN1

add chain=forward action=accept in-interface=bridge2 out-interface=ether1 comment="BEST-PCC-LAN-TO-WAN1"

# LAN to WAN2

add chain=forward action=accept in-interface=bridge2 out-interface=ether2 comment="BEST-PCC-LAN-TO-WAN2"

# Explicit port forwarding through WAN1

add chain=forward action=accept in-interface=ether1 connection-nat-state=dstnat comment="BEST-PCC-DSTNAT-WAN1"

# Explicit port forwarding through WAN2

add chain=forward action=accept in-interface=ether2 connection-nat-state=dstnat comment="BEST-PCC-DSTNAT-WAN2"

# Drop all remaining forwarded traffic

add chain=forward action=drop comment="BEST-PCC-FORWARD-DROP-OTHER"


# ------------------------------------------------------------
# 19. COMPLETE
# ------------------------------------------------------------

:put "BEST PCC DUAL WAN CONFIGURATION APPLIED"
