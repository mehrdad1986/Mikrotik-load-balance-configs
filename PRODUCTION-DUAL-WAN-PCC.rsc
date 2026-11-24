# ============================================================================
# PRODUCTION DUAL WAN PCC CONFIGURATION
# MikroTik RB750Gr3 - RouterOS 7.23.2+
# ============================================================================
#
# TOPOLOGY:
#   WAN1: ether1 → 192.168.2.100/24 (Gateway: 192.168.2.1)
#   WAN2: ether2 → 192.168.0.100/24 (Gateway: 192.168.0.1)
#   LAN:  bridge2 (ether4 + ether5) → 192.168.10.1/24
#
# FEATURES:
#   • 50/50 PCC load balancing (per-connection distribution)
#   • Recursive health checks with 2 public IPs per WAN
#   • Independent failover for each routing table
#   • Full firewall protection (input + forward chains)
#   • Management restricted to LAN only
#   • Static NAT for predictable source addressing
#
# HEALTH MONITORING:
#   WAN1: 1.1.1.1 (Cloudflare) + 8.8.8.8 (Google)
#   WAN2: 9.9.9.9 (Quad9) + 208.67.222.222 (OpenDNS)
#
# IMPORTANT PREREQUISITES:
#   This configuration assumes a clean router with NO DEFAULT CONFIGURATION.
#   If default bridge or firewall rules exist, remove them first or conflicts will occur.
#
#   To reset: /system reset-configuration no-defaults=yes
#
# BEFORE APPLYING:
#   1. Backup current configuration: /system backup save name=before-pcc
#   2. Export current config: /export file=before-pcc-export
#   3. Update WAN IP addresses and gateways to match your ISPs
#   4. Test from local access only (not remote) in case of issues
#
# ============================================================================


# ============================================================================
# SECTION 1: LAN BRIDGE CONFIGURATION
# ============================================================================
# Creates a Layer-2 bridge to combine ether4 and ether5 into a single
# logical LAN interface. This simplifies mangle rules and provides a
# unified entry point for all LAN traffic.
#
# RSTP (Rapid Spanning Tree Protocol) is enabled to prevent loops if
# additional switches are connected to the bridge.

/interface bridge
add name=bridge2 protocol-mode=rstp comment="LAN"

/interface bridge port
add bridge=bridge2 interface=ether4
add bridge=bridge2 interface=ether5

# Create interface list for LAN (used by management services later)
/interface list
add name=LAN

/interface list member
add list=LAN interface=bridge2


# ============================================================================
# SECTION 2: IP ADDRESS ASSIGNMENT
# ============================================================================
# Assigns static IP addresses to all interfaces.
#
# IMPORTANT: Update these addresses to match your ISP assignments:
#   - WAN1 IP and subnet must match ISP1's allocation
#   - WAN2 IP and subnet must match ISP2's allocation
#   - LAN subnet can be changed to any private range you prefer

/ip address
add address=192.168.2.100/24 interface=ether1 comment="WAN1"
add address=192.168.0.100/24 interface=ether2 comment="WAN2"
add address=192.168.10.1/24 interface=bridge2 comment="LAN"


# ============================================================================
# SECTION 3: DHCP SERVER CONFIGURATION
# ============================================================================
# Automatically assigns IP addresses to LAN clients.
#
# POOL RANGE: 192.168.10.100-250 (150 addresses)
#   Reserves .1 for gateway, .2-.99 for static assignments
#
# LEASE TIME: 12 hours
#   Clients renew halfway through (6 hours)
#   Adjust based on your environment (longer for stable networks)

/ip pool
add name=lan-pool ranges=192.168.10.100-192.168.10.250

/ip dhcp-server
add name=dhcp-lan interface=bridge2 address-pool=lan-pool lease-time=12h disabled=no

/ip dhcp-server network
add address=192.168.10.0/24 gateway=192.168.10.1 dns-server=192.168.10.1


# ============================================================================
# SECTION 4: DNS CONFIGURATION
# ============================================================================
# Configures DNS resolver for the router and LAN clients.
#
# UPSTREAM SERVERS:
#   1.0.0.1       - Cloudflare (primary)
#   149.112.112.112 - Quad9 (secondary)
#
# allow-remote-requests=yes: Allows LAN clients to use router as DNS server
# cache-size=4096KiB: Stores DNS responses for faster subsequent lookups
#
# NOTE: These DNS servers are DIFFERENT from health check targets.
#       DNS follows the main routing table (WAN1 primary, WAN2 backup).
#       This ensures DNS works even during failover.

/ip dns
set allow-remote-requests=yes servers=1.0.0.1,149.112.112.112 cache-size=4096KiB


# ============================================================================
# SECTION 5: MULTI-WAN ROUTING FOUNDATION
# ============================================================================
# Prepares RouterOS for policy-based routing with multiple WANs.
#
# rp-filter=loose:
#   Reverse Path Filtering controls how router validates source IPs.
#   
#   strict (default): Packet must arrive on the interface that would be
#                     used to reach its source IP. BREAKS multi-WAN because
#                     return traffic may arrive on different interface.
#   
#   loose: Only checks that source IP is reachable via ANY interface.
#          Required for PCC to work correctly with asymmetric routing.
#
# ROUTING TABLES:
#   Creates two policy routing tables for PCC traffic distribution.
#   Each table contains its own default routes with independent failover.
#
#   to-wan1: Routes for connections marked for WAN1
#   to-wan2: Routes for connections marked for WAN2
#   main: Default table (router's own traffic, unmarked connections)

