# MikroTik Triple WAN PCC Load Balancing Configuration

Complete PCC (Per Connection Classifier) load balancing setup for MikroTik RouterOS 7.x with three WAN connections including LTE backup.

## 📋 Overview

This configuration provides:
- **33/33/33 load balancing** across three WAN connections
- **Automatic failover** with gateway health checks
- **Independent failover** across all three routing tables
- **LTE backup** for redundancy
- **Proper NAT** handling for each WAN interface

## 🔧 Network Topology

```
┌─────────────────────────────────────────┐
│          MikroTik Router                │
│       (with LTE capability)             │
├─────────────────────────────────────────┤
│  ether1 (WAN1) ──► ISP 1                │
│  ether2 (WAN2) ──► ISP 2                │
│  lte1 (WAN3)   ──► LTE Provider         │
│  ether4 (LAN)  ──┐                      │
│  ether5 (LAN)  ──┴─► bridge-LAN         │
└─────────────────────────────────────────┘
```

## 📝 Configuration Parameters

### WAN Interfaces
- **WAN1**: ether1 - Configure your ISP1 IP and gateway
- **WAN2**: ether2 - Configure your ISP2 IP and gateway
- **WAN3**: lte1 - LTE modem IP and gateway

### LAN Interface
- **Bridge**: bridge-LAN (ether4 + ether5)
- **LAN Network**: 10.10.10.0/24
- **LAN Gateway**: 10.10.10.1

### Failover Priority
1. **Primary**: WAN1 (ether1)
2. **Secondary**: WAN2 (ether2)
3. **Tertiary**: WAN3 (lte1) - LTE backup

## 🚀 Quick Start

### Before You Begin

1. **Backup your current configuration:**
   ```
   /system backup save name=before-triple-pcc
   /export file=before-triple-pcc-export
   ```

2. **Update the placeholders in the script:**
   - Replace `[YOUR_WAN1_IP]` with your WAN1 IP address
   - Replace `[YOUR_WAN1_GATEWAY]` with your WAN1 gateway
   - Replace `[YOUR_WAN2_IP]` with your WAN2 IP address
   - Replace `[YOUR_WAN2_GATEWAY]` with your WAN2 gateway
   - Replace `[YOUR_LTE_IP]` with your LTE IP address
   - Replace `[YOUR_LTE_GATEWAY]` with your LTE gateway

3. **Adjust LAN subnet if needed:**
   - Default is 10.10.10.0/24
   - Change to match your network

### Installation

1. Open WinBox or SSH to your MikroTik
2. Open a New Terminal
3. Copy and paste the entire script from `triple-wan-pcc-latest.rsc`
4. Wait for completion message: "TRIPLE WAN PCC CONFIGURATION APPLIED"

## ✅ Verification Commands

After applying the configuration, verify everything is working:

### Check IP Addresses
```
/ip address print
```

### Check Routing Tables
```
/routing table print
```

### Check Routes and Gateway Status
```
/ip route print detail where check-gateway=ping
```

### Monitor PCC Statistics
```
/ip firewall mangle print stats
```

### Check Connection Distribution
```
/ip firewall connection print where connection-mark~"WAN"
```

### Test Each WAN
```
/ping 1.1.1.1 count=10
/tool traceroute 1.1.1.1
```

### Monitor LTE Status
```
/interface lte print
/interface lte info lte1
```

## 🔍 How It Works

