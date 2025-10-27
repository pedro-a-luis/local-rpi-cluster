# Pi-hole Maintenance Guide

**Quick Reference for Pi-hole DNS Server Maintenance**

---

## Quick Commands

### Check Status
```bash
# Using convenience script
./scripts/update-pihole.sh --status

# Or manually
ssh admin@192.168.1.25 "pihole status"
ssh admin@192.168.1.26 "pihole status"
```

### Update Pi-hole
```bash
# Recommended: Update both (one at a time)
./scripts/update-pihole.sh

# Update secondary first (safer)
./scripts/update-pihole.sh --secondary

# Update primary only
./scripts/update-pihole.sh --primary

# Check for updates without applying
./scripts/update-pihole.sh --check
```

### Update Gravity Only (Fast)
```bash
# Just update blocklists
./scripts/update-pihole.sh --dns-only

# Or manually
ssh admin@192.168.1.25 "pihole -g"
ssh admin@192.168.1.26 "pihole -g"
```

---

## Server Information

| Server | Hostname | IP | Role | WireGuard |
|--------|----------|-----|------|-----------|
| Primary | rpi-vpn-1 | 192.168.1.25 | Primary DNS + VPN | ✅ Active |
| Secondary | rpi-vpn-2 | 192.168.1.26 | Secondary DNS + VPN | ✅ Active |

**Credentials**: admin / Admin123
**Web Interface**: http://192.168.1.25/admin, http://192.168.1.26/admin

---

## Common Tasks

### View Pi-hole Version
```bash
ssh admin@192.168.1.25 "pihole -v"
```

### Check DNS Resolution
```bash
# Test from external host
nslookup grafana.stratdata.org 192.168.1.25
nslookup grafana.stratdata.org 192.168.1.26

# Test from Pi-hole itself
ssh admin@192.168.1.25 "nslookup grafana.stratdata.org 127.0.0.1"
```

### View Query Logs (Real-time)
```bash
ssh admin@192.168.1.25 "pihole -t"
```

### View Statistics
```bash
ssh admin@192.168.1.25 "pihole -c"
```

### Restart Pi-hole Service
```bash
ssh admin@192.168.1.25 "pihole restartdns"

# Or using systemd
ssh admin@192.168.1.25 "sudo systemctl restart pihole-FTL"
```

### Flush DNS Cache
```bash
ssh admin@192.168.1.25 "pihole restartdns reload-lists"
```

---

## DNS Management

### Add DNS Entry
```bash
ssh admin@192.168.1.25
echo "address=/newservice.stratdata.org/192.168.1.240" | sudo tee -a /etc/dnsmasq.d/99-stratdata-local.conf
sudo pihole restartdns

# Repeat for secondary
ssh admin@192.168.1.26
# ... same commands
```

### View Current DNS Entries
```bash
ssh admin@192.168.1.25 "cat /etc/dnsmasq.d/99-stratdata-local.conf"
```

### Update All DNS Entries (Ansible)
```bash
# Use the DNS update playbook
ansible-playbook ansible/playbooks/infrastructure/update-pihole-dns.yml
```

See: [DNS Setup Guide](../getting-started/dns-setup-guide.md)

---

## Backup & Restore

### Backup Configuration
```bash
# Via web interface: Settings → Teleporter → Backup

# Or via SSH
ssh admin@192.168.1.25
tar -czf pihole-backup-$(date +%Y%m%d).tar.gz \
    /etc/pihole/ \
    /etc/dnsmasq.d/

# Download backup
scp admin@192.168.1.25:~/pihole-backup-*.tar.gz ./
```

### Restore Configuration
```bash
# Via web interface: Settings → Teleporter → Restore

# Or via SSH
ssh admin@192.168.1.25
sudo pihole -a restorebackup /path/to/backup.tar.gz
```

---

## Troubleshooting

### DNS Not Responding

**Check Service Status:**
```bash
ssh admin@192.168.1.25 "sudo systemctl status pihole-FTL"
```

**Check Port Binding:**
```bash
ssh admin@192.168.1.25 "sudo netstat -tulpn | grep :53"
```

**Restart Service:**
```bash
ssh admin@192.168.1.25 "sudo systemctl restart pihole-FTL"
```

**Check Logs:**
```bash
ssh admin@192.168.1.25 "sudo tail -f /var/log/pihole/pihole.log"
ssh admin@192.168.1.25 "sudo tail -f /var/log/pihole/FTL.log"
```

---

### Gravity Update Fails

**Clear Cache and Retry:**
```bash
ssh admin@192.168.1.25
sudo rm -rf /etc/pihole/gravity.db*
pihole -g
```

**Check Internet Connectivity:**
```bash
ssh admin@192.168.1.25 "ping -c 3 8.8.8.8"
ssh admin@192.168.1.25 "ping -c 3 google.com"
```

