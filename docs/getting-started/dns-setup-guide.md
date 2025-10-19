# DNS Configuration Guide - Pi-hole Setup

## Goal
Configure DNS so that `*.stratdata.org` points to the Pi cluster at `192.168.1.240`

---

## Current Configuration - Pi-hole (Active)

### DNS Infrastructure

**2x Raspberry Pi 3 running Pi-hole v6.1.2 + WireGuard VPN**

**Primary DNS: rpi-vpn-1**
- IP: 192.168.1.25
- Pi-hole: v6.1.2
- WireGuard: ✓ (2 peers configured)
- Upstream DNS: 8.8.8.8, 8.8.4.4
- Listening Mode: ALL (accepts external queries)
- Credentials: admin/Admin123

**Secondary DNS: rpi-vpn-2**
- IP: 192.168.1.26
- Pi-hole: v6.1.2
- WireGuard: ✓ (configured)
- Upstream DNS: 8.8.8.8, 8.8.4.4
- Listening Mode: ALL (accepts external queries)
- Auto-sync: Every 15 minutes (rsync from primary)
- Credentials: admin/Admin123

### DNS Records Configuration

**File**: `/etc/dnsmasq.d/99-stratdata-local.conf` (on both Pi-hole servers)

```conf
# Local DNS entries for stratdata.org cluster
address=/grafana.stratdata.org/192.168.1.240
address=/longhorn.stratdata.org/192.168.1.240
address=/code.stratdata.org/192.168.1.240
address=/prometheus.stratdata.org/192.168.1.240
address=/loki.stratdata.org/192.168.1.240
address=/traefik.stratdata.org/192.168.1.240
```

### Services
- grafana.stratdata.org → 192.168.1.240
- longhorn.stratdata.org → 192.168.1.240
- code.stratdata.org → 192.168.1.240
- prometheus.stratdata.org → 192.168.1.240
- loki.stratdata.org → 192.168.1.240
- traefik.stratdata.org → 192.168.1.240

---

## Client Configuration

### Option 1: Network-wide DNS (Recommended)

Configure your router's DHCP server to use Pi-hole:

1. Login to your router (192.168.1.1)
2. Navigate to DHCP settings
3. Set DNS servers:
   - **Primary DNS**: 192.168.1.25 (rpi-vpn-1)
   - **Secondary DNS**: 192.168.1.26 (rpi-vpn-2)
4. Save and reboot router (or renew DHCP leases)

**Benefits**:
- All devices on network use Pi-hole
- Network-wide ad blocking
- Automatic failover between DNS servers
- No per-device configuration needed

### Option 2: Windows DNS (Per-device)

**Manual Configuration**:
1. Open **Network Connections** (Win+R → `ncpa.cpl`)
2. Right-click network adapter → **Properties**
3. Select **Internet Protocol Version 4 (TCP/IPv4)** → **Properties**
4. Select **"Use the following DNS server addresses"**:
   - **Preferred DNS**: `192.168.1.25`
   - **Alternate DNS**: `192.168.1.26`
5. Click **OK**

**Flush DNS cache**:
```powershell
ipconfig /flushdns
```

### Option 3: Linux/WSL

Edit `/etc/resolv.conf` or use systemd-resolved:

```bash
# Temporary (until reboot)
sudo bash -c 'echo "nameserver 192.168.1.25" > /etc/resolv.conf'
sudo bash -c 'echo "nameserver 192.168.1.26" >> /etc/resolv.conf'

# Permanent (systemd-resolved)
sudo systemctl edit systemd-resolved
# Add:
# [Resolve]
# DNS=192.168.1.25 192.168.1.26
```

---

## Management

### Pi-hole Web Interface

**Access**:
- Primary: http://192.168.1.25/admin
- Secondary: http://192.168.1.26/admin

**Password**: Set via `pihole -a -p` command

### Add New DNS Entry

**Via SSH** (recommended for automation):

```bash
# SSH to Pi-hole server
ssh admin@192.168.1.25

# Edit dnsmasq config
sudo nano /etc/dnsmasq.d/99-stratdata-local.conf

# Add entry:
address=/newservice.stratdata.org/192.168.1.240

# Restart DNS
sudo systemctl restart pihole-FTL

# Repeat for secondary (192.168.1.26)
```

