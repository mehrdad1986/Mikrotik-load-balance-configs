# Dual WAN vs Triple WAN PCC Comparison

A comprehensive comparison to help you choose the right PCC configuration for your needs.

## 📊 Quick Comparison Table

| Feature | Dual WAN PCC | Triple WAN PCC |
|---------|--------------|----------------|
| **Number of WANs** | 2 | 3 |
| **Interfaces** | ether1, ether2 | ether1, ether2, lte1 |
| **Load Distribution** | 50/50 | 33/33/33 |
| **Routing Tables** | 2 policy tables (to-wan1, to-wan2) | 3 policy tables (to-WAN1, to-WAN2, to-WAN3) |
| **Health Check Method** | Recursive (4 public IPs) | Gateway ping |
| **Netwatch** | Not included | Optional, recommended |
| **LTE Support** | No | Yes |
| **LAN Bridge Name** | bridge2 | bridge-LAN |
| **LAN Default Subnet** | 192.168.10.0/24 | 10.10.10.0/24 |
| **Configuration Complexity** | Simple | Moderate |
| **Script Lines** | ~200 | ~150 |
| **Router Services PCC** | No (output chain not configured) | Optional (commented out) |
| **FastTrack Handling** | Explicitly disabled | Should be manually disabled |
| **Best For** | Most scenarios | Advanced redundancy with LTE |

---

## 🔍 Detailed Feature Comparison

### Health Check Methods

#### Dual WAN (Recursive Routing)
```
Uses 4 public IPs as health check targets:
- WAN1: 1.1.1.1 (Cloudflare) + 8.8.8.8 (Google)
- WAN2: 9.9.9.9 (Quad9) + 208.67.222.222 (OpenDNS)

Each IP is pinned to its WAN with scope=10 routes
Main and policy routes use these IPs as recursive gateways
```

**Advantages**:
- More reliable (checks internet connectivity, not just gateway)
- Two targets per WAN (redundancy in monitoring)
- Automatically fails over if one target fails but other is reachable

**Disadvantages**:
- Slightly more complex configuration
- More routes in routing table

#### Triple WAN (Gateway Ping)
```
Directly pings each WAN gateway:
- WAN1: check-gateway=ping to [YOUR_WAN1_GATEWAY]
- WAN2: check-gateway=ping to [YOUR_WAN2_GATEWAY]
- WAN3: check-gateway=ping to [YOUR_LTE_GATEWAY]
```

**Advantages**:
- Simpler configuration
- Fewer routes
- Lower resource usage

**Disadvantages**:
- Only checks gateway (not internet connectivity)
- If gateway responds but ISP is down, router won't know

**Recommendation**: For triple WAN, consider adding recursive routing like dual WAN for more reliable monitoring.

---

### Failover Mechanisms

#### Dual WAN
**Main Table**:
- WAN1 primary (distance=1, via 1.1.1.1 and 8.8.8.8)
- WAN2 backup (distance=2, via 9.9.9.9 and 208.67.222.222)

**to-wan1 Table**:
- WAN1 primary (distance=1)
- WAN2 backup (distance=2)

**to-wan2 Table**:
- WAN2 primary (distance=1)
- WAN1 backup (distance=2)

**Result**: If WAN1 fails completely (both health checks down), all traffic shifts to WAN2. If only one health check fails, WAN1 stays partially active.

#### Triple WAN
**Main Table**:
- WAN1 primary (distance=1)
- WAN2 secondary (distance=2)
- WAN3 tertiary (distance=3)

**to-WAN1 Table**:
- WAN1 primary → WAN2 → WAN3

**to-WAN2 Table**:
- WAN2 primary → WAN1 → WAN3

**to-WAN3 Table**:
- WAN3 primary → WAN1 → WAN2

**Result**: Each PCC bucket has three failover levels. LTE is typically the last resort across all tables.

---

### PCC Distribution

#### Dual WAN
```
per-connection-classifier=both-addresses-and-ports:2/0  → WAN1 (50%)
per-connection-classifier=both-addresses-and-ports:2/1  → WAN2 (50%)
```

**Characteristics**:
- Exactly 50/50 split
- Good for two similar speed connections
- Predictable distribution