### 1. Routing Tables
- **main**: Default routing table (router's own traffic)
- **to-WAN1**: Policy table for WAN1-marked connections
- **to-WAN2**: Policy table for WAN2-marked connections
- **to-WAN3**: Policy table for WAN3-marked connections

### 2. PCC Classification
Traffic from LAN is split using `per-connection-classifier=both-addresses-and-ports:3/X`:
- **3/0**: 33% of connections → WAN1
- **3/1**: 33% of connections → WAN2
- **3/2**: 33% of connections → WAN3

### 3. Gateway Health Checks
Each WAN gateway is monitored with `check-gateway=ping`:
- Checks every few seconds
- Route is marked as unreachable if ping fails
- Traffic automatically fails over to next available route

### 4. Failover Mechanism

Each policy table has three routes with different priorities:

**to-WAN1 Table:**
1. WAN1 (distance=1) - Primary
2. WAN2 (distance=2) - First backup
3. WAN3 (distance=3) - Second backup (LTE)

**to-WAN2 Table:**
1. WAN2 (distance=1) - Primary
2. WAN1 (distance=2) - First backup
3. WAN3 (distance=3) - Second backup (LTE)

**to-WAN3 Table:**
1. WAN3 (distance=1) - Primary (LTE)
2. WAN1 (distance=2) - First backup
3. WAN2 (distance=3) - Second backup

This ensures that:
- Traffic marked for each WAN prefers that specific interface
- If primary WAN fails, traffic uses another available WAN
- Full redundancy across all three links

### 5. Netwatch Fast Failover (Optional)
The optional netwatch configuration provides faster failover by:
- Monitoring each gateway every 5 seconds
- Immediately clearing connections when a gateway goes down
- Forcing reconnection through an available WAN

### 6. NAT Configuration
Separate masquerade rules for each WAN ensure traffic exits with the correct source IP address.

## 🛡️ Firewall Protection (Optional)

The script includes commented-out basic firewall rules. Uncomment if needed:

### Input Chain
- Accepts established/related connections
- Drops invalid connections
- Allows LAN access to router
- Drops all other input (blocks remote management from WAN)

### Forward Chain
- Accepts established/related connections
- Drops invalid connections
- Allows LAN → WAN traffic
- Drops all other forwarded traffic

## 🔧 Customization

### Change LAN Subnet
```
/ip address
# Change 10.10.10.1/24 to your desired subnet

/ip dhcp-server network
# Update the network address accordingly
```

### Adjust PCC Ratio
For different load distribution (example 50/30/20):
```
# 10 total buckets for finer control:
# 5 buckets (0-4) for WAN1 = 50%
per-connection-classifier=both-addresses-and-ports:10/0
per-connection-classifier=both-addresses-and-ports:10/1
per-connection-classifier=both-addresses-and-ports:10/2
per-connection-classifier=both-addresses-and-ports:10/3
per-connection-classifier=both-addresses-and-ports:10/4

# 3 buckets (5-7) for WAN2 = 30%
per-connection-classifier=both-addresses-and-ports:10/5
per-connection-classifier=both-addresses-and-ports:10/6
per-connection-classifier=both-addresses-and-ports:10/7

# 2 buckets (8-9) for WAN3 = 20%
per-connection-classifier=both-addresses-and-ports:10/8
per-connection-classifier=both-addresses-and-ports:10/9
```

### Add Port Forwarding
To forward a port from WAN1 to an internal server:
```
/ip firewall nat
add chain=dstnat in-interface=ether1 protocol=tcp dst-port=8080 \
    action=dst-nat to-addresses=10.10.10.100 to-ports=80 \
    comment="Forward port 8080 to internal web server"
```

### Enable Router Traffic Load Balancing
Uncomment the "Router-Originated Traffic Marking" section in the script to load balance traffic from the router itself (DNS queries, NTP, updates, etc.).

### Change DNS Servers
```
/ip dns
set servers=1.1.1.1,8.8.8.8  # Change to your preferred DNS servers
```

### Modify Netwatch Intervals
```
/tool netwatch
# Change interval and timeout as needed
set [find host=[YOUR_WAN1_GATEWAY]] interval=10s timeout=3s
```

## 🐛 Troubleshooting

### All WANs show as down
Check physical connectivity and verify gateway IPs:
```
/ping [YOUR_WAN1_GATEWAY] interface=ether1
/ping [YOUR_WAN2_GATEWAY] interface=ether2
/ping [YOUR_LTE_GATEWAY] interface=lte1
```

### LTE not working
1. Check LTE interface status:
   ```
   /interface lte print
   /interface lte info lte1
   ```
2. Verify LTE signal strength
3. Check APN settings if required

### Traffic only uses one or two WANs
1. Check mangle statistics: `/ip firewall mangle print stats`
2. Verify connection marks: `/ip firewall connection print where connection-mark~"WAN"`
3. Clear existing connections: `/ip firewall connection remove [find]`
4. Test new connections

### No internet access from LAN
1. Check NAT rules: `/ip firewall nat print`
2. Verify routes: `/ip route print detail`
3. Test gateway connectivity from router

### Failover not working
1. Check gateway monitoring: `/ip route print detail where check-gateway=ping`
2. Verify "reachable" status on active routes
3. Test manually: disable a WAN interface and observe traffic shift

### Slow failover
1. Enable netwatch for faster detection
2. Reduce netwatch interval (but not too low to avoid false positives)
3. Consider using recursive routing for more reliable health checks

## 📊 Monitoring

### Real-time Connection Distribution
```
/ip firewall connection print interval=1 where connection-mark~"WAN"
```

### Track Bandwidth per WAN
```
/interface monitor-traffic ether1,ether2,lte1
```

### View Route Status
```
/ip route print where check-gateway=ping
```

### LTE Signal Quality
```
/interface lte monitor lte1 once
```

## ⚙️ Advanced Features

### Recursive Routing
For more reliable health checks, replace simple gateway pings with recursive routes to multiple public IPs:

```
# Pin specific IPs to each WAN
/ip route
add dst-address=1.1.1.1/32 gateway=[YOUR_WAN1_GATEWAY] scope=10
add dst-address=8.8.8.8/32 gateway=[YOUR_WAN2_GATEWAY] scope=10
add dst-address=9.9.9.9/32 gateway=[YOUR_LTE_GATEWAY] scope=10

# Use those IPs as recursive gateways
add dst-address=0.0.0.0/0 gateway=1.1.1.1 distance=1 scope=30 target-scope=11 check-gateway=ping
```

### Connection Tracking Timeout
Adjust connection timeouts for faster failover:
```
/ip firewall connection tracking
set tcp-established-timeout=1h tcp-close-timeout=10s
```

### LTE Data Limit Monitoring
Create a script to monitor LTE data usage and switch to other WANs if limit reached:
```
/system scheduler
add name=lte-data-check interval=1h on-event=lte-data-script

# Create script to check LTE usage and adjust routes accordingly
```

## 📚 Additional Resources

- [MikroTik Wiki - PCC](https://wiki.mikrotik.com/wiki/Manual:PCC)
- [RouterOS Manual - LTE](https://help.mikrotik.com/docs/display/ROS/LTE)
- [RouterOS Manual - Policy Routing](https://help.mikrotik.com/docs/display/ROS/Policy+Routing)
- [MikroTik Forum - Multi-WAN](https://forum.mikrotik.com/)

## ⚠️ Important Notes

1. **LTE Data Costs**: Be aware that LTE connections typically have data caps and costs. Consider:
   - Setting LTE as lowest priority (highest distance)
   - Implementing data usage monitoring
   - Using LTE only for failover, not load balancing

2. **Connection Persistence**: Each connection stays on its assigned WAN for its entire lifetime. Only new connections are load balanced.

3. **Latency Differences**: LTE typically has higher latency than wired connections. This is normal and expected.

4. **Router-Originated Traffic**: By default, traffic from the router itself uses the main routing table (WAN1 primary). Uncomment the output chain rules to change this.

5. **FastTrack**: PCC is incompatible with FastTrack. Do not enable FastTrack with this configuration.

6. **Bandwidth Asymmetry**: If your three WANs have very different speeds, consider adjusting the PCC ratio to match bandwidth proportions.

## 🎯 Use Cases

### Scenario 1: Office with Two ISPs + LTE Backup
- **WAN1**: Primary fiber ISP (fastest)
- **WAN2**: Secondary cable ISP
- **WAN3**: LTE backup (data limited)
- Load balance across WAN1 and WAN2, use LTE only when both fail

### Scenario 2: Remote Site with Limited Connectivity
- **WAN1**: DSL connection
- **WAN2**: Cable connection
- **WAN3**: LTE for redundancy
- Distribute load evenly across all three

### Scenario 3: Mobile/Temporary Installation
- **WAN1**: Primary LTE
- **WAN2**: Secondary LTE (different carrier)
- **WAN3**: Satellite or other backup
- Full redundancy with multiple LTE carriers

## 📄 License

This configuration is provided as-is for educational and production use. Modify as needed for your environment.

## 🤝 Contributing

Found an issue or have an improvement? Please share your feedback!

---

**Version**: 1.0  
**Compatible with**: RouterOS 7.x  
**Recommended for**: Devices with LTE capability
