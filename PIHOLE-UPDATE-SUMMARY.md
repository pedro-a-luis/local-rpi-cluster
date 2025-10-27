# Pi-hole Update Summary

**Date**: October 26, 2025
**Status**: ✅ Complete (with notes)

---

## Update Results

### Primary Pi-hole (rpi-vpn-1 - 192.168.1.25)

✅ **Successfully Updated**

| Component | Before | After | Status |
|-----------|--------|-------|--------|
| Pi-hole Core | v6.2.1 | v6.2.1 | ✅ Latest |
| Web Interface | v6.3 | v6.3 | ✅ Latest |
| FTL | v6.3 | v6.3 | ✅ Latest |
| OS Packages | 19 pending | 0 pending | ✅ Updated |
| WireGuard | Active | Active | ✅ Updated |
| Gravity Database | 101,221 domains | 101,221 domains | ✅ Updated |

**DNS Status**: ✅ Working
- Resolves external domains
- Resolves local domains (e.g., `grafana.stratdata.org` → `192.168.1.240`)
- Upstream DNS: Google DNS (8.8.8.8, 8.8.4.4)

---

### Secondary Pi-hole (rpi-vpn-2 - 192.168.1.26)

✅ **Successfully Updated**

| Component | Before | After | Status |
|-----------|--------|-------|--------|
| Pi-hole Core | v5.x | v6.2.1 | ✅ Upgraded to Latest |
| Web Interface | v5.x | v6.3 | ✅ Upgraded to Latest |
| FTL | v6.2.3 | v6.3 | ✅ Upgraded to Latest |
| OS Packages | 102 pending | 1 pending | ✅ Updated |
| WireGuard | Active | Active | ✅ Updated |
| Gravity Database | Synced | 101,221 domains | ✅ Updated |
| Reboot | Not required | Completed | ✅ Rebooted |

**DNS Status**: ✅ Working (partially)
- Resolves external domains correctly
- ⚠️ Does NOT resolve local/custom domains (resolves to public IPs)
- Upstream DNS: Google DNS (8.8.8.8, 8.8.4.4) - **Manually configured**

---

## Important Findings

### 1. ⚠️ Gravity Sync Not Compatible with Pi-hole 6

**Issue**: Gravity Sync project was **archived on July 26, 2024** and is **incompatible with Pi-hole 6.x**.

**Impact**:
- Automatic synchronization of blocklists and custom DNS records between primary and secondary is NOT available
- Pi-hole 6.x includes architectural changes that broke Gravity Sync compatibility
- Final Gravity Sync version (4.0.7) only works with Pi-hole 5.x

**Workaround Applied**:
- Manually configured upstream DNS servers on secondary Pi-hole
- Secondary functions as an independent backup DNS server
- Configuration changes must be made manually on both servers

---

### 2. Configuration Differences

#### Primary (rpi-vpn-1)
- **Purpose**: Main DNS server with custom local domain records
- **Custom DNS**: Configured with local domain mappings
  - `grafana.stratdata.org` → `192.168.1.240`
  - (Other .stratdata.org domains)
- **Source**: Manually configured

#### Secondary (rpi-vpn-2)
- **Purpose**: Backup/redundancy DNS server
- **Custom DNS**: None - resolves everything via upstream
  - `grafana.stratdata.org` → Public IP (87.103.15.249)
- **Note**: Does NOT have local domain records

---

## Recommendations

### Option 1: Keep as Backup Only (Current State)

**Pros**:
- Secondary provides DNS redundancy for internet queries
- If primary fails, external DNS resolution still works
- Simple configuration

**Cons**:
- Local domain resolution (*.stratdata.org) won't work when primary is down
- No automatic synchronization of blocklists/settings

**Recommendation**: Good for basic redundancy

---

### Option 2: Manual Sync of Custom DNS Records

Add the same custom local DNS records to secondary manually.

**Steps**:
1. Get custom DNS records from primary:
   ```bash
   ssh rpi-vpn-1 "pihole api dns.cname.list"
   ssh rpi-vpn-1 "pihole api dns.host.list"
   ```

2. Add each custom record to secondary using Pi-hole web interface or API

**Pros**:
- Full failover capability - secondary can handle all queries
- Local domain resolution works on both servers

**Cons**:
- Manual synchronization required
- Changes must be made twice (primary + secondary)

**Recommendation**: Best for production-like setup

---

### Option 3: Explore Pi-hole 6 Native Sync (If Available)