/ip settings
set rp-filter=loose

/routing table
add name=to-wan1 fib
add name=to-wan2 fib


# ============================================================================
# SECTION 6: PCC EXCLUSION LIST
# ============================================================================
# Defines IP ranges that should BYPASS PCC load balancing.
#
# WHY EXCLUDE THESE:
#   These are private, local, or special-use addresses that should never
#   be routed through WAN interfaces. PCC is only for public internet traffic.
#
# WHAT HAPPENS WITHOUT THIS:
#   - LAN-to-LAN traffic might be routed out WAN and back (broken)
#   - Router management traffic might fail
#   - Multicast and broadcast would be routed incorrectly
#
# ADDRESS RANGES EXPLAINED:
#   0.0.0.0/8       - Invalid/this network (RFC 1122)
#   10.0.0.0/8      - Private Class A (RFC 1918)
#   100.64.0.0/10   - Carrier-grade NAT (RFC 6598)
#   127.0.0.0/8     - Loopback (RFC 1122)
#   169.254.0.0/16  - Link-local (RFC 3927)
#   172.16.0.0/12   - Private Class B (RFC 1918)
#   192.168.0.0/16  - Private Class C (RFC 1918)
#   198.18.0.0/15   - Benchmarking (RFC 2544)
#   224.0.0.0/4     - Multicast (RFC 5771)
#   240.0.0.0/4     - Reserved (RFC 1112)

/ip firewall address-list
add list=no-pcc address=0.0.0.0/8
add list=no-pcc address=10.0.0.0/8
add list=no-pcc address=100.64.0.0/10
add list=no-pcc address=127.0.0.0/8
add list=no-pcc address=169.254.0.0/16
add list=no-pcc address=172.16.0.0/12
add list=no-pcc address=192.168.0.0/16
add list=no-pcc address=198.18.0.0/15
add list=no-pcc address=224.0.0.0/4
add list=no-pcc address=240.0.0.0/4


# ============================================================================
# SECTION 7: RECURSIVE HEALTH CHECK ROUTES
# ============================================================================
# Pins specific public IPs to each WAN for health monitoring.
#
# HOW RECURSIVE ROUTING WORKS:
#   
#   Traditional: gateway=192.168.2.1 check-gateway=ping
#   Problem: Only checks if gateway responds. If gateway is up but ISP link
#            is down, router doesn't know internet is unreachable.
#
#   Recursive: gateway=1.1.1.1 (requires route to 1.1.1.1 via real gateway)
#   Benefit: Checks end-to-end internet connectivity, not just gateway.
#
# SCOPE EXPLANATION:
#   
#   scope=10: This is the "target" route that provides actual next-hop.
#             These routes point to real gateway IPs.
#   
#   Later routes use target-scope=11 meaning:
#   "I need a route with scope <= 11 to resolve my gateway"
#   Since 10 <= 11, these routes satisfy that requirement.
#
# WHY TWO TARGETS PER WAN:
#   
#   Redundancy in monitoring. If one target fails (e.g., Cloudflare has
#   an outage), the other target keeps the route active. Only when BOTH
#   targets fail does the WAN route become inactive.
#
# CHOSEN TARGETS:
#   
#   These are highly reliable, globally distributed DNS servers:
#   - 1.1.1.1: Cloudflare (anycast, worldwide presence)
#   - 8.8.8.8: Google (anycast, worldwide presence)
#   - 9.9.9.9: Quad9 (anycast, privacy-focused)
#   - 208.67.222.222: OpenDNS (reliable, long-standing)

/ip route
add dst-address=1.1.1.1/32 gateway=192.168.2.1 scope=10 comment="PROBE-WAN1-CLOUDFLARE"
add dst-address=8.8.8.8/32 gateway=192.168.2.1 scope=10 comment="PROBE-WAN1-GOOGLE"

add dst-address=9.9.9.9/32 gateway=192.168.0.1 scope=10 comment="PROBE-WAN2-QUAD9"
add dst-address=208.67.222.222/32 gateway=192.168.0.1 scope=10 comment="PROBE-WAN2-OPENDNS"


# ============================================================================
# SECTION 8: MAIN ROUTING TABLE (ROUTER'S OWN TRAFFIC)
# ============================================================================
# Default routes for traffic that doesn't have a routing mark.
# This includes:
#   - Router's own generated traffic (DNS lookups, NTP, package updates)
#   - Any traffic that bypasses PCC (no-pcc address list)
#
# PRIORITY STRUCTURE:
#   
#   distance=1: WAN1 primary routes (via both Cloudflare and Google)
#   distance=2: WAN2 backup routes (via both Quad9 and OpenDNS)
#
# RECURSIVE GATEWAY:
#   
#   gateway=1.1.1.1 means "route via 1.1.1.1"
#   RouterOS looks up how to reach 1.1.1.1 (finds the scope=10 route above)
#   That route says "use gateway 192.168.2.1"
#   So effective gateway is 192.168.2.1, but monitored via ping to 1.1.1.1
#
# target-scope=11:
#   
#   Tells RouterOS "I need a route with scope <= 11 to resolve my gateway"
#   The scope=10 routes from Section 7 satisfy this requirement
#
# check-gateway=ping:
#   
#   RouterOS pings the recursive gateway (1.1.1.1, 8.8.8.8, etc.)
#   If ping fails, route becomes inactive
#   Traffic automatically uses next lowest distance route
#
# FAILOVER BEHAVIOR:
#   
#   Normal: Both WAN1 routes active, router uses WAN1
#   
#   If 1.1.1.1 unreachable: WAN1-CF route fails, but WAN1-GOOGLE still active
#                           Router continues using WAN1 via 8.8.8.8 route
#   
#   If both 1.1.1.1 AND 8.8.8.8 unreachable: Both WAN1 routes fail
#                                             WAN2 routes (distance=2) activate
#                                             Router switches to WAN2

