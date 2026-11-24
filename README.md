# MikroTik PCC Load Balancing Configurations

Production-ready PCC (Per Connection Classifier) load balancing configurations for MikroTik RouterOS 7.x with comprehensive documentation, verification commands, and troubleshooting guides.

## 📚 Available Configurations

### 🔗 Dual WAN PCC
Perfect for most scenarios with two ISP connections.

- **Production Script**: [`PRODUCTION-DUAL-WAN-PCC.rsc`](PRODUCTION-DUAL-WAN-PCC.rsc) ⭐ **START HERE**
- **Alternative Script**: [`dual-wan-pcc-latest.rsc`](dual-wan-pcc-latest.rsc)
- **Documentation**: [`README-dual-wan.md`](README-dual-wan.md)
- **Features**:
  - 50/50 load balancing
  - Recursive health checks with 2 targets per WAN
  - Independent failover in both routing tables
  - Basic firewall protection
  - **Heavily commented for learning**

### 🔗🔗🔗 Triple WAN PCC
For advanced setups with three WAN connections including LTE backup.

- **Script**: [`triple-wan-pcc-latest.rsc`](triple-wan-pcc-latest.rsc)
- **Documentation**: [`README-triple-wan.md`](README-triple-wan.md)
- **Features**:
  - 33/33/33 load balancing
  - LTE backup support
  - Gateway health monitoring
  - Optional netwatch for fast failover

## 🚀 Quick Start

### 1. Choose Your Configuration
- **Dual WAN**: Two internet connections (fiber, cable, DSL, etc.)
- **Triple WAN**: Three internet connections (including LTE backup)

### 2. Backup Current Configuration
```
/system backup save name=before-pcc
/export file=before-pcc-export
```

### 3. Download and Customize
1. Download the appropriate `.rsc` file
2. Replace all placeholder values:
   - `[YOUR_WAN1_IP]` - Your WAN1 IP address
   - `[YOUR_WAN1_GATEWAY]` - Your WAN1 gateway
   - `[YOUR_WAN2_IP]` - Your WAN2 IP address
   - `[YOUR_WAN2_GATEWAY]` - Your WAN2 gateway
   - For triple WAN: also update WAN3/LTE settings

### 4. Apply Configuration
1. Open WinBox or SSH to your MikroTik
2. Open a New Terminal
3. Copy and paste the entire script
4. Wait for confirmation message

### 5. Verify
```
/ip address print
/ip route print detail where check-gateway=ping
/ip firewall mangle print stats
```

## 📖 Documentation

### Dual WAN
- Full setup guide: [README-dual-wan.md](README-dual-wan.md)
- Configuration file: [dual-wan-pcc-latest.rsc](dual-wan-pcc-latest.rsc)
- Tutorial (HTML): [dual-wan-pcc-tutorial-detailed.html](dual-wan-pcc-tutorial-detailed.html)
- Legacy reference: [dual-wan-pcc.txt](dual-wan-pcc.txt)

### Triple WAN
- Full setup guide: [README-triple-wan.md](README-triple-wan.md)
- Configuration file: [triple-wan-pcc-latest.rsc](triple-wan-pcc-latest.rsc)
- Tutorial (HTML): [triple-wan-pcc-tutorial.html](triple-wan-pcc-tutorial.html)
- Interactive guide (HTML): [triple-wan-pcc-interactive-guide.html](triple-wan-pcc-interactive-guide.html)
- Legacy reference: [triple-wan-pcc.txt](triple-wan-pcc.txt)

### Additional Resources
- DoH (DNS over HTTPS) server list: [doh-list.md](doh-list.md)
- Sample config (reference): [config.rsc](config.rsc)
- **PCC Concepts Deep Dive**: [PCC-CONCEPTS.md](PCC-CONCEPTS.md) 📚

### Teaching Materials
- Dual WAN detailed tutorial (HTML): [dual-wan-pcc-tutorial-detailed.html](dual-wan-pcc-tutorial-detailed.html)
- Triple WAN tutorial (HTML): [triple-wan-pcc-tutorial.html](triple-wan-pcc-tutorial.html)
- Triple WAN interactive guide (HTML): [triple-wan-pcc-interactive-guide.html](triple-wan-pcc-interactive-guide.html)

## 🔍 How PCC Works

### Per Connection Classifier (PCC)
PCC distributes connections across multiple WANs based on a hash of:
- Source address
- Destination address
- Source port
- Destination port

Each new connection is assigned to a WAN link, and that connection stays on that link for its entire lifetime.

### Key Concepts

**Connection Marking**:
```
per-connection-classifier=both-addresses-and-ports:2/0  # 50% to WAN1
per-connection-classifier=both-addresses-and-ports:2/1  # 50% to WAN2
```

**Routing Tables**:
- Each WAN gets its own routing table (to-wan1, to-wan2, etc.)
- Tables have primary and backup routes
- Automatic failover when primary gateway fails

**Health Checks**:
- Gateway monitoring via `check-gateway=ping`
- Routes become inactive when gateway is unreachable
- Traffic automatically uses backup routes

## 🛠️ Common Verification Commands

### Check Configuration
```
/ip address print
/routing table print
/ip route print detail
```

### Monitor PCC Distribution
```
/ip firewall mangle print stats
/ip firewall connection print where connection-mark~"wan"
```

### Test Connectivity
```
/ping 1.1.1.1 count=10
/ping 8.8.8.8 count=10
/tool traceroute 1.1.1.1
```

### View Gateway Status
```
/ip route print where check-gateway=ping
```

