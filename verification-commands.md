# MikroTik PCC Verification and Troubleshooting Commands

Complete reference for verifying, monitoring, and troubleshooting PCC load balancing configurations.

## 📋 Table of Contents

1. [Initial Verification](#initial-verification)
2. [Monitoring PCC Distribution](#monitoring-pcc-distribution)
3. [Health Check Status](#health-check-status)
4. [Connection Tracking](#connection-tracking)
5. [Traffic Analysis](#traffic-analysis)
6. [Troubleshooting](#troubleshooting)
7. [Performance Testing](#performance-testing)

---

## Initial Verification

### Check IP Addresses
Verify all WAN and LAN IP addresses are configured correctly.

```bash
/ip address print
```

**Expected output**: All interfaces should have correct IP addresses assigned.

### Check Routing Tables
Verify that policy routing tables exist.

```bash
/routing table print
```

**Expected output for Dual WAN**:
```
# NAME         FIB
0 main         yes
1 to-wan1      yes
2 to-wan2      yes
```

**Expected output for Triple WAN**:
```
# NAME         FIB
0 main         yes
1 to-WAN1      yes
2 to-WAN2      yes
3 to-WAN3      yes
```

### Check All Routes
View all configured routes with details.

```bash
/ip route print detail
```

### Check Routes with Gateway Monitoring
View only routes that have gateway health checks enabled.

```bash
/ip route print detail where check-gateway=ping
```

**What to look for**:
- Routes should show `check-gateway=ping`
- Active routes show as `reachable`
- Failed gateways show as `unreachable`

---

## Monitoring PCC Distribution

### View Mangle Rules
Check all mangle rules and their packet/byte counters.

```bash
/ip firewall mangle print stats
```

**What to check**:
- PCC classify rules should have incrementing packet counts
- Both WAN1 and WAN2 rules should show traffic (roughly equal for 50/50)
- If one WAN shows zero packets, PCC is not working

### View Mangle Rules with Details
```bash
/ip firewall mangle print detail
```

### Reset Mangle Counters
Useful to see fresh statistics after configuration changes.

```bash
/ip firewall mangle reset-counters-all
```

Then monitor for a few minutes and check stats again.

---

## Health Check Status

### View Route Status
Check which routes are active and which gateways are reachable.

```bash
/ip route print where check-gateway=ping
```

**Status indicators**:
- `A` = Active route (gateway is reachable)
- `S` = Static route
- `c` = Connected route

### Monitor Gateway Reachability
Continuously monitor route status.

```bash
/ip route print where check-gateway=ping interval=2s
```

Press `Ctrl+C` to stop.

### Check Specific Routing Table
View routes in a specific policy table.

```bash
# For to-wan1 table
/ip route print where routing-table=to-wan1

# For to-wan2 table
/ip route print where routing-table=to-wan2
```

### Netwatch Status (if configured)
Check netwatch monitoring status.

```bash
/tool netwatch print detail
```

**Expected output**:
- Shows each monitored gateway
- Status: up or down
- Last up/down time

---

## Connection Tracking

### View All Active Connections
```bash
/ip firewall connection print
```

### Filter Connections by Mark
View only connections marked for specific WANs.

```bash
# WAN1 connections
/ip firewall connection print where connection-mark=wan1-conn

# WAN2 connections
/ip firewall connection print where connection-mark=wan2-conn

# All WAN-marked connections
/ip firewall connection print where connection-mark~"wan"
```

### Count Connections per WAN
```bash
# WAN1
/ip firewall connection print count-only where connection-mark=wan1-conn

# WAN2
/ip firewall connection print count-only where connection-mark=wan2-conn
```

### Continuous Connection Monitoring
```bash
/ip firewall connection print interval=2s where connection-mark~"wan"
```

### Clear All Connections
Useful for forcing reconnections through available WANs after failover.

```bash
/ip firewall connection remove [find]
```

**Warning**: This will drop all active connections!

### Clear Specific WAN Connections
```bash
# Clear WAN1 connections
/ip firewall connection remove [find connection-mark=wan1-conn]

# Clear WAN2 connections
/ip firewall connection remove [find connection-mark=wan2-conn]
```

---

## Traffic Analysis

### Monitor Interface Traffic
Real-time traffic monitoring on all interfaces.

```bash
/interface monitor-traffic ether1,ether2,bridge2
```

For triple WAN:
```bash
/interface monitor-traffic ether1,ether2,lte1,bridge-LAN
```

### Check Interface Statistics
```bash
/interface print stats
```

### Monitor Specific Interface
```bash
/interface monitor-traffic ether1 once
```

### View NAT Rules
Check that NAT rules are configured correctly.

```bash
/ip firewall nat print
```

**Expected**: Separate masquerade or src-nat rules for each WAN interface.

### NAT Rule Statistics
```bash
/ip firewall nat print stats
```

Shows packet and byte counts for each NAT rule.

---

## Troubleshooting

### Test Gateway Connectivity

#### Ping Each Gateway from Router
```bash
# WAN1 gateway
/ping [YOUR_WAN1_GATEWAY] interface=ether1 count=10

# WAN2 gateway
/ping [YOUR_WAN2_GATEWAY] interface=ether2 count=10

# For triple WAN - LTE gateway
/ping [YOUR_LTE_GATEWAY] interface=lte1 count=10
```

#### Ping Public IPs via Specific Interface
```bash
# Via WAN1
/ping 1.1.1.1 interface=ether1 count=10

# Via WAN2
/ping 8.8.8.8 interface=ether2 count=10
```

### Traceroute Testing
Check routing path to external hosts.

```bash
# Default routing (should use main table)
/tool traceroute 1.1.1.1

# Via specific interface
/tool traceroute 1.1.1.1 interface=ether1
/tool traceroute 8.8.8.8 interface=ether2
```

### DNS Testing
```bash
# Check DNS settings
/ip dns print

# Test DNS resolution
/ping google.com count=5

# View DNS cache
/ip dns cache print
```

### Check Firewall Rules
```bash
# Input chain
/ip firewall filter print chain=input

# Forward chain
/ip firewall filter print chain=forward

# All rules with statistics
/ip firewall filter print stats
```

### View DHCP Leases
Check if LAN clients are getting IP addresses.

```bash
/ip dhcp-server lease print
```

### Check DHCP Server Status
```bash
/ip dhcp-server print
```

### View System Logs
Check for errors or warnings.

```bash
/log print where topics~"error"
/log print where topics~"warning"
/log print where topics~"route"
```

### Check System Resources
Verify router is not overloaded.

```bash
/system resource print
```

**What to check**:
- CPU load (should be low, <50%)
- Free memory (should be available)
- Uptime

### View Active Processes
```bash
/system resource cpu print
```

---

## Performance Testing

### Bandwidth Test Between Routers
If you have another MikroTik on the other end:

```bash
/tool bandwidth-test [remote-router-ip] protocol=tcp direction=both
```

### Speed Test from LAN Client
From a computer on the LAN:
1. Open multiple browser tabs
2. Run speed tests simultaneously
3. Each test should use a different WAN

**Services to use**:
- speedtest.net
- fast.com
- Multiple terminal windows with curl/wget

### Connection Distribution Test

1. **Reset mangle counters**:
   ```bash
   /ip firewall mangle reset-counters-all
   ```

2. **Generate traffic** from LAN clients

3. **Check distribution after 5 minutes**:
   ```bash
   /ip firewall mangle print stats where comment~"PCC"
   ```

4. **Expected**: Both WAN classification rules should show similar packet counts (±10%)

### Failover Test

#### Test WAN1 Failure
1. **Check current status**:
   ```bash
   /ip route print where check-gateway=ping
   ```

2. **Simulate WAN1 failure**:
   ```bash
   /interface disable ether1
   ```

3. **Monitor route changes**:
   ```bash
   /ip route print where check-gateway=ping
   ```
   
   WAN1 routes should become inactive, WAN2 should take over.

4. **Check active connections shift to WAN2**:
   ```bash
   /ip firewall connection print where connection-mark~"wan"
   ```

5. **Re-enable WAN1**:
   ```bash
   /interface enable ether1
   ```

6. **Verify WAN1 routes become active again**:
   ```bash
   /ip route print where check-gateway=ping
   ```

#### Test WAN2 Failure
Repeat above steps for ether2.

---

## Diagnostic Scripts

### Quick Health Check Script
Create a script to run all basic checks:

```bash
/system script add name=pcc-health-check source={
  :put "=== IP Addresses ===";
  /ip address print brief;
  :put "\n=== Routing Tables ===";
  /routing table print;
  :put "\n=== Route Status ===";
  /ip route print where check-gateway=ping;
  :put "\n=== PCC Stats ===";
  /ip firewall mangle print stats where comment~"PCC";
  :put "\n=== Connection Distribution ===";
  :put ("WAN1: " . [:len [/ip firewall connection find connection-mark=wan1-conn]]);
  :put ("WAN2: " . [:len [/ip firewall connection find connection-mark=wan2-conn]]);
}
```

**Run the script**:
```bash
/system script run pcc-health-check
```

### Automated Connection Counter
Continuously display connection distribution:

```bash
:while (true) do={
  :put ("WAN1: " . [:len [/ip firewall connection find connection-mark=wan1-conn]] . \
        " | WAN2: " . [:len [/ip firewall connection find connection-mark=wan2-conn]]);
  :delay 2s;
}
```

Press `Ctrl+C` to stop.

---

## Common Issues and Checks

### Issue: All traffic uses only one WAN

**Checks**:
```bash
# 1. Check if both gateways are reachable
/ip route print where check-gateway=ping

# 2. Check mangle rules are matching
/ip firewall mangle print stats where comment~"PCC"

# 3. Check connection marks
/ip firewall connection print where connection-mark~"wan"

# 4. Clear connections and test
/ip firewall connection remove [find]
```

### Issue: No internet access

**Checks**:
```bash
# 1. Check IP addresses
/ip address print

# 2. Check routes
/ip route print

# 3. Test gateway connectivity
/ping [YOUR_WAN1_GATEWAY] interface=ether1
/ping [YOUR_WAN2_GATEWAY] interface=ether2

# 4. Check NAT
/ip firewall nat print

# 5. Check firewall
/ip firewall filter print chain=forward
```

### Issue: Slow or no failover

**Checks**:
```bash
# 1. Check gateway monitoring
/ip route print detail where check-gateway=ping

# 2. Check if netwatch is configured
/tool netwatch print

# 3. Manually test failover
/interface disable ether1
# Wait 10 seconds
/ip route print where check-gateway=ping
# Should show WAN1 routes as inactive
```

### Issue: Connections drop during failover

**This is expected behavior** with PCC. When a WAN fails:
- Existing connections on that WAN are lost
- New connections use available WAN(s)
- Netwatch can speed up detection and cleanup

**Mitigation**:
```bash
# Enable netwatch for faster failover
/tool netwatch
add host=[YOUR_WAN1_GATEWAY] interval=5s timeout=2s \
    down-script="/ip firewall connection remove [find connection-mark=wan1-conn]"
```

---

## Logging and Monitoring

### Enable Route Logging
```bash
/system logging
add topics=route,!debug action=memory
```

### View Route Logs
```bash
/log print where topics~"route"
```

### Enable Firewall Logging (for debugging)
```bash
# Log PCC classification
/ip firewall mangle
set [find comment~"PCC classify"] log=yes log-prefix=PCC
```

**Check logs**:
```bash
/log print where message~"PCC"
```

**Disable after debugging** (generates lots of logs):
```bash
/ip firewall mangle
set [find log=yes] log=no
```

---

## Scheduled Checks

### Auto Health Check Every Hour
```bash
/system scheduler add name=hourly-health-check interval=1h \
    on-event="/system script run pcc-health-check"
```

### Auto Connection Cleanup on WAN Failure
```bash
# Already covered by netwatch, but can also use scheduler
/system scheduler add name=connection-cleanup interval=30s \
    on-event={
      :if ([/ip route get [find comment~"WAN1" and check-gateway=ping] active] = false) do={
        /ip firewall connection remove [find connection-mark=wan1-conn];
      }
    }
```

---

## Export Configuration for Backup

### Export Current Config
```bash
/export file=current-pcc-config
```

### Export Only PCC-Related Configuration
```bash
/routing table export file=routing-tables
/ip route export file=routes
/ip firewall mangle export file=mangle
/ip firewall nat export file=nat
```

---

## Quick Reference Card

### Essential Commands
| Command | Purpose |
|---------|---------|
| `/ip address print` | View IP configuration |
| `/ip route print where check-gateway=ping` | View route health |
| `/ip firewall mangle print stats` | View PCC statistics |
| `/ip firewall connection print where connection-mark~"wan"` | View active connections |
| `/interface monitor-traffic ether1,ether2` | Monitor bandwidth |
| `/ping [gateway] interface=[wan]` | Test specific WAN |
| `/log print where topics~"error"` | Check for errors |

### Quick Tests
```bash
# Full system check (run all these in sequence)
/ip address print
/routing table print
/ip route print where check-gateway=ping
/ip firewall mangle print stats where comment~"PCC"
/ip firewall connection print count-only where connection-mark~"wan"
/ping 1.1.1.1 count=5
/ping 8.8.8.8 count=5
```

---

**Remember**: Always backup before making changes!

```bash
/system backup save name=before-changes
/export file=before-changes-export
```