/ip route
add dst-address=0.0.0.0/0 gateway=1.1.1.1 distance=1 target-scope=11 check-gateway=ping comment="MAIN-WAN1-CF"
add dst-address=0.0.0.0/0 gateway=8.8.8.8 distance=1 target-scope=11 check-gateway=ping comment="MAIN-WAN1-GOOGLE"

add dst-address=0.0.0.0/0 gateway=9.9.9.9 distance=2 target-scope=11 check-gateway=ping comment="MAIN-WAN2-QUAD9"
add dst-address=0.0.0.0/0 gateway=208.67.222.222 distance=2 target-scope=11 check-gateway=ping comment="MAIN-WAN2-OPENDNS"


# ============================================================================
# SECTION 9: WAN1 POLICY ROUTING TABLE
# ============================================================================
# Routes for connections marked to use WAN1 (via PCC).
#
# STRUCTURE:
#   Primary (distance=1): WAN1 via both health check targets
#   Backup (distance=2): WAN2 via both health check targets
#
# @main NOTATION:
#   
#   gateway=1.1.1.1@main means:
#   "Route to 1.1.1.1, but look up 1.1.1.1 in the MAIN table, not to-wan1"
#   
#   This is CRITICAL. Without @main:
#   - RouterOS would look for 1.1.1.1 route in to-wan1 table
#   - That route doesn't exist in to-wan1
#   - Gateway resolution fails
#   
#   With @main:
#   - RouterOS looks up 1.1.1.1 in main table
#   - Finds the scope=10 route: 1.1.1.1 via 192.168.2.1
#   - Correctly resolves to real gateway
#
# INDEPENDENT FAILOVER:
#   
#   This table has its OWN failover, separate from main table:
#   
#   Scenario 1: WAN1 completely fails
#     - Both WAN1 routes (distance=1) become inactive
#     - WAN2 routes (distance=2) activate automatically
#     - Connections marked for WAN1 now use WAN2
#   
#   Scenario 2: Only one WAN1 health check fails (e.g., 1.1.1.1 unreachable)
#     - WAN1-PRIMARY-CF route fails
#     - WAN1-PRIMARY-GOOGLE route still active
#     - Traffic continues using WAN1 via Google route
#   
#   Scenario 3: Both WANs healthy
#     - WAN1 routes (distance=1) active and preferred
#     - WAN2 routes (distance=2) inactive (standby)

/ip route
add dst-address=0.0.0.0/0 gateway=1.1.1.1@main routing-table=to-wan1 distance=1 target-scope=11 check-gateway=ping comment="WAN1-PRIMARY-CF"
add dst-address=0.0.0.0/0 gateway=8.8.8.8@main routing-table=to-wan1 distance=1 target-scope=11 check-gateway=ping comment="WAN1-PRIMARY-GOOGLE"

add dst-address=0.0.0.0/0 gateway=9.9.9.9@main routing-table=to-wan1 distance=2 target-scope=11 check-gateway=ping comment="WAN1-BACKUP-QUAD9"
add dst-address=0.0.0.0/0 gateway=208.67.222.222@main routing-table=to-wan1 distance=2 target-scope=11 check-gateway=ping comment="WAN1-BACKUP-OPENDNS"


# ============================================================================
# SECTION 10: WAN2 POLICY ROUTING TABLE
# ============================================================================
# Routes for connections marked to use WAN2 (via PCC).
#
# STRUCTURE:
#   Primary (distance=1): WAN2 via both health check targets
#   Backup (distance=2): WAN1 via both health check targets
#
# MIRROR OF WAN1 TABLE:
#   
#   This table is the inverse of to-wan1:
#   - Prefers WAN2 (distance=1)
#   - Falls back to WAN1 (distance=2)
#
# WHY CROSSOVER BACKUP:
#   
#   This provides true multi-WAN resilience:
#   
#   - 50% of connections prefer WAN1, backup to WAN2
#   - 50% of connections prefer WAN2, backup to WAN1
#   - If either WAN fails, 100% of connections still work
#   - Load remains distributed even during single-WAN failure
#
# EXAMPLE SCENARIO:
#   
#   Normal operation:
#     to-wan1 table: 50% of connections via WAN1
#     to-wan2 table: 50% of connections via WAN2
#     Result: Perfect 50/50 distribution
#   
#   WAN1 fails:
#     to-wan1 table: Connections fail over to WAN2 (distance=2)
#     to-wan2 table: Connections continue on WAN2 (distance=1)
#     Result: 100% of connections via WAN2
#   
#   WAN2 fails:
#     to-wan1 table: Connections continue on WAN1 (distance=1)
#     to-wan2 table: Connections fail over to WAN1 (distance=2)
#     Result: 100% of connections via WAN1

