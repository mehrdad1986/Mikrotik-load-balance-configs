# MikroTik Dual WAN PCC Load Balancing Configuration

Complete PCC (Per Connection Classifier) load balancing setup for MikroTik RouterOS 7.x with dual WAN connections.

## 📋 Overview

This configuration provides:
- **50/50 load balancing** across two WAN connections
- **Automatic failover** with recursive health checks
- **Independent failover** in both PCC routing tables
- **Proper NAT** handling for each WAN interface
- **Basic firewall** protection

## 🔧 Network Topology

```
┌─────────────────────────────────────────┐
│          MikroTik Router                │
│         (RB750Gr3 or similar)           │
├─────────────────────────────────────────┤
│  ether1 (WAN1) ──► ISP 1                │
│  ether2 (WAN2) ──► ISP 2                │
│  ether4 (LAN)  ──┐                      │
│  ether5 (LAN)  ──┴─► bridge2 (LAN)      │
└─────────────────────────────────────────┘
```

## 📝 Configuration Parameters

### WAN Interfaces
- **WAN1**: ether1 - Configure your ISP1 IP and gateway
- **WAN2**: ether2 - Configure your ISP2 IP and gateway

### LAN Interface
- **Bridge**: bridge2 (ether4 + ether5)
- **LAN Network**: 192.168.10.0/24
- **LAN Gateway**: 192.168.10.1

### Health Check Targets
**WAN1 Monitors:**
- Cloudflare: 1.1.1.1
- Google: 8.8.8.8

**WAN2 Monitors:**
- Quad9: 9.9.9.9
- OpenDNS: 208.67.222.222

## 🚀 Quick Start

### Before You Begin

1. **Backup your current configuration:**
   ```
   /system backup save name=before-pcc
   /export file=before-pcc-export
   ```

2. **Update the placeholders in the script:**
   - Replace `[YOUR_WAN1_IP]` with your WAN1 IP address
   - Replace `[YOUR_WAN1_GATEWAY]` with your WAN1 gateway
   - Replace `[YOUR_WAN2_IP]` with your WAN2 IP address
   - Replace `[YOUR_WAN2_GATEWAY]` with your WAN2 gateway

### Installation

1. Open WinBox or SSH to your MikroTik
2. Open a New Terminal
3. Copy and paste the entire script from `dual-wan-pcc-latest.rsc`
4. Wait for completion message: "BEST PCC DUAL WAN CONFIGURATION APPLIED"

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

### Check Active Connections
```
/ip firewall connection print where connection-mark~"wan"
```

### Test Connectivity
```
/ping 1.1.1.1 count=10
/ping 8.8.8.8 count=10
/tool traceroute 1.1.1.1
```

## 🔍 How It Works

### 1. Routing Tables
- **main**: Default routing table (router's own traffic)
- **to-wan1**: Policy table for WAN1-marked connections
- **to-wan2**: Policy table for WAN2-marked connections

### 2. PCC Classification
Traffic from LAN is split using `per-connection-classifier=both-addresses-and-ports:2/0` and `2/1`:
- **2/0**: 50% of connections → WAN1
- **2/1**: 50% of connections → WAN2

### 3. Recursive Health Checks
Each WAN has two monitoring targets:
- If one target fails, the other keeps the route active
- If both targets fail, traffic fails over to the backup WAN
- Monitoring is done via ICMP ping with `check-gateway=ping`

### 4. Failover Mechanism
Each policy table has:
- **Primary routes** (distance=1) via preferred WAN
- **Backup routes** (distance=2) via alternate WAN

Example: Traffic marked for WAN1 normally uses WAN1, but automatically switches to WAN2 if WAN1 health checks fail.

### 5. NAT Configuration
Separate source NAT rules for each WAN ensure traffic exits with the correct source IP address.

## 🛡️ Firewall Protection

### Input Chain
- Accepts established/related connections
- Drops invalid connections
- **Allows LAN access** to router
- **Blocks WAN access** to router (remote management disabled)

### Forward Chain
- Accepts established/related connections
- Drops invalid connections
- Allows LAN → WAN1 and LAN → WAN2
- Allows port forwarding (dstnat connections)
- Drops all other forwarded traffic

## 🔧 Customization

### Change LAN Subnet
If you need a different LAN subnet, update:
```
/ip address
# Change 192.168.10.1/24 to your desired subnet

/ip dhcp-server network
# Update the network address accordingly
```

### Add Port Forwarding
To forward a port from WAN1 to an internal server:
```
/ip firewall nat
add chain=dstnat in-interface=ether1 protocol=tcp dst-port=8080 \
    action=dst-nat to-addresses=192.168.10.100 to-ports=80 \
    comment="Forward port 8080 to internal web server"
```

### Adjust PCC Ratio
To change the load balancing ratio from 50/50:
```
# For 70/30 split (70% WAN1, 30% WAN2):
per-connection-classifier=both-addresses-and-ports:10/0  # Rules 0-6 for WAN1 (7 rules)
per-connection-classifier=both-addresses-and-ports:10/7  # Rules 7-9 for WAN2 (3 rules)
```

### Change DNS Servers
```
/ip dns
set servers=1.1.1.1,8.8.8.8  # Change to your preferred DNS servers
```

## 🐛 Troubleshooting

### Both WANs show as down
Check physical connectivity and verify gateway IPs are correct:
```
/ping [YOUR_WAN1_GATEWAY] interface=ether1
/ping [YOUR_WAN2_GATEWAY] interface=ether2
```

### Traffic only uses one WAN
1. Check mangle statistics: `/ip firewall mangle print stats`
2. Verify connection marks: `/ip firewall connection print where connection-mark~"wan"`
3. Clear existing connections: `/ip firewall connection remove [find]`

### No internet access from LAN
1. Check NAT rules: `/ip firewall nat print`
2. Verify firewall rules: `/ip firewall filter print`
3. Check routing: `/ip route print detail`

### Failover not working
1. Check gateway monitoring: `/ip route print detail where check-gateway=ping`
2. Look for "reachable" status on active routes
3. Verify health check targets are responding

## 📚 Additional Resources

- [MikroTik Wiki - PCC](https://wiki.mikrotik.com/wiki/Manual:PCC)
- [RouterOS Manual - Mangle](https://help.mikrotik.com/docs/display/ROS/Mangle)
- [RouterOS Manual - Policy Routing](https://help.mikrotik.com/docs/display/ROS/Policy+Routing)

## ⚠️ Important Notes

1. **FastTrack**: This configuration is incompatible with FastTrack. The script removes FastTrack rules.

2. **Connection Persistence**: Each connection stays on its assigned WAN for its entire lifetime. Only new connections are load balanced.

3. **DNS**: Router's own DNS queries follow the main routing table (WAN1 primary, WAN2 backup).

4. **Router-Originated Traffic**: Traffic from the router itself (updates, NTP, etc.) uses the main routing table, not PCC.

5. **Remote Management**: The firewall blocks all incoming WAN connections to the router. Access only from LAN.

## 📄 License

This configuration is provided as-is for educational and production use. Modify as needed for your environment.

## 🤝 Contributing

Found an issue or have an improvement? Please share your feedback!

---

**Version**: 1.0  
**Compatible with**: RouterOS 7.x  
**Tested on**: MikroTik RB750Gr3
