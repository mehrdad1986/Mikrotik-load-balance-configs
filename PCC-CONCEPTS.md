# Understanding PCC Load Balancing - Detailed Concepts

This document explains the fundamental concepts behind PCC (Per Connection Classifier) load balancing in MikroTik RouterOS.

## 📚 Table of Contents

1. [What is PCC?](#what-is-pcc)
2. [How PCC Works](#how-pcc-works)
3. [PCC vs Other Load Balancing Methods](#pcc-vs-other-methods)
4. [Connection Marking](#connection-marking)
5. [Routing Tables in RouterOS 7](#routing-tables-in-routeros-7)
6. [Gateway Health Monitoring](#gateway-health-monitoring)
7. [Failover Mechanisms](#failover-mechanisms)
8. [NAT and PCC](#nat-and-pcc)
9. [Common Misconceptions](#common-misconceptions)
10. [Best Practices](#best-practices)

---

## What is PCC?

**PCC (Per Connection Classifier)** is a MikroTik-specific method for load balancing network traffic across multiple WAN connections.

### Key Characteristics:

**Per-Connection, Not Per-Packet**:
- PCC distributes **entire connections**, not individual packets
- Once a connection is assigned to a WAN, all packets in that connection use the same WAN
- This maintains session stability and prevents packet reordering issues

**Hash-Based Distribution**:
- Uses a hash algorithm to deterministically assign connections to WANs
- Based on: source IP, destination IP, source port, destination port
- Same connection always gets the same WAN (session persistence)

**Transparent to Applications**:
- Applications see a normal internet connection
- No special client configuration needed
- Works with all protocols (TCP, UDP, ICMP, etc.)

### What PCC Is NOT:

❌ **Not Bandwidth Aggregation**: A single download doesn't get faster  
❌ **Not Per-Packet Load Balancing**: Each connection stays on one WAN  
❌ **Not ECMP**: Different routing mechanism (see comparison below)  
❌ **Not True Bonding**: Doesn't combine bandwidth at Layer 2

---

## How PCC Works

### Step-by-Step Process:

```
1. NEW CONNECTION ARRIVES FROM LAN
   ↓
2. CHECK: Is destination private/local?
   YES → Skip PCC, use direct routing
   NO → Continue to PCC
   ↓
3. HASH CONNECTION ATTRIBUTES
   Hash = f(src_ip, dst_ip, src_port, dst_port)
   ↓
4. DIVIDE HASH INTO BUCKETS
   Hash % NumWANs = Bucket Number
   Example: Hash % 2 = 0 or 1 (for dual WAN)
   ↓
5. MARK CONNECTION
   Bucket 0 → wan1-conn
   Bucket 1 → wan2-conn
   ↓
6. MARK ROUTING
   wan1-conn → to-wan1 routing table
   wan2-conn → to-wan2 routing table
   ↓
7. ROUTE LOOKUP
   Each routing table has routes via specific WAN
   ↓
8. APPLY NAT
   Outgoing interface determines source IP
   ↓
9. SEND PACKET
   All future packets in this connection follow same path
```

### Visual Example:

```
LAN Client 192.168.10.100 → Google 142.250.185.46

Connection: 192.168.10.100:54321 → 142.250.185.46:443

Hash Calculation:
  Input: 192.168.10.100 + 142.250.185.46 + 54321 + 443
  Hash: 0xABCD1234
  Bucket: 0xABCD1234 % 2 = 0
  Result: Assigned to WAN1

All packets in this HTTPS session use WAN1.

New connection 192.168.10.100:54322 → 142.250.185.46:443
  (Different source port = different hash = possibly WAN2)
```

---

## PCC vs Other Methods

### 1. PCC (Per Connection Classifier)

**How it works**: Hash-based connection distribution

**Pros**:
- ✅ Session stability (no packet reordering)
- ✅ Works with all protocols
- ✅ Simple configuration
- ✅ No client configuration needed
- ✅ Good distribution with many connections

**Cons**:
- ❌ Single connection uses one WAN only
- ❌ Requires many concurrent connections for best results
- ❌ Incompatible with FastTrack

**Best for**: 
- Multiple users/devices
- Mixed traffic (web, downloads, streaming)
- Budget-conscious setups

---

### 2. ECMP (Equal-Cost Multi-Path)

**How it works**: Routing decision per packet (or per flow, depending on implementation)

**Pros**:
- ✅ Built into routing protocols
- ✅ Standards-based
- ✅ Automatic failover
- ✅ No mangle rules needed

**Cons**:
- ❌ Can cause packet reordering
- ❌ May break some protocols
- ❌ Less granular control
- ❌ Not all ISPs support it properly

**Best for**:
- Enterprise environments
- When working with routing protocols (BGP, OSPF)
- More predictable network paths

---

### 3. True Bonding (EoIP + Bonding)

**How it works**: Layer 2 tunneling with aggregation at both ends

**Pros**:
- ✅ True bandwidth aggregation
- ✅ Single connections get combined speed
- ✅ Seamless failover

**Cons**:
- ❌ Requires MikroTik at both ends
- ❌ More complex setup
- ❌ Additional overhead (tunneling)
- ❌ Not suitable for typical ISP connections

**Best for**:
- Site-to-site links
- When you control both endpoints
- Need actual bandwidth aggregation

---

### 4. NTH (Nth Load Balancing)

**How it works**: Takes every Nth packet and routes it differently

**Pros**:
- ✅ Very simple
- ✅ Truly distributes all traffic

**Cons**:
- ❌ Breaks most protocols (packet reordering)
- ❌ Not recommended for internet traffic
- ❌ No session persistence

**Best for**:
- Testing only
- Specific lab scenarios
- **NOT recommended for production**

---

### Comparison Table:

| Method | Session Stability | Bandwidth per Connection | Complexity | Client Config |
|--------|------------------|-------------------------|------------|---------------|
| **PCC** | ✅ Excellent | Single WAN speed | Low | None |
| **ECMP** | ⚠️ Depends | Single WAN speed | Low | None |
| **Bonding** | ✅ Excellent | Combined speed | High | Both ends |
| **NTH** | ❌ Poor | Combined (broken) | Very Low | None |

---

## Connection Marking

### What Are Connection Marks?

Connection marks are metadata tags attached to connections tracked by the firewall's connection tracking system.

### Two Types of Marks:

**1. Connection Mark** (`connection-mark`):
- Applied to the entire connection (both directions)
- Persists for the lifetime of the connection
- Inherited by all packets in the connection

**2. Routing Mark** (`routing-mark`):
- Specifies which routing table to use
- Applied to packets based on connection mark
- Controls path selection

### Mark Flow:

```
NEW PACKET ARRIVES
   ↓
Is connection already marked? 
   YES → Use existing connection-mark
   NO → Apply PCC rule to mark it
   ↓
Connection-mark assigned (e.g., wan1-conn)
   ↓
Routing-mark applied based on connection-mark
   ↓
Packet uses specified routing table
```

### Why Use Marks?

**Session Persistence**:
- Once marked, all packets follow same path
- Prevents asymmetric routing issues

**Stateful**:
- Both directions of connection use same mark
- Return traffic automatically follows correct path

**Efficient**:
- Mark once per connection, not per packet
- Lower CPU overhead

---

## Routing Tables in RouterOS 7

### What Changed in RouterOS 7?

**RouterOS 6** used numeric routing marks:
```
routing-mark=to-wan1   # This was just a name, not a table
```

**RouterOS 7** uses actual named routing tables:
```
/routing table
add name=to-wan1 fib
```

### Key Concepts:

**FIB (Forwarding Information Base)**:
- The actual forwarding table used by the hardware
- `fib` flag activates the table for packet forwarding

**Multiple Routing Tables**:
- RouterOS 7 supports many independent routing tables
- Each table has its own routes
- Packets use table specified by routing-mark

**Route Resolution**:
- Tables can reference each other
- Example: `gateway=1.1.1.1@main` looks up 1.1.1.1 in main table

### PCC Routing Table Strategy:

**Main Table**:
- Used by router's own traffic
- Used by traffic with no routing-mark
- Has primary/backup default routes

**to-wan1 Table**:
- Used by connections marked for WAN1
- Primary route via WAN1 gateway
- Backup route via WAN2 gateway

**to-wan2 Table**:
- Used by connections marked for WAN2
- Primary route via WAN2 gateway
- Backup route via WAN1 gateway

### Failover Benefits:

Each PCC bucket has **independent failover**:
```
Scenario: WAN1 fails

Traffic marked for WAN1:
  to-wan1 table, distance=1 via WAN1 → FAILS
  to-wan1 table, distance=2 via WAN2 → ACTIVATES
  Result: WAN1 traffic fails over to WAN2

Traffic marked for WAN2:
  to-wan2 table, distance=1 via WAN2 → STILL ACTIVE
  Result: WAN2 traffic continues normally

Outcome: ALL traffic continues, some via backup path
```

---

## Gateway Health Monitoring

### How Monitoring Works:

**check-gateway=ping**:
- RouterOS sends ICMP ping to gateway
- Default interval: approximately every 10 seconds
- Marks route as "unreachable" if ping fails

**Route Status**:
```
/ip route print where check-gateway=ping

Flags: X, A, D, C, S, R, r
X - disabled
A - active (gateway reachable)
D - dynamic
C - connect, S - static, r - rip
R - bgp, m - mme, B - blackhole, U - unreachable, P - prohibit

0 AS  dst-address=0.0.0.0/0 gateway=192.168.2.1 ... check-gateway=ping
       ↑
   Active = Gateway is UP
```

### Two Monitoring Approaches:

**1. Simple Gateway Ping** (Triple WAN default):
```
add gateway=192.168.2.1 check-gateway=ping
```

**Checks**: Can router reach the gateway?

**Pros**: Simple, low overhead  
**Cons**: Gateway may be up but ISP link down

---

**2. Recursive Routing** (Dual WAN recommended):
```
# Pin specific IPs to each WAN
add dst-address=1.1.1.1/32 gateway=192.168.2.1 scope=10

# Use those IPs as recursive gateways
add dst-address=0.0.0.0/0 gateway=1.1.1.1 scope=30 target-scope=11 check-gateway=ping
```

**Checks**: Can router reach public internet via this WAN?

**Pros**: Detects ISP failures, not just gateway issues  
**Cons**: More routes, slightly more complex

---

### Scope Explanation:

**scope=10** (target scope):
- Route that provides the actual next-hop
- Example: 1.1.1.1 via gateway 192.168.2.1

**scope=30 target-scope=11**:
- Recursive route that depends on another route
- Requires a route with scope ≤ 11 (which 10 satisfies)
- Automatically activates/deactivates based on target reachability

---

## Failover Mechanisms

### How Failover Happens:

```
1. GATEWAY PING FAILS
   ↓
2. ROUTE MARKED UNREACHABLE
   Routes with that gateway become inactive
   ↓
3. BACKUP ROUTE ACTIVATES
   Next lowest distance route for same destination takes over
   ↓
4. EXISTING CONNECTIONS
   Packets use new route immediately
   But connections may break if WAN is truly down
   ↓
5. NEW CONNECTIONS
   Are routed via backup path from the start
```

### Failover Speed:

**Detection Time**:
- Gateway monitoring: ~10 seconds (default ping interval)
- With netwatch: ~2-5 seconds (configurable)

**Switchover Time**:
- Route activation: Instant (microseconds)
- Existing connections: May timeout if WAN is down
- New connections: Instant, use backup path

### Netwatch for Faster Failover:

```
/tool netwatch
add host=192.168.2.1 interval=5s timeout=2s \
    down-script="/ip firewall connection remove [find connection-mark=wan1-conn]"
```

**What it does**:
1. Monitors gateway every 5 seconds
2. If gateway doesn't respond within 2 seconds, triggers down-script
3. Clears all connections using failed WAN
4. Forces applications to reconnect via backup WAN

**Benefits**:
- Faster detection (5s vs 10s)
- Immediate connection cleanup
- Smoother failover for end users

---

## NAT and PCC

### Why NAT Per Interface?

When a packet exits a WAN interface, its source IP must be rewritten to match that WAN's IP address.

**Without correct NAT**:
```
LAN packet: 192.168.10.100 → Google
Routed via WAN1 (192.168.2.100)
But NAT uses WAN2 address (192.168.0.100)
ISP1 receives packet with ISP2's address → DROPPED
```

**With correct NAT**:
```
Packet exits ether1 → NAT to 192.168.2.100 ✓
Packet exits ether2 → NAT to 192.168.0.100 ✓
```

### NAT Methods:

**1. Masquerade** (dynamic NAT):
```
add chain=srcnat out-interface=ether1 action=masquerade
```
- Automatically uses interface's current IP
- Works with dynamic IPs (DHCP, PPPoE)
- Slightly higher CPU usage

**2. Source NAT** (static NAT):
```
add chain=srcnat out-interface=ether1 action=src-nat to-addresses=192.168.2.100
```
- Uses specified IP address
- Faster processing
- Requires manual update if IP changes

**Recommendation**: 
- Use **masquerade** for LTE/dynamic IPs
- Use **src-nat** for static business IPs (slightly better performance)

---

## Common Misconceptions

### ❌ Myth 1: "PCC combines bandwidth"

**Reality**: PCC distributes connections. A single download uses only one WAN's speed.

**Example**:
- WAN1: 100 Mbps
- WAN2: 50 Mbps
- One download: 50-100 Mbps (depends which WAN it gets)
- Ten simultaneous downloads: Combined ~150 Mbps total

---

### ❌ Myth 2: "50/50 PCC means exactly half the traffic"

**Reality**: PCC aims for 50/50 connection count, not 50/50 bandwidth.

**Example**:
- 10 connections total
- 5 connections → WAN1 (might be downloading huge files = 90 Mbps)
- 5 connections → WAN2 (might be just browsing = 10 Mbps)
- Distribution: 50/50 connections, but 90/10 bandwidth usage

---

### ❌ Myth 3: "Failover is seamless"

**Reality**: Existing connections break when their WAN fails. Only new connections use backup.

**What happens**:
- WAN1 fails
- Connections using WAN1: Break (timeout)
- Applications: Reconnect automatically
- New connection attempts: Use WAN2
- User experience: Brief interruption, then recovery

---

### ❌ Myth 4: "PCC works with FastTrack"

**Reality**: FastTrack bypasses mangle rules, breaking PCC.

**Problem**:
```
1. First few packets → Go through mangle, get marked
2. Connection fast-tracked
3. Remaining packets → Bypass mangle, lose routing-mark
4. Fall back to main routing table
5. Result: All traffic uses one WAN (usually WAN1)
```

**Solution**: Disable FastTrack when using PCC.

---

### ❌ Myth 5: "More WANs = Always better"

**Reality**: More WANs add complexity and may not help much.

**Considerations**:
- 2 WANs: Good balance of reliability and simplicity
- 3 WANs: Good if LTE is for backup only
- 4+ WANs: Rarely justified unless very high availability needed

**Diminishing returns**:
- 1→2 WANs: 2× capacity, 2× reliability
- 2→3 WANs: 1.5× capacity, marginal reliability gain
- 3→4 WANs: 1.33× capacity, management overhead increases

---

## Best Practices

### 1. Design Principles

**Use Different ISPs**:
- Don't get two connections from same provider
- Different upstream networks = real redundancy

**Match Speeds When Possible**:
- 100 Mbps + 100 Mbps: Excellent balance
- 100 Mbps + 50 Mbps: Works, but adjust PCC ratio
- 100 Mbps + 10 Mbps LTE: Keep LTE for failover only

**Plan Your Subnets**:
- Use non-overlapping private subnets
- Document everything
- Use meaningful names

---

### 2. Configuration Best Practices

**Always Backup First**:
```
/system backup save name=before-pcc
/export file=before-pcc-export
```

**Use Descriptive Comments**:
```
add comment="PCC classify connections to WAN1" ...
```

**Test Thoroughly**:
1. Verify both WANs work individually
2. Test PCC distribution
3. Test failover (unplug each WAN)
4. Test recovery (plug back in)

**Monitor After Deployment**:
```
/ip firewall mangle print stats
/ip route print where check-gateway=ping
/ip firewall connection print where connection-mark~"wan"
```

---

### 3. Troubleshooting Approach

**Problem: Traffic only uses one WAN**

Check in order:
1. Routes active? `/ip route print where check-gateway=ping`
2. Mangle rules matching? `/ip firewall mangle print stats`
3. Connections marked? `/ip firewall connection print`
4. FastTrack enabled? `/ip firewall filter print where action=fasttrack`

**Problem: Slow failover**

Solutions:
1. Enable netwatch for faster detection
2. Use recursive routing to public IPs
3. Tune check-gateway intervals (carefully)

**Problem: Asymmetric routing**

Causes:
- NAT rules missing or incorrect
- Inbound traffic not marked
- Port forwarding without proper connection marking

---

### 4. Optimization Tips

**For Few Users (1-5)**:
- PCC helps, but benefit is limited
- Consider simpler primary/backup setup
- Or ECMP if your environment supports it

**For Many Users (10+)**:
- PCC excels here
- Good connection distribution
- Clear benefit from load balancing

**For Mixed Traffic**:
- Keep LTE for failover, not load balancing (data costs)
- Use QoS to prioritize critical traffic
- Consider VoIP/gaming on specific WAN

---

### 5. Security Considerations

**Firewall Rules**:
- Always include input chain protection
- Block WAN→Router access
- Allow only dstnat from WAN

**Remote Management**:
- Disable WAN management by default
- Use VPN for remote access
- Or allow specific IPs only

**Monitoring**:
- Enable logging for troubleshooting
- Use SNMP for monitoring
- Set up alerts for WAN failures

---

## 📚 Additional Resources

**Official Documentation**:
- [MikroTik Wiki - PCC](https://wiki.mikrotik.com/wiki/Manual:PCC)
- [RouterOS Manual - Mangle](https://help.mikrotik.com/docs/display/ROS/Mangle)
- [RouterOS Manual - Policy Routing](https://help.mikrotik.com/docs/display/ROS/Policy+Routing)

**This Repository**:
- [Dual WAN README](README-dual-wan.md)
- [Triple WAN README](README-triple-wan.md)
- [Comparison Guide](COMPARISON.md)
- [Verification Commands](verification-commands.md)

---

**Last Updated**: 2026  
**Applies To**: RouterOS 7.x

This document is part of the MikroTik PCC Load Balancing configuration repository.