/ip route
add dst-address=0.0.0.0/0 gateway=9.9.9.9@main routing-table=to-wan2 distance=1 target-scope=11 check-gateway=ping comment="WAN2-PRIMARY-QUAD9"
add dst-address=0.0.0.0/0 gateway=208.67.222.222@main routing-table=to-wan2 distance=1 target-scope=11 check-gateway=ping comment="WAN2-PRIMARY-OPENDNS"

add dst-address=0.0.0.0/0 gateway=1.1.1.1@main routing-table=to-wan2 distance=2 target-scope=11 check-gateway=ping comment="WAN2-BACKUP-CF"
add dst-address=0.0.0.0/0 gateway=8.8.8.8@main routing-table=to-wan2 distance=2 target-scope=11 check-gateway=ping comment="WAN2-BACKUP-GOOGLE"


# ============================================================================
# SECTION 11: MANGLE - CONNECTION MARKING AND PCC
# ============================================================================
# Mangle rules classify and mark traffic to control routing decisions.
#
# PROCESSING ORDER:
#   Rules are evaluated top-to-bottom. First match wins (unless passthrough=yes).
#
# CHAIN EXPLANATION:
#   
#   prerouting: Processes packets BEFORE routing decision
#               Used for: marking inbound traffic, PCC classification
#   
#   output: Processes packets generated BY the router
#           Used for: ensuring router's replies use correct WAN
#
# MARK TYPES:
#   
#   connection-mark: Tags the entire connection (both directions)
#                    Persists for connection lifetime
#                    All packets in connection inherit this mark
#   
#   routing-mark: Specifies which routing table to use
#                 Applied based on connection-mark
#                 Controls path selection
#
# PASSTHROUGH:
#   
#   passthrough=yes: Continue to next rule (allows multiple marks)
#   passthrough=no: Stop here, skip remaining rules (optimization)

/ip firewall mangle

# ---------------------------------------------------------------------------
# STEP 1: MARK INBOUND WAN CONNECTIONS
# ---------------------------------------------------------------------------
# When traffic arrives FROM a WAN interface, remember which WAN it came from.
#
# WHY THIS MATTERS:
#   
#   Port forwarding example:
#     - External host connects to your WAN1 IP on port 80
#     - Connection marked as wan1-conn
#     - Your server responds
#     - Response must go back via WAN1 (same public IP)
#     - output chain rule (Section 12) ensures this happens
#
#   Without this marking:
#     - Response might use different WAN (wrong source IP)
#     - External host sees response from unexpected IP
#     - Connection fails
#
# connection-mark=no-mark:
#   Only mark NEW connections that aren't already marked
#   Prevents overwriting existing marks

add chain=prerouting in-interface=ether1 connection-state=new connection-mark=no-mark action=mark-connection new-connection-mark=wan1-conn passthrough=yes comment="INBOUND-WAN1"

add chain=prerouting in-interface=ether2 connection-state=new connection-mark=no-mark action=mark-connection new-connection-mark=wan2-conn passthrough=yes comment="INBOUND-WAN2"


# ---------------------------------------------------------------------------
# STEP 2: BYPASS PCC FOR LOCAL AND PRIVATE DESTINATIONS
# ---------------------------------------------------------------------------
# Skip PCC for traffic that should never go through WAN.
#
# BYPASS-LOCAL:
#   dst-address-type=local means:
#     "Destination is an IP configured ON this router"
#   
#   Examples:
#     - LAN client accessing router's web interface (192.168.10.1)
#     - LAN client accessing router's DNS service
#     - LAN client SSHing into router
#   
#   These must NOT be PCC'd because they don't need routing at all.
#   They terminate on the router itself.
#
# BYPASS-PRIVATE:
#   dst-address-list=no-pcc means:
#     "Destination is in the no-pcc address list" (Section 6)
#   
#   Examples:
#     - LAN client accessing another LAN device (192.168.10.x)
#     - LAN client accessing a server in another private subnet
#     - Multicast or broadcast traffic
#   
#   These must NOT be PCC'd because they should use direct LAN routing.
#
# action=accept:
#   Stop processing here. Skip remaining mangle rules for these packets.

add chain=prerouting in-interface=bridge2 dst-address-type=local action=accept comment="BYPASS-LOCAL"

add chain=prerouting in-interface=bridge2 dst-address-list=no-pcc action=accept comment="BYPASS-PRIVATE"