**When to adjust**: If WANs have very different speeds (e.g., 100 Mbps + 50 Mbps), consider 2:1 ratio using different PCC denominators.

#### Triple WAN
```
per-connection-classifier=both-addresses-and-ports:3/0  → WAN1 (33%)
per-connection-classifier=both-addresses-and-ports:3/1  → WAN2 (33%)
per-connection-classifier=both-addresses-and-ports:3/2  → WAN3 (33%)
```

**Characteristics**:
- Equal 33/33/33 split
- May not be ideal if LTE is data-limited
- Simple to understand

**When to adjust**: For LTE as backup-only, use unequal ratios like 45/45/10.

---

### NAT Configuration

#### Dual WAN
```
/ip firewall nat
add chain=srcnat out-interface=ether1 action=src-nat to-addresses=[WAN1_IP]
add chain=srcnat out-interface=ether2 action=src-nat to-addresses=[WAN2_IP]
```

Uses **src-nat** with explicit IP addresses.

**Advantages**:
- Works with static IPs
- Explicit control

#### Triple WAN
```
/ip firewall nat
add chain=srcnat out-interface=ether1 action=masquerade
add chain=srcnat out-interface=ether2 action=masquerade
add chain=srcnat out-interface=lte1 action=masquerade
```

Uses **masquerade** (dynamic NAT).

**Advantages**:
- Works with dynamic IPs (common for LTE)
- Automatically adapts to IP changes

**Note**: Both approaches work fine. Choose based on whether you have static or dynamic WAN IPs.

---

### Firewall Configuration

#### Dual WAN
Includes **complete firewall** rules:

**Input Chain**:
- Accept established/related
- Drop invalid
- Accept from LAN
- Drop all other (blocks WAN management)

**Forward Chain**:
- Accept established/related
- Drop invalid
- Allow LAN → WAN1
- Allow LAN → WAN2
- Allow port forwarding (dstnat)
- Drop all other

**Included by default**: Yes, comprehensive protection.

#### Triple WAN
Firewall rules are **commented out** (optional):

```
# /ip firewall filter
# add chain=input ...
```

**Why**: Assumes you may already have firewall rules or want to add your own.

**Recommendation**: Uncomment and customize the firewall rules, or add your own.

---

### Router-Originated Traffic

#### Dual WAN
**Not configured** - output chain rules are **not included**.

**Result**: Router's own traffic (DNS lookups, NTP, package updates) uses the main table:
- Primary via WAN1
- Backup via WAN2
- Not load balanced

**To enable**: Add output chain mangle rules similar to prerouting chain.

#### Triple WAN
**Commented out** (optional):

```
# /ip firewall mangle
# add chain=output ...
```

**Result by default**: Same as dual WAN - router uses main table.

**To enable**: Uncomment the output chain section.

---

### Netwatch Configuration

#### Dual WAN
**Not included**.

**Manual addition** (if desired):
```
/tool netwatch
add host=[WAN1_GATEWAY] interval=5s timeout=2s \
    down-script="/ip firewall connection remove [find connection-mark=wan1-conn]"
add host=[WAN2_GATEWAY] interval=5s timeout=2s \
    down-script="/ip firewall connection remove [find connection-mark=wan2-conn]"
```

#### Triple WAN
**Included but optional**:
```
/tool netwatch
add host=[YOUR_WAN1_GATEWAY] interval=5s timeout=2s \
    down-script="/ip firewall connection remove [find connection-mark=WAN1-conn]"
# ... (similar for WAN2 and WAN3)
```

**Purpose**: Clears existing connections immediately when a gateway goes down, forcing faster failover.

**Recommendation**: Enable for faster failover, especially important for real-time applications.

---

## 🎯 Use Case Recommendations

### Choose Dual WAN PCC If:

✅ You have two wired ISP connections  
✅ You want proven, production-ready configuration  
✅ You prefer recursive health checking  
✅ You don't need LTE backup  
✅ You want complete firewall rules included  
✅ Your setup is relatively straightforward

**Examples**:
- Home office with fiber + cable
- Small business with two business ISPs
- Branch office with redundant connections
- Anywhere with two reliable wired connections

### Choose Triple WAN PCC If:

✅ You have three WAN connections (including LTE)  
✅ You need LTE as backup/failover  
✅ You want maximum redundancy  
✅ You're comfortable customizing configuration  
✅ You prefer simpler gateway-based health checks  
✅ You may have dynamic IPs (LTE)

**Examples**:
- Remote sites with limited connectivity options
- Mobile deployments
- Critical infrastructure requiring 3+ ISPs
- Areas with unreliable wired connections
- Failover-first scenarios (LTE as emergency backup)

---

## 💰 Cost Considerations

### Dual WAN
**Hardware**:
- Any MikroTik with 2+ Ethernet ports
- RB750Gr3 (hEX) is perfect
- Budget: $50-100

**Monthly Costs**:
- Two wired ISP connections
- No data caps typically
- Predictable monthly cost

**Total**: Lower initial and ongoing costs

### Triple WAN
**Hardware**:
- MikroTik with LTE capability
- LtAP mini LTE, wAP LTE, or hAP ac3 LTE6
- Budget: $100-200+

**Monthly Costs**:
- Two wired ISPs
- LTE data plan (even if only for backup)
- May have data usage charges

**Total**: Higher initial hardware cost + ongoing LTE fees

**Cost Optimization for Triple WAN**:
- Use LTE only as backup (don't load balance with it)
- Choose low-cost LTE plan with minimal monthly data
- Monitor usage to avoid overage charges

---

## 🔧 Complexity Comparison

### Configuration Complexity

**Dual WAN**: ⭐⭐⭐ (3/5)
- More routes (recursive setup)
- More comprehensive (firewall included)
- Well-documented and tested

**Triple WAN**: ⭐⭐⭐⭐ (4/5)
- Three WANs to manage
- LTE configuration
- Netwatch scripting
- More variables to customize

### Maintenance Complexity

**Dual WAN**: ⭐⭐ (2/5)
- Two gateways to monitor
- Straightforward troubleshooting
- Fewer moving parts

**Triple WAN**: ⭐⭐⭐ (3/5)
- Three gateways to monitor
- LTE signal quality monitoring
- Data usage tracking
- More failover scenarios

---

## 🚀 Performance Comparison

### Throughput

Both configurations provide:
- **Per-connection**: Speed of one WAN link
- **Aggregate**: Sum of all WAN links (with many concurrent connections)

**Dual WAN**: Total throughput = WAN1 + WAN2  
**Triple WAN**: Total throughput = WAN1 + WAN2 + WAN3

**Note**: LTE typically has lower speeds and higher latency than wired connections.

### Latency

**Dual WAN**:
- Typically 10-50ms (wired connections)
- Consistent across both WANs (usually)

**Triple WAN**:
- Wired: 10-50ms
- LTE: 50-150ms (can vary significantly)
- Mixed latencies across different connection types

**Impact**: Applications sensitive to latency may perform poorly over LTE.

### Failover Speed

**Dual WAN**:
- Recursive routing: Detects failures in ~5-10 seconds
- Route changes: Almost instant
- Connection cleanup: Manual or via netwatch

**Triple WAN**:
- Gateway ping: Detects failures in ~2-5 seconds
- With netwatch: Connections cleared immediately
- Faster overall failover (when netwatch enabled)

---

## 📋 Migration Guide

### From Dual to Triple WAN

If you're running dual WAN and want to add LTE:

1. **Backup current config**:
   ```
   /system backup save name=dual-wan-backup
   /export file=dual-wan-export
   ```

2. **Install LTE modem/interface**

3. **Key changes needed**:
   - Add WAN3 IP address
   - Create to-WAN3 routing table
   - Add PCC rule for 3/2 (WAN3)
   - Add routes in all three policy tables
   - Add NAT rule for lte1
   - Add netwatch for LTE gateway

4. **Change PCC from 2/X to 3/X**:
   ```
   Old: per-connection-classifier=both-addresses-and-ports:2/0
   New: per-connection-classifier=both-addresses-and-ports:3/0
   ```

5. **Test thoroughly**

### From Triple to Dual WAN

If you want to simplify from triple to dual:

1. **Backup current config**

2. **Key changes needed**:
   - Remove WAN3 configuration
   - Delete to-WAN3 routing table
   - Remove PCC 3/2 rule
   - Change PCC from 3/X to 2/X
   - Remove LTE routes
   - Remove LTE NAT rule
   - Remove netwatch for LTE

3. **Consider adding recursive routing** (dual WAN best practice)

4. **Test thoroughly**

---

## 🛠️ Customization Recommendations

### Dual WAN Customizations

**Add Netwatch**:
```
/tool netwatch
add host=192.168.2.1 interval=5s timeout=2s \
    down-script="/ip firewall connection remove [find connection-mark=wan1-conn]"
add host=192.168.0.1 interval=5s timeout=2s \
    down-script="/ip firewall connection remove [find connection-mark=wan2-conn]"
```

**Add Output Chain PCC** (if router needs load balancing):
```
/ip firewall mangle
add chain=output connection-mark=no-mark per-connection-classifier=both-addresses-and-ports:2/0 \
    action=mark-connection new-connection-mark=wan1-conn passthrough=yes
add chain=output connection-mark=no-mark per-connection-classifier=both-addresses-and-ports:2/1 \
    action=mark-connection new-connection-mark=wan2-conn passthrough=yes
add chain=output connection-mark=wan1-conn action=mark-routing new-routing-mark=to-wan1
add chain=output connection-mark=wan2-conn action=mark-routing new-routing-mark=to-wan2
```

### Triple WAN Customizations

**Uncomment Firewall**:
Essential for security - uncomment the firewall section.

**Uncomment Output Chain**:
If router needs load balancing (optional).

**Use LTE as Backup Only** (don't load balance):
```
# Change PCC to only use WAN1 and WAN2:
per-connection-classifier=both-addresses-and-ports:2/0  → WAN1
per-connection-classifier=both-addresses-and-ports:2/1  → WAN2
# No PCC rule for WAN3

# LTE only used for failover via routing table distance
```

**Add Recursive Routing** (recommended):
Follow dual WAN pattern for more reliable health checks.

---

## 🏆 Verdict

### For Most Users: Dual WAN
- **Pros**: Simpler, cheaper, proven, complete
- **Cons**: Limited to two connections, no LTE
- **Best for**: 90% of use cases

### For Special Cases: Triple WAN
- **Pros**: Maximum redundancy, LTE backup
- **Cons**: More complex, higher cost, requires customization
- **Best for**: Remote sites, critical infrastructure, unreliable areas

---

## 📊 Real-World Performance

### Dual WAN Example
**Setup**: 100 Mbps fiber + 50 Mbps cable

**Single download**: 100 Mbps (or 50 Mbps, depending on which WAN)  
**Two downloads**: 150 Mbps total (100 + 50)  
**100 concurrent connections**: ~75 Mbps average per connection

### Triple WAN Example
**Setup**: 100 Mbps fiber + 50 Mbps cable + 20 Mbps LTE

**Single download**: 20-100 Mbps (depending on which WAN)  
**Three downloads**: 170 Mbps total (100 + 50 + 20)  
**High latency on LTE**: May affect real-time applications

**Cost**: LTE data usage = 1 GB/hour at full speed  
If LTE is only for backup, minimal data used.

---

## 📝 Summary Matrix

| Criteria | Dual WAN | Triple WAN | Winner |
|----------|----------|------------|--------|
| **Simplicity** | ✓ Simple | Complex | Dual |
| **Cost** | ✓ Lower | Higher | Dual |
| **Reliability** | ✓✓ Recursive health | ✓ Gateway ping | Dual |
| **Redundancy** | ✓✓ Two WANs | ✓✓✓ Three WANs | Triple |
| **LTE Support** | ✗ No | ✓ Yes | Triple |
| **Firewall** | ✓ Included | Optional | Dual |
| **Netwatch** | Optional | Included | Triple |
| **Documentation** | ✓✓✓ Comprehensive | ✓✓ Good | Dual |
| **Flexibility** | ✓✓ Good | ✓✓✓ High | Triple |

---

**Recommendation**: Start with **Dual WAN** unless you specifically need LTE or three connections. It's simpler, well-tested, and handles 90% of use cases perfectly.

If you need LTE backup or maximum redundancy, **Triple WAN** is the way to go, but be prepared to customize and monitor more closely.