### Monitor Traffic
```
/interface monitor-traffic ether1,ether2
```

## 🐛 Common Issues

### Traffic only uses one WAN
1. Check mangle statistics: `/ip firewall mangle print stats`
2. Clear connections: `/ip firewall connection remove [find]`
3. Verify both gateways are reachable

### No internet access
1. Check NAT rules: `/ip firewall nat print`
2. Verify routes are active: `/ip route print detail`
3. Test gateway connectivity

### Slow failover
1. Enable netwatch for faster detection
2. Use recursive routing to public IPs
3. Adjust check intervals

## ⚠️ Important Notes

### What PCC Is
- ✅ **Per-connection load balancing** - Each connection uses one WAN
- ✅ **Automatic failover** - Routes switch when gateways fail
- ✅ **Session persistence** - Connections stay on assigned WAN

### What PCC Is Not
- ❌ **Not per-packet** - Packets from same connection use same WAN
- ❌ **Not bandwidth aggregation** - Single downloads don't combine speeds
- ❌ **Not seamless failover** - Existing connections break when WAN fails

### Compatibility
- ✅ RouterOS 7.x (uses named routing tables)
- ⚠️ RouterOS 6.x requires different syntax (use legacy scripts)
- ❌ Not compatible with FastTrack (FastTrack bypasses mangle)

### Best Practices
1. Always backup before applying
2. Test step-by-step if connected remotely
3. Update placeholder values before applying
4. Monitor for 24 hours after deployment
5. Document your specific IP addresses and gateways

## 📊 Network Topologies

### Dual WAN Setup
```
                    ┌─── WAN1 (ether1) ───► ISP 1
                    │
Router (MikroTik) ──┤
                    │
                    └─── WAN2 (ether2) ───► ISP 2
         │
         └─── LAN (bridge2: ether4+ether5) ───► Local Network
```

### Triple WAN Setup
```
                    ┌─── WAN1 (ether1) ───► ISP 1
                    │
Router (MikroTik) ──┼─── WAN2 (ether2) ───► ISP 2
                    │
                    └─── WAN3 (lte1) ─────► LTE Provider
         │
         └─── LAN (bridge-LAN: ether4+ether5) ───► Local Network
```

## 🎯 Use Cases

### Home/Small Office
- **Dual WAN**: Primary fiber + backup cable
- Reliable internet with automatic failover
- Cost-effective redundancy

### Medium Business
- **Dual WAN**: Two business ISPs from different providers
- Load balance normal traffic
- Maintain connectivity if one provider fails

### Remote Site
- **Triple WAN**: DSL + Cable + LTE
- Maximum redundancy
- LTE as emergency backup

### Critical Operations
- **Triple WAN**: Fiber + Fiber + LTE
- Always-on connectivity
- Multiple carrier redundancy

## 🔒 Security Considerations

### Default Firewall Rules
Both configurations include basic firewall protection:
- Drop invalid connections
- Block WAN access to router
- Allow LAN management only
- Block unsolicited inbound traffic

### Additional Security
Consider adding:
- SSH key authentication
- Fail2ban or login attempt limiting
- Port knocking for remote access
- VPN for secure remote management

### What's NOT Included
These configurations do NOT include:
- Advanced firewall rules
- IDS/IPS
- Content filtering
- VPN server setup
- Port forwarding rules

Add these separately based on your needs.

## 📈 Performance Expectations

### Load Balancing
- Each connection uses one WAN link
- Overall bandwidth increases with multiple concurrent connections
- Single large download uses only one link
- Many small connections distribute across links

### Latency
- Each connection follows one path
- Latency equals the WAN in use
- LTE typically has higher latency than wired
- Failover may cause momentary interruption

### Throughput
- Total throughput = sum of all WANs (for multiple connections)
- Single connection throughput = one WAN's speed
- PCC doesn't aggregate bandwidth per connection

## 🤝 Contributing

Found an issue or have an improvement?
1. Test thoroughly in your environment
2. Document your changes
3. Share feedback and suggestions

## 📄 License

These configurations are provided as-is for educational and production use.

**Free to use, modify, and share.**

No warranty provided. Test before deploying in production.

## 🆘 Support

### Documentation
- Read the specific README for your configuration
- Check troubleshooting sections
- Review verification commands

### Community Resources
- [MikroTik Forum](https://forum.mikrotik.com/)
- [MikroTik Wiki](https://wiki.mikrotik.com/)
- [RouterOS Manual](https://help.mikrotik.com/docs/)

### Professional Help
For production deployments, consider:
- MikroTik certified consultants
- Professional network engineers
- Your local MikroTik distributor

---

## 📝 Configuration Summary

| Feature | Dual WAN | Triple WAN |
|---------|----------|------------|
| **WAN Ports** | 2 (ether1, ether2) | 3 (ether1, ether2, lte1) |
| **Load Distribution** | 50/50 | 33/33/33 |
| **Routing Tables** | 2 policy tables | 3 policy tables |
| **Health Checks** | 4 recursive targets | 3 gateway pings |
| **LAN Ports** | ether4+ether5 | ether4+ether5 |
| **LTE Support** | No | Yes |
| **Netwatch** | No | Optional |
| **Complexity** | Simple | Moderate |
| **Best For** | Most scenarios | Advanced redundancy |

---

**Last Updated**: 2026  
**RouterOS Version**: 7.x  
**Tested On**: MikroTik RB750Gr3 (hEX)

**Compatible Devices**: Any MikroTik running RouterOS 7.x with sufficient interfaces