# ---------------------------------------------------------------------------
# STEP 3: PCC CLASSIFICATION (THE LOAD BALANCING MAGIC)
# ---------------------------------------------------------------------------
# Distribute NEW connections across WANs using hash-based classification.
#
# PER-CONNECTION CLASSIFIER EXPLAINED:
#   
#   per-connection-classifier=both-addresses-and-ports:2/0
#   
#   Both-addresses-and-ports: Hash input includes:
#     - Source IP address
#     - Destination IP address
#     - Source port
#     - Destination port
#   
#   :2/0 and :2/1 means:
#     - Divide hash space into 2 buckets (0 and 1)
#     - :2/0 matches bucket 0 (approximately 50%)
#     - :2/1 matches bucket 1 (approximately 50%)
#
# HOW HASHING WORKS:
#   
#   Connection: 192.168.10.100:54321 → 142.250.185.46:443
#   
#   Hash = f(192.168.10.100, 54321, 142.250.185.46, 443)
#   Hash = 0xABCD1234 (example)
#   
#   Bucket = Hash modulo 2
#   Bucket = 0xABCD1234 % 2 = 0
#   
#   Result: This connection gets wan1-conn mark (bucket 0)
#
# SESSION PERSISTENCE:
#   
#   Same 4-tuple ALWAYS produces same hash
#   Same hash ALWAYS selects same bucket
#   Same bucket ALWAYS gets same connection-mark
#   
#   This means:
#     - All packets in a connection use the same WAN
#     - No packet reordering
#     - Application-layer protocols work correctly
#
# WHY 50/50 ISN'T EXACT:
#   
#   Hash distributes CONNECTIONS, not BANDWIDTH
#   
#   Example:
#     - 10 connections total
#     - 5 to WAN1 (might be downloading huge files = 90 Mbps)
#     - 5 to WAN2 (might be just browsing = 10 Mbps)
#     - Distribution: 50/50 connections, but 90/10 bandwidth
#   
#   Over many connections, distribution averages out to 50/50.
#
# RULE CONDITIONS:
#   
#   in-interface=bridge2: Only from LAN
#   connection-mark=no-mark: Only if not already marked
#   connection-state=new: Only for NEW connections
#   dst-address-type=!local: Exclude router itself
#
# passthrough=yes:
#   
#   Continue to next rule even after marking.
#   Required because:
#     1. This rule marks connection
#     2. Next rule needs to apply routing-mark based on connection-mark

add chain=prerouting in-interface=bridge2 connection-mark=no-mark connection-state=new dst-address-type=!local per-connection-classifier=both-addresses-and-ports:2/0 action=mark-connection new-connection-mark=wan1-conn passthrough=yes comment="PCC-WAN1"

add chain=prerouting in-interface=bridge2 connection-mark=no-mark connection-state=new dst-address-type=!local per-connection-classifier=both-addresses-and-ports:2/1 action=mark-connection new-connection-mark=wan2-conn passthrough=yes comment="PCC-WAN2"


# ============================================================================
# SECTION 12: MANGLE - ROUTING MARKS (ROUTING TABLE SELECTION)
# ============================================================================
# Apply routing-marks based on connection-marks to force use of specific
# routing tables.
#
# ROUTING MARK PURPOSE:
#   
#   Connection-mark identifies: "This connection belongs to WAN1"
#   Routing-mark specifies: "Use the to-wan1 routing table"
#   
#   The routing table then determines the actual path/gateway.
#
# TWO LOCATIONS:
#   
#   prerouting chain: For LAN client traffic
#   output chain: For router's own traffic (replies to inbound connections)

# ---------------------------------------------------------------------------
# LAN CLIENT TRAFFIC
# ---------------------------------------------------------------------------
# Traffic from LAN clients that was previously marked by PCC.
#
# RULE LOGIC:
#   
#   IF connection-mark = wan1-conn
#   THEN routing-mark = to-wan1
#   
#   This forces RouterOS to look up routes in the to-wan1 table
#   instead of the main table.
#
# passthrough=no:
#   
#   Stop processing here. No need to continue to other rules.
#   This is the final mark for this packet.
#   Optimization: saves CPU cycles.

add chain=prerouting in-interface=bridge2 connection-mark=wan1-conn action=mark-routing new-routing-mark=to-wan1 passthrough=no comment="ROUTE-WAN1"

add chain=prerouting in-interface=bridge2 connection-mark=wan2-conn action=mark-routing new-routing-mark=to-wan2 passthrough=no comment="ROUTE-WAN2"


# ---------------------------------------------------------------------------
# ROUTER-ORIGINATED REPLIES TO INBOUND CONNECTIONS
# ---------------------------------------------------------------------------
# Ensures router's response packets use the same WAN as the inbound connection.
#
# CRITICAL FOR:
#   
#   Port forwarding:
#     - External host connects to WAN1 IP
#     - Inbound traffic marked as wan1-conn (Section 11, Step 1)
#     - Forwarded to internal server
#     - Server responds
#     - Response goes through router
#     - output chain marks response with to-wan1
#     - Response exits via WAN1 (same public IP)
#   
#   Router services:
#     - External host connects to router's service on WAN2
#     - Inbound traffic marked as wan2-conn
#     - Router processes request
#     - Router generates response
#     - output chain marks response with to-wan2
#     - Response exits via WAN2
#
# WITHOUT THESE RULES:
#   
#   Router's replies would use the main routing table
#   Main table prefers WAN1
#   Reply might exit via wrong WAN
#   
#   Example:
#     - Connection came in via WAN2 IP (192.168.0.100)
#     - Reply exits via WAN1 IP (192.168.2.100)
#     - External host sees response from unexpected IP
#     - Connection fails
#
# CHAIN EXPLANATION:
#   
#   output: Packets generated BY the router
#   
#   This includes:
#     - Replies to incoming connections
#     - Responses from router services
#     
#   This does NOT include:
#     - Forwarded traffic (uses prerouting, not output)
#     - Router's own initiated traffic (uses main table by default)