**Via Web Interface**:
1. Login to http://192.168.1.25/admin
2. Go to **Local DNS** → **DNS Records**
3. Add entry:
   - Domain: `newservice.stratdata.org`
   - IP Address: `192.168.1.240`
4. Save
5. Repeat for secondary Pi-hole

### Restart DNS Service

```bash
ssh admin@192.168.1.25
sudo systemctl restart pihole-FTL
```

Or:
```bash
ssh admin@192.168.1.25
pihole restartdns
```

### Check DNS Status

```bash
ssh admin@192.168.1.25
pihole status
```

### View DNS Logs

```bash
ssh admin@192.168.1.25
pihole -t  # Tail logs in real-time
```

---

## Verification

### Test DNS Resolution

**From Windows PowerShell**:
```powershell
nslookup grafana.stratdata.org 192.168.1.25
# Should return: 192.168.1.240
```

**From Linux/WSL**:
```bash
nslookup grafana.stratdata.org 192.168.1.25
dig @192.168.1.25 grafana.stratdata.org
```

**Test All Services**:
```bash
for host in grafana longhorn code prometheus loki traefik; do
  echo -n "$host.stratdata.org: "
  nslookup ${host}.stratdata.org 192.168.1.25 | grep "Address: 192"
done
```

### Test HTTPS Access

```bash
curl -I https://grafana.stratdata.org
curl -I https://longhorn.stratdata.org
curl -I https://code.stratdata.org
```

---

## WireGuard VPN Access

Both Pi-hole servers have WireGuard VPN configured for external access.

**Check VPN Status**:
```bash
ssh admin@192.168.1.25
sudo wg show
```

**Access cluster remotely**:
1. Connect to WireGuard VPN
2. DNS queries automatically use Pi-hole
3. Access services at `*.stratdata.org` URLs

---

## High Availability

### Configuration Synchronization

**Automatic sync** (every 15 minutes):
- Gravity database synced from primary to secondary
- Custom DNS entries synced (`99-stratdata-local.conf`)
- WireGuard configs remain independent
- Cron job: `/usr/local/bin/pihole-sync.sh`
- Logs: `/var/log/pihole-sync.log`

**Manual sync**:
```bash
ssh admin@192.168.1.26 'sudo /usr/local/bin/pihole-sync.sh'
```

### Failover Behavior

**Primary DNS fails** (192.168.1.25):
- Clients automatically use secondary (192.168.1.26)
- No service interruption (configs are synchronized)
- ~1-5 second failover time

**Both DNS servers fail**:
- Clients fall back to tertiary DNS (if configured)
- Or use router's DNS (192.168.1.1)

### Health Monitoring

**Check both servers**:
```bash
# Primary
ssh admin@192.168.1.25 'pihole status'

# Secondary
ssh admin@192.168.1.26 'pihole status'
```

**Network test**:
```bash
nslookup grafana.stratdata.org 192.168.1.25
nslookup grafana.stratdata.org 192.168.1.26
```

---

## Troubleshooting

### DNS not resolving

**Check DNS server is running**:
```bash
ssh admin@192.168.1.25 'pihole status'
```

**Check port 53 is listening**:
```bash
ssh admin@192.168.1.25 'sudo netstat -uln | grep :53'
```

**Test DNS directly**:
```bash
nslookup grafana.stratdata.org 192.168.1.25
```

**Restart DNS service**:
```bash
ssh admin@192.168.1.25 'sudo systemctl restart pihole-FTL'
```

### Getting public IP instead of local

**Issue**: `grafana.stratdata.org` resolves to 87.103.15.249

**Cause**: Not using Pi-hole DNS servers

**Fix**:
1. Check Windows DNS settings: `ipconfig /all`
2. Verify DNS servers are 192.168.1.25 and 192.168.1.26
3. Flush DNS: `ipconfig /flushdns`
4. Test: `nslookup grafana.stratdata.org`

### Still seeing DSM login page

**Issue**: Browser shows Synology login instead of Grafana

**Causes**:
1. **Wrong DNS resolution** - Run `nslookup grafana.stratdata.org`
   - Should return 192.168.1.240, not 192.168.1.20 or 87.103.15.249
2. **Browser cache** - Clear cache or use incognito mode
3. **Windows DNS cache** - Run `ipconfig /flushdns`