Check if Pi-hole 6 includes any native synchronization features.

**Action**: Research Pi-hole 6 documentation for:
- Built-in replication features
- API-based synchronization
- Community tools compatible with v6

---

## DNS Testing Results

### Primary (192.168.1.25)
```bash
$ nslookup grafana.stratdata.org 192.168.1.25
Name:    grafana.stratdata.org
Address: 192.168.1.240  ← Local cluster IP ✅
```

### Secondary (192.168.1.26)
```bash
$ nslookup grafana.stratdata.org 192.168.1.26
Name:    grafana.stratdata.org
Address: 87.103.15.249  ← Public IP (no local record) ⚠️

$ nslookup google.com 192.168.1.26
Name:    google.com
Address: 172.217.17.14  ← External resolution works ✅
```

---

## Web Admin Interfaces

Both Pi-hole admin panels are accessible:

- **Primary**: http://192.168.1.25/admin
- **Secondary**: http://192.168.1.26/admin

**Note**: Password may need to be reset if not set during update.

To set/reset password:
```bash
ssh rpi-vpn-1 "sudo pihole -a -p"
ssh rpi-vpn-2 "sudo pihole -a -p"
```

---

## Files Modified

### 1. [ansible/playbooks/infrastructure/update-pihole.yml](ansible/playbooks/infrastructure/update-pihole.yml)
- Fixed `clean: yes` → `autoclean: yes` (line 135)

### 2. [ansible/playbooks/infrastructure/setup-gravity-sync.yml](ansible/playbooks/infrastructure/setup-gravity-sync.yml)
- Updated version `4.0.2` → `4.0.7` (line 89)
- **Note**: Still won't work with Pi-hole 6.x (Gravity Sync archived)

### 3. `/etc/pihole/pihole.toml` on rpi-vpn-2
- Added upstream DNS: `upstreams = ["8.8.8.8","8.8.4.4"]`
- Backup saved at: `/etc/pihole/pihole.toml.backup`

---

## System Status

### Primary (rpi-vpn-1)
```
Hostname: rpi-vpn-1
OS: Debian GNU/Linux 12 (bookworm)
Kernel: 6.12.47+rpt-rpi-v8
Uptime: 2 weeks, 1 day, 2+ hours
Status: ✅ All services active
Reboot: Not required
```

### Secondary (rpi-vpn-2)
```
Hostname: rpi-vpn-2
OS: Debian GNU/Linux 12 (bookworm)
Kernel: 6.12.34+rpt-rpi-v8 → 6.12.47+rpt-rpi-v8 (after reboot)
Uptime: 2 minutes (rebooted)
Status: ✅ All services active
Reboot: ✅ Completed
```

---

## Next Steps

### Immediate (Optional)

1. **Add Custom DNS Records to Secondary** (Recommended)
   - Copy local domain mappings from primary to secondary
   - Ensures full failover capability

2. **Test Failover**
   ```bash
   # Stop primary DNS temporarily
   ssh rpi-vpn-1 "sudo systemctl stop pihole-FTL"

   # Test resolution from client using secondary
   nslookup grafana.stratdata.org 192.168.1.26

   # Restart primary
   ssh rpi-vpn-1 "sudo systemctl start pihole-FTL"
   ```

3. **Set Web Admin Passwords** (if needed)
   ```bash
   ssh rpi-vpn-1 "sudo pihole -a -p"
   ssh rpi-vpn-2 "sudo pihole -a -p"
   ```

---

### Future Monitoring

1. **Regular Updates**
   - Run monthly: `./scripts/update-pihole.sh`
   - Update secondary first (safer)
   - Then update primary

2. **Check for Pi-hole 6 Sync Solutions**
   - Monitor Pi-hole community for v6-compatible sync tools
   - Check official Pi-hole documentation for native features

3. **Monitor DNS Health**
   ```bash
   ./scripts/update-pihole.sh --status
   ```

---

## Summary

✅ **Both Pi-hole servers successfully updated to v6.3**
- Primary: 19 OS packages updated
- Secondary: 102 OS packages updated + major Pi-hole upgrade (v5 → v6)

✅ **DNS Services Operational**
- Primary: Full functionality (external + local DNS)
- Secondary: Backup DNS for external queries

⚠️ **Gravity Sync Incompatible**
- Not compatible with Pi-hole 6.x
- Manual configuration required for synchronization

📋 **Action Required** (Optional):
- Manually add custom DNS records to secondary for full failover capability

---

**Update completed on October 26, 2025**