add chain=output connection-mark=wan1-conn action=mark-routing new-routing-mark=to-wan1 passthrough=no comment="OUTPUT-WAN1"

add chain=output connection-mark=wan2-conn action=mark-routing new-routing-mark=to-wan2 passthrough=no comment="OUTPUT-WAN2"


# ============================================================================
# SECTION 13: SOURCE NAT (NETWORK ADDRESS TRANSLATION)
# ============================================================================
# Rewrites source IP of outgoing packets to match the WAN interface IP.
#
# WHY NAT IS REQUIRED:
#   
#   LAN uses private IPs (192.168.10.x) which are not routable on internet.
#   
#   Without NAT:
#     LAN packet: 192.168.10.100 → 1.1.1.1
#     ISP receives this packet
#     ISP cannot route response (192.168.10.x is private)
#     Connection fails
#   
#   With NAT:
#     Outgoing: 192.168.10.100 → 1.1.1.1
#     NAT rewrites to: 192.168.2.100 → 1.1.1.1
#     ISP sees routable source IP
#     Response: 1.1.1.1 → 192.168.2.100
#     NAT rewrites back to: 1.1.1.1 → 192.168.10.100
#     LAN client receives response
#
# WHY SEPARATE RULES PER INTERFACE:
#   
#   Each WAN has different public IP:
#     WAN1: 192.168.2.100
#     WAN2: 192.168.0.100
#   
#   Packet exiting ether1 must use 192.168.2.100 as source
#   Packet exiting ether2 must use 192.168.0.100 as source
#   
#   ISPs often filter by source IP:
#     - ISP1 drops packets with ISP2's IP as source
#     - ISP2 drops packets with ISP1's IP as source
#   
#   Correct source IP per interface is REQUIRED.
#
# src-nat vs masquerade:
#   
#   src-nat: Static NAT to specified address
#     - Faster (no need to look up interface IP)
#     - Requires manual update if IP changes
#     - Best for static business IPs
#   
#   masquerade: Dynamic NAT to interface's current IP
#     - Automatically adapts to IP changes
#     - Slightly higher CPU usage
#     - Best for dynamic IPs (DHCP, PPPoE, LTE)
#   
#   This configuration uses src-nat because WAN IPs are static.

/ip firewall nat
add chain=srcnat out-interface=ether1 action=src-nat to-addresses=192.168.2.100 comment="NAT-WAN1"
add chain=srcnat out-interface=ether2 action=src-nat to-addresses=192.168.0.100 comment="NAT-WAN2"


# ============================================================================
# SECTION 14: FIREWALL - INPUT CHAIN
# ============================================================================
# Controls access TO the router itself.
#
# SECURITY MODEL:
#   
#   Default Deny: Drop everything unless explicitly allowed
#   
#   Allowed:
#     - Established/related connections (ongoing communications)
#     - LAN access to all router services
#   
#   Denied:
#     - Invalid packets (malformed, spoofed, etc.)
#     - New connections from WAN (management protection)
#
# RULE ORDER MATTERS:
#   
#   Rules are processed top-to-bottom
#   First match wins
#   Most specific rules first, most general rules last

/ip firewall filter

# ---------------------------------------------------------------------------
# RULE 1: ACCEPT ESTABLISHED/RELATED
# ---------------------------------------------------------------------------
# Allow ongoing communications and related connections.
#
# established: Connection already exists and is active
#              Example: Response to router's DNS query
#
# related: New connection related to existing connection
#          Example: FTP data connection (related to FTP control connection)
#
# untracked: Connection not tracked by connection tracking
#            Rare, but included for completeness
#
# WHY THIS IS FIRST:
#   Most packets are part of existing connections
#   Accept these immediately without checking other rules
#   Improves performance

add chain=input action=accept connection-state=established,related,untracked comment="INPUT-ESTABLISHED"


# ---------------------------------------------------------------------------
# RULE 2: DROP INVALID
# ---------------------------------------------------------------------------
# Drop malformed or invalid packets.
#
# WHAT IS INVALID:
#   - Packets that don't match any known connection
#   - Packets with impossible flag combinations
#   - Packets that violate protocol specifications
#   - Potential spoofing or attack traffic
#
# WHY DROP EARLY:
#   No legitimate traffic should be invalid
#   Dropping saves processing time for remaining rules
#   Protects against certain attacks

add chain=input action=drop connection-state=invalid comment="INPUT-INVALID"


# ---------------------------------------------------------------------------
# RULE 3: ALLOW LAN ACCESS
# ---------------------------------------------------------------------------
# LAN clients can access ALL router services.
#
# SERVICES INCLUDED:
#   - Web interface (HTTP/HTTPS)
#   - Winbox
#   - SSH
#   - Telnet (if enabled)
#   - API
#   - DNS requests
#   - DHCP requests
#   - Ping
#   - Everything else
#
# WHY NO RESTRICTIONS FROM LAN:
#   - LAN is trusted network
#   - Administrators need full access
#   - Convenience for management
#
# IF YOU WANT MORE SECURITY:
#   Add rules above this one to allow only specific services
#   Then change this rule to drop instead of accept

add chain=input action=accept in-interface=bridge2 comment="INPUT-LAN"