**Fix**:
```powershell
# Check DNS
ipconfig /all | Select-String "DNS"

# Should show:
# DNS Servers . . . . . . . . . . . : 192.168.1.25
#                                     192.168.1.26

# If not, update network adapter DNS settings
```

### Pi-hole not blocking ads

**Check blocklists**:
```bash
ssh admin@192.168.1.25 'pihole -g'  # Update gravity (blocklists)
```

**Check query logs**:
```bash
ssh admin@192.168.1.25 'pihole -t'
```

### Config file not persisting

**Issue**: Changes to `/etc/dnsmasq.d/99-stratdata-local.conf` lost after reboot

**Fix**: Ensure file has proper permissions
```bash
ssh admin@192.168.1.25
sudo chown root:root /etc/dnsmasq.d/99-stratdata-local.conf
sudo chmod 644 /etc/dnsmasq.d/99-stratdata-local.conf
```

---

## Maintenance

### Update Pi-hole

```bash
ssh admin@192.168.1.25
pihole -up
```

### Update Blocklists

```bash
ssh admin@192.168.1.25
pihole -g
```

### Backup Configuration

**Pi-hole Teleporter** (web interface):
1. Login to http://192.168.1.25/admin
2. Settings → Teleporter
3. Backup → Download

**Manual backup**:
```bash
ssh admin@192.168.1.25
tar -czf pihole-backup-$(date +%Y%m%d).tar.gz /etc/pihole/ /etc/dnsmasq.d/
```

---

## Legacy: Synology DS723+ DNS (Deprecated)

The Synology DS723+ (192.168.1.20) was previously used as the primary DNS server with BIND. This has been replaced by the Pi-hole setup for better ad-blocking, VPN integration, and dedicated DNS performance.

**Old configuration** (archived):
- Zone files: `/var/packages/DNSServer/target/named/etc/zone/master/`
- Config: `/var/packages/DNSServer/target/named/etc/conf/`

If needed, the Synology DNS can be re-enabled as a tertiary DNS server.

---

## Network Diagram

```
Internet (87.103.15.249)
    ↓
Router (192.168.1.1)
    ↓
┌──────────────────────────────────────────┐
│ Local Network (192.168.1.0/24)           │
│                                           │
│  Pi-hole Primary (192.168.1.25)          │
│  ├─ DNS Server (dnsmasq)                 │
│  ├─ WireGuard VPN                        │
│  ├─ Ad Blocking                          │
│  └─ *.stratdata.org → 192.168.1.240      │
│                                           │
│  Pi-hole Secondary (192.168.1.26)        │
│  ├─ DNS Server (dnsmasq)                 │
│  ├─ WireGuard VPN                        │
│  ├─ Ad Blocking                          │
│  └─ *.stratdata.org → 192.168.1.240      │
│                                           │
│  Pi Cluster Master (192.168.1.240)       │
│  ├─ Traefik Ingress                      │
│  │   ├─ grafana.stratdata.org            │
│  │   ├─ longhorn.stratdata.org           │
│  │   └─ code.stratdata.org               │
│  └─ Worker Nodes (192.168.1.241-247)     │
│                                           │
│  Synology DS723+ (192.168.1.20)          │
│  ├─ NFS Storage (2TB NVMe)               │
│  └─ Let's Encrypt Cert (*.stratdata.org) │
│                                           │
│  Synology DS118 (192.168.1.10)           │
│  └─ NFS Storage (7.3TB)                  │
└──────────────────────────────────────────┘
```

---

## Quick Reference

**DNS Servers**:
- Primary: 192.168.1.25 (rpi-vpn-1)
- Secondary: 192.168.1.26 (rpi-vpn-2)

**Credentials**: admin/Admin123

**Web Interfaces**:
- http://192.168.1.25/admin
- http://192.168.1.26/admin

**Config File**: `/etc/dnsmasq.d/99-stratdata-local.conf`

**Restart DNS**: `sudo systemctl restart pihole-FTL`

**Check Status**: `pihole status`

**Add DNS Entry**:
```bash
echo "address=/service.stratdata.org/192.168.1.240" | \
  sudo tee -a /etc/dnsmasq.d/99-stratdata-local.conf
sudo systemctl restart pihole-FTL
```