---

### High CPU/Memory Usage

**Check Resource Usage:**
```bash
ssh admin@192.168.1.25 "top -bn1 | head -20"
```

**Check Query Load:**
```bash
ssh admin@192.168.1.25 "pihole -c -e"
```

**Restart if Needed:**
```bash
ssh admin@192.168.1.25 "sudo systemctl restart pihole-FTL"
```

---

### Config Sync Between Servers

**Manual Sync (Primary → Secondary):**
```bash
# Copy DNS config
scp admin@192.168.1.25:/etc/dnsmasq.d/99-stratdata-local.conf \
    admin@192.168.1.26:/tmp/

ssh admin@192.168.1.26 "sudo mv /tmp/99-stratdata-local.conf /etc/dnsmasq.d/ && sudo pihole restartdns"

# Copy gravity database (optional)
scp admin@192.168.1.25:/etc/pihole/gravity.db \
    admin@192.168.1.26:/tmp/

ssh admin@192.168.1.26 "sudo mv /tmp/gravity.db /etc/pihole/ && sudo pihole restartdns"
```

**Automated Sync:**
Check if sync script exists: `/usr/local/bin/pihole-sync.sh`

---

## Monitoring

### Key Metrics to Watch

1. **DNS Response Time**: Should be < 50ms
2. **Queries Blocked**: Typical 10-30% of total
3. **Memory Usage**: Should be < 50%
4. **CPU Usage**: Should be < 20%
5. **Disk Space**: Should have > 1GB free

### Prometheus Metrics

If integrated with Prometheus:
```bash
# Check if Pi-hole exporter is running
ssh admin@192.168.1.25 "systemctl status pihole-exporter"
```

---

## Security

### Change Admin Password

**Via Web Interface:**
1. Login to http://192.168.1.25/admin
2. Settings → API/Web interface
3. Set new password

**Via Command Line:**
```bash
ssh admin@192.168.1.25 "pihole -a -p"
# Enter new password when prompted
```

⚠️ **IMPORTANT**: Update password on BOTH servers and in your documentation!

### Update WireGuard Keys

```bash
ssh admin@192.168.1.25
sudo wg show
# Check peer configurations

# Regenerate keys if needed
wg genkey | tee /tmp/privatekey | wg pubkey > /tmp/publickey
```

---

## Maintenance Schedule

### Weekly
- [ ] Check query logs for anomalies
- [ ] Verify both servers responding
- [ ] Update gravity database

### Monthly
- [ ] Run full system updates (OS + Pi-hole)
- [ ] Review blocked/allowed domains
- [ ] Check disk space
- [ ] Review DNS entries for outdated services

### Quarterly
- [ ] Backup configuration
- [ ] Review blocklist subscriptions
- [ ] Check WireGuard VPN connections
- [ ] Security audit (passwords, access logs)

---

## Useful Pi-hole Commands

```bash
# Status and control
pihole status                    # Show status
pihole restartdns               # Restart DNS service
pihole restartdns reload-lists  # Reload blocklists
pihole enable                   # Enable blocking
pihole disable 10m              # Disable blocking for 10 minutes

# Updates
pihole -up                      # Update Pi-hole
pihole -g                       # Update gravity (blocklists)
pihole -r                       # Repair/reconfigure

# Information
pihole -v                       # Show versions
pihole -c                       # Show statistics (interactive)
pihole -c -e                    # Show statistics (export)
pihole -t                       # Tail query log

# Lists management
pihole -w domain.com            # Whitelist domain
pihole -b domain.com            # Blacklist domain
pihole -wild domain.com         # Wildcard blacklist

# Query management
pihole -q domain.com            # Query logs for domain
pihole -fl                      # Flush logs

# Admin
pihole -a -p                    # Change admin password
pihole -a -t                    # Set temperature unit
pihole checkout                 # Switch branches/versions
```

---

## Related Documentation

- [DNS Setup Guide](../getting-started/dns-setup-guide.md) - Complete DNS configuration
- [Pi-hole Update Guide](../../ansible/playbooks/infrastructure/PIHOLE-UPDATE-GUIDE.md) - Detailed update procedures
- [Cluster Access Guide](../getting-started/cluster-access-guide.md) - Access credentials
- [Security Update](../../SECURITY-UPDATE.md) - Security recommendations

---

## Support Resources

### Pi-hole Documentation
- Official Docs: https://docs.pi-hole.net/
- FAQ: https://docs.pi-hole.net/main/faq/
- Troubleshooting: https://docs.pi-hole.net/guides/dns/

### Community
- Reddit: r/pihole
- Discourse: https://discourse.pi-hole.net/

---

**Last Updated**: October 21, 2025
**Maintained By**: Infrastructure Team