# ---------------------------------------------------------------------------
# RULE 4: DROP EVERYTHING ELSE
# ---------------------------------------------------------------------------
# Default deny for all remaining traffic.
#
# WHAT THIS BLOCKS:
#   - New connections from WAN interfaces
#   - Attempts to access router from internet
#   - Port scans from WAN
#   - Brute force attacks on SSH/Winbox
#   - Unauthorized management access
#
# CONSEQUENCE:
#   Remote management from internet is BLOCKED
#   
#   If you need remote management:
#     1. Set up VPN first
#     2. Or add rules above to allow specific source IPs
#     3. Never allow unrestricted WAN access

add chain=input action=drop comment="INPUT-DROP-OTHER"


# ============================================================================
# SECTION 15: FIREWALL - FORWARD CHAIN
# ============================================================================
# Controls traffic THROUGH the router (LAN ↔ WAN).
#
# SECURITY MODEL:
#   
#   Default Deny: Drop everything unless explicitly allowed
#   
#   Allowed:
#     - Established/related connections (ongoing communications)
#     - LAN to both WANs (internet access)
#     - WAN to LAN for port forwards only (dstnat)
#   
#   Denied:
#     - Invalid packets
#     - Unsolicited inbound connections from internet

# ---------------------------------------------------------------------------
# RULE 1: ACCEPT ESTABLISHED/RELATED
# ---------------------------------------------------------------------------
# Allow ongoing communications.
#
# EXAMPLES:
#   - LAN client browsing web: request → response
#   - LAN client streaming video: initial request → data stream
#   - Port forwarded connection: external → internal server + responses
#
# WHY THIS IS FIRST:
#   Most forwarded traffic is part of existing connections
#   Accept immediately without checking other rules

add chain=forward action=accept connection-state=established,related,untracked comment="FORWARD-ESTABLISHED"


# ---------------------------------------------------------------------------
# RULE 2: DROP INVALID
# ---------------------------------------------------------------------------
# Drop malformed packets being forwarded.
#
# PROTECTS AGAINST:
#   - Spoofed packets
#   - Malformed protocol traffic
#   - Certain types of attacks targeting LAN clients

add chain=forward action=drop connection-state=invalid comment="FORWARD-INVALID"


# ---------------------------------------------------------------------------
# RULES 3-4: ALLOW LAN TO BOTH WANS
# ---------------------------------------------------------------------------
# LAN clients can initiate connections to internet via either WAN.
#
# HOW THIS WORKS WITH PCC:
#   
#   1. LAN client initiates connection (new)
#   2. PCC marks connection (wan1-conn or wan2-conn)
#   3. Routing mark applied (to-wan1 or to-wan2)
#   4. Routing table determines out-interface (ether1 or ether2)
#   5. This firewall rule allows the forwarding
#   6. NAT rewrites source IP
#   7. Packet exits via chosen WAN
#
# WHY TWO RULES:
#   Need explicit allow for each out-interface
#   Ensures both WANs can be used by PCC

add chain=forward action=accept in-interface=bridge2 out-interface=ether1 comment="LAN-WAN1"
add chain=forward action=accept in-interface=bridge2 out-interface=ether2 comment="LAN-WAN2"


# ---------------------------------------------------------------------------
# RULES 5-6: ALLOW PORT FORWARDS
# ---------------------------------------------------------------------------
# Allow inbound connections from internet IF there's a port forward configured.
#
# connection-nat-state=dstnat means:
#   "This connection has been destination-NATted"
#   
#   In other words:
#   - A dstnat rule in NAT table matched this connection
#   - Destination IP was rewritten (WAN IP → LAN IP)
#   - This is a port forward
#
# EXAMPLE PORT FORWARD FLOW:
#   
#   NAT rule: (to be added separately if needed)
#   /ip firewall nat
#   add chain=dstnat in-interface=ether1 protocol=tcp dst-port=80 \
#       action=dst-nat to-addresses=192.168.10.100 to-ports=80
#   
#   Incoming packet: 1.2.3.4 → 192.168.2.100:80
#   
#   After dstnat:
#     Destination rewritten: 1.2.3.4 → 192.168.10.100:80
#     connection-nat-state becomes dstnat
#   
#   Forward chain:
#     Packet matches PORTFORWARD-WAN1 rule
#     Forwarding allowed
#   
#   Packet reaches internal server: 1.2.3.4 → 192.168.10.100:80
#
# WHY TWO RULES:
#   Port forwards can be on either WAN
#   Need explicit allow for each in-interface
#
# SECURITY:
#   Only explicitly configured port forwards are allowed
#   Random inbound connections are still blocked (by final rule)

add chain=forward action=accept in-interface=ether1 connection-nat-state=dstnat comment="PORTFORWARD-WAN1"
add chain=forward action=accept in-interface=ether2 connection-nat-state=dstnat comment="PORTFORWARD-WAN2"


# ---------------------------------------------------------------------------
# RULE 7: DROP EVERYTHING ELSE
# ---------------------------------------------------------------------------
# Default deny for all remaining forwarded traffic.
#
# WHAT THIS BLOCKS:
#   
#   From WAN:
#     - Port scans
#     - Connection attempts to LAN without port forward
#     - Attacks targeting LAN clients
#   
#   From LAN:
#     - Unlikely to match (previous rules cover legitimate LAN traffic)
#     - Safety net in case of misconfiguration
#
# CONSEQUENCE:
#   Strong protection: LAN is not accessible from internet
#   Only explicitly configured port forwards work

add chain=forward action=drop comment="FORWARD-DROP-OTHER"


# ============================================================================
# SECTION 16: MANAGEMENT SECURITY
# ============================================================================
# Restricts access to router management services.
#
# PRINCIPLE: Minimize attack surface
#   
#   Disable: Services you don't use
#   Restrict: Services you do use to LAN only
#   Secure: Services that remain enabled

# ---------------------------------------------------------------------------
# DISABLE INSECURE/UNUSED SERVICES
# ---------------------------------------------------------------------------

/ip service
set [find where name="telnet"] disabled=yes    # Unencrypted, insecure
set [find where name="ftp"] disabled=yes       # Unencrypted, rarely needed
set [find where name="www"] disabled=yes       # Unencrypted web interface
set [find where name="www-ssl"] disabled=yes   # HTTPS web interface (disable if using Winbox only)
set [find where name="api"] disabled=yes       # Unencrypted API
set [find where name="api-ssl"] disabled=yes   # Encrypted API (disable if unused)

# RESTRICT SSH AND WINBOX TO LAN ONLY
set [find where name="ssh"] address=192.168.10.0/24      # SSH from LAN only
set [find where name="winbox"] address=192.168.10.0/24   # Winbox from LAN only

# ---------------------------------------------------------------------------
# SECURE SSH
# ---------------------------------------------------------------------------
# Require strong cryptography for SSH connections.

/ip ssh
set strong-crypto=yes


# ---------------------------------------------------------------------------
# MAC SERVER RESTRICTIONS
# ---------------------------------------------------------------------------
# MAC-based discovery and management tools should only work on LAN.
#
# mac-server: MAC telnet server
# mac-winbox: Winbox access via MAC address (when IP is unknown)

/tool mac-server
set allowed-interface-list=LAN

/tool mac-server mac-winbox
set allowed-interface-list=LAN


# ---------------------------------------------------------------------------
# NEIGHBOR DISCOVERY
# ---------------------------------------------------------------------------
# Restricts which interfaces broadcast neighbor discovery.
#
# Prevents WAN-side devices from discovering this router.

/ip neighbor discovery-settings
set discover-interface-list=LAN


# ============================================================================
# SECTION 17: SYSTEM CONFIGURATION
# ============================================================================
# Basic system settings.

# ---------------------------------------------------------------------------
# TIMEZONE
# ---------------------------------------------------------------------------
# Set to your local timezone for accurate logging timestamps.
#
# CHANGE THIS TO YOUR LOCATION:
# Examples:
#   America/New_York
#   Europe/London
#   Asia/Tokyo
#   Australia/Sydney

/system clock
set time-zone-name=Asia/Tehran


# ---------------------------------------------------------------------------
# ROUTER IDENTITY
# ---------------------------------------------------------------------------
# Descriptive name for this router.
# Shows in Winbox, logs, and neighbor discovery.

/system identity
set name=hEX-PCC-DualWAN


# ============================================================================
# CONFIGURATION COMPLETE
# ============================================================================

:put "============================================"
:put "DUAL WAN PCC CONFIGURATION COMPLETED"
:put "============================================"
:put ""
:put "NEXT STEPS:"
:put "1. Test health checks with:"
:put "   /ping 1.1.1.1 src-address=192.168.2.100 count=5"
:put "   /ping 8.8.8.8 src-address=192.168.2.100 count=5"
:put "   /ping 9.9.9.9 src-address=192.168.0.100 count=5"
:put "   /ping 208.67.222.222 src-address=192.168.0.100 count=5"
:put ""
:put "2. Verify routes are active:"
:put "   /ip route print detail where dst-address=0.0.0.0/0"
:put ""
:put "3. Monitor PCC distribution:"
:put "   /ip firewall mangle print stats"
:put ""
:put "4. Check active connections:"
:put "   /ip firewall connection print where connection-mark~\"wan\""
:put ""
:put "============================================"


# ============================================================================
# END OF CONFIGURATION
# ============================================================================
#
# ARCHITECTURE SUMMARY:
#   • 50/50 PCC load balancing via hash-based connection distribution
#   • Recursive health monitoring with 2 targets per WAN for reliability
#   • Independent failover per routing table (crossover backup)
#   • Full security: LAN trusted, WAN blocked except port forwards
#   • Management restricted to LAN only
#
# EXPECTED BEHAVIOR:
#   • Normal: ~50% connections via WAN1, ~50% via WAN2
#   • WAN1 fails: 100% connections via WAN2
#   • WAN2 fails: 100% connections via WAN1
#   • Single health target fails: WAN remains active via other target
#   • Router's own traffic: WAN1 primary, WAN2 backup
#
# IMPORTANT NOTES:
#   • Load balancing is per-connection, NOT per-packet
#   • Single downloads use one WAN only (don't combine speeds)
#   • Multiple concurrent connections distribute across both WANs
#   • Failover is automatic but existing connections may break
#     (applications will reconnect automatically)
#
# FOR SUPPORT:
#   See documentation: README-dual-wan.md
#   See concepts guide: PCC-CONCEPTS.md
#   See verification commands: verification-commands.md
#
# ============================================================================
