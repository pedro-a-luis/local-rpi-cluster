# Pi-hole Update Guide

**Playbook**: `update-pihole.yml`
**Servers**: rpi-vpn-1 (192.168.1.25), rpi-vpn-2 (192.168.1.26)
**Purpose**: Update Pi-hole software, OS packages, gravity database, and WireGuard

---

## Quick Start

### Prerequisites

1. **SSH Keys Configured**
   ```bash
   # Copy your SSH key to both Pi-hole servers
   ssh-copy-id admin@192.168.1.25
   ssh-copy-id admin@192.168.1.26

   # Test SSH access (should not ask for password)
   ssh admin@192.168.1.25 "hostname"
   ssh admin@192.168.1.26 "hostname"
   ```

2. **Ansible Installed**
   ```bash
   # Check Ansible version
   ansible --version

   # Install if needed
   pip install ansible
   ```

3. **Inventory Configured**
   - Already configured in `ansible/inventory/hosts.yml`
   - Hosts: `rpi-vpn-1`, `rpi-vpn-2` in `pihole` group

---

## Usage

### Standard Update (Recommended)

Updates both Pi-hole servers one at a time to maintain DNS availability:

```bash
# From this repository root
cd /root/gitlab/local-rpi-cluster
ansible-playbook ansible/playbooks/infrastructure/update-pihole.yml

# OR from pi-master
ssh admin@192.168.1.240
cd /home/admin/ansible
ansible-playbook playbooks/infrastructure/update-pihole.yml
```

---

### Update Primary Only

```bash
ansible-playbook ansible/playbooks/infrastructure/update-pihole.yml --limit rpi-vpn-1
```

---

### Update Secondary Only

```bash
ansible-playbook ansible/playbooks/infrastructure/update-pihole.yml --limit rpi-vpn-2
```

---

### Check for Updates (Dry Run)

```bash
ansible-playbook ansible/playbooks/infrastructure/update-pihole.yml --check
```

---

## What the Playbook Does

### Phase 1: Pre-Update Checks
- Displays current system information
- Shows Pi-hole version
- Checks Pi-hole status
- Lists available OS package updates

### Phase 2: Update OS Packages
- Updates package cache
- Performs `dist-upgrade` on all packages
- Removes orphaned packages
- Cleans package cache

### Phase 3: Update Pi-hole
- Runs `pihole -up` (updates Pi-hole core, web interface, FTL)
- Updates gravity database (blocklists)
- Checks WireGuard status and updates if needed

### Phase 4: Reboot (if required)
- Checks if kernel/critical packages need reboot
- Reboots server if needed
- Updates one server at a time (maintains DNS availability)

### Phase 5: Post-Update Verification
- Verifies all services are running
  - SSH
  - Pi-hole FTL (DNS service)
  - WireGuard VPN
- Tests local DNS resolution
- Displays Pi-hole statistics

### Phase 6: Final Health Check
- Queries DNS from both servers
- Verifies responses from external location
- Provides summary and recommendations

---

## Update Strategy

### Recommended: Secondary First
```bash
# Step 1: Update secondary (safer, less impact)
ansible-playbook ansible/playbooks/infrastructure/update-pihole.yml --limit rpi-vpn-2

# Step 2: Verify DNS still working
nslookup grafana.stratdata.org 192.168.1.26
nslookup grafana.stratdata.org 192.168.1.25

# Step 3: Update primary
ansible-playbook ansible/playbooks/infrastructure/update-pihole.yml --limit rpi-vpn-1

# Step 4: Final verification
nslookup grafana.stratdata.org 192.168.1.25
nslookup grafana.stratdata.org 192.168.1.26
```

### Alternative: Both Simultaneously (Faster but riskier)
```bash
# Update both at once (DNS will be down briefly during reboot)
ansible-playbook ansible/playbooks/infrastructure/update-pihole.yml

# Note: The playbook uses serial: 1, so it will still update one at a time
```

---

## Monitoring Update Progress

### Follow Live Output
The playbook provides detailed output showing:
- Current system version and uptime
- Packages being upgraded
- Pi-hole update progress
- Reboot notifications
- Service verification results

### Check Status During Update

**From another terminal**:
```bash
# Check if server is responding
ping 192.168.1.25

# Check DNS service
nslookup grafana.stratdata.org 192.168.1.25

# SSH to check status (if not rebooting)
ssh admin@192.168.1.25 "pihole status"
```

---

## What Gets Updated

### Operating System
- All Debian/Raspberry Pi OS packages
- Security updates
- Kernel updates (if available)

### Pi-hole Components
- **Pi-hole Core** - Main blocking engine
- **Web Interface** - Admin dashboard
- **FTL (Faster Than Light)** - DNS and DHCP server
- **Gravity Database** - Blocklist compilation

### Additional Software
- **WireGuard VPN** - If enabled
- **System utilities** - All installed packages

---

## Expected Duration

| Phase | Duration | Notes |
|-------|----------|-------|
| Pre-checks | 30 sec | Quick system info gathering |
| OS update | 2-5 min | Depends on packages available |
| Pi-hole update | 1-2 min | Usually quick if already recent |
| Gravity update | 1-3 min | Downloads and compiles blocklists |
| Reboot | 1-2 min | Only if kernel/critical updates |
| Verification | 30 sec | Service checks and DNS tests |
| **Total per server** | **5-15 min** | Typical update time |
| **Both servers (serial)** | **10-30 min** | One at a time for HA |

---

## Troubleshooting

### SSH Connection Fails

**Problem**: `Permission denied (publickey,password)`

**Solution**:
```bash
# Copy SSH key
ssh-copy-id admin@192.168.1.25

# Or specify key explicitly
ansible-playbook ansible/playbooks/infrastructure/update-pihole.yml \
  --private-key ~/.ssh/pi_cluster
```

---

### Pi-hole Update Fails

**Problem**: `pihole -up` returns errors

**Solution**:
```bash
# SSH to server
ssh admin@192.168.1.25

# Check Pi-hole status
pihole status

# Repair Pi-hole
pihole -r  # Select "Repair"

# Or reinstall
curl -sSL https://install.pi-hole.net | bash
```

---

### DNS Not Responding After Update

**Problem**: Cannot resolve DNS queries

**Solution**:
```bash
# SSH to server
ssh admin@192.168.1.25

# Check FTL status
sudo systemctl status pihole-FTL

# Restart if needed
sudo systemctl restart pihole-FTL

# Check firewall
sudo iptables -L -n | grep 53

# Test locally
nslookup google.com 127.0.0.1
```

---

### Server Doesn't Reboot

**Problem**: Playbook hangs at reboot

**Solution**:
```bash
# Wait 5 minutes for timeout

# Manual reboot from another terminal
ssh admin@192.168.1.25 "sudo reboot"

# Or force reboot (if accessible via network)
ssh admin@192.168.1.25 "sudo reboot -f"

# Physical access may be needed if network is down
```

---

### Gravity Update Fails

**Problem**: `pihole -g` fails to update blocklists

**Solution**:
```bash
# SSH to server
ssh admin@192.168.1.25

# Check internet connectivity
ping 8.8.8.8

# Update gravity with verbose output
pihole -g -v

# Clear gravity cache and retry
sudo rm -rf /etc/pihole/gravity.db
pihole -g
```

---

## Post-Update Verification

### From Your Workstation

```bash
# Test DNS resolution from both servers
nslookup grafana.stratdata.org 192.168.1.25
nslookup grafana.stratdata.org 192.168.1.26

# Test ad blocking (should return 0.0.0.0)
nslookup ads.example.com 192.168.1.25

# Check services are accessible
curl -I https://grafana.stratdata.org
curl -I https://airflow.stratdata.org
```

---

### From Pi-hole Admin Interface

1. Open http://192.168.1.25/admin (Primary)
2. Open http://192.168.1.26/admin (Secondary)
3. Login with: **admin** / **Admin123**
4. Check dashboard:
   - Queries blocked today
   - Domains on blocklist
   - Status indicators (should all be green)

---

### From Pi-hole Server

```bash
# SSH to server
ssh admin@192.168.1.25

# Check Pi-hole version
pihole -v

# Check status
pihole status

# View statistics
pihole -c

# Check query log
pihole -t
```

---

## Maintenance Schedule

### Regular Updates
- **Monthly**: Run update playbook for OS and Pi-hole
- **Weekly**: Update gravity database only
- **Quarterly**: Full system review and cleanup

### Gravity Update Only

```bash
# Just update blocklists (fast)
ansible pihole -m shell -a "pihole -g"
```

### Check for Updates Without Installing

```bash
# Dry run - see what would be updated
ansible-playbook ansible/playbooks/infrastructure/update-pihole.yml --check
```

---

## Rollback Procedure

If update causes issues:

### Restore from Backup (if available)
```bash
# SSH to Pi-hole
ssh admin@192.168.1.25

# Restore Pi-hole configuration
sudo pihole -a restorebackup /path/to/backup.tar.gz
```

### Downgrade Pi-hole
```bash
# SSH to Pi-hole
ssh admin@192.168.1.25

# Checkout specific version
cd /etc/.pihole
sudo git checkout v5.x  # Replace with desired version
pihole -r  # Repair
```

### Restore System (Nuclear Option)
```bash
# If you have system backup from Velero or other tool
# Restore entire Pi-hole server from backup
```

---

## Advanced Options

### Skip Reboot (Don't Reboot Even If Needed)

Modify the playbook temporarily or use tags (if implemented):
```bash
# Edit playbook, comment out reboot task
# Or add condition: when: false
```

### Update Specific Components Only

```bash
# Just Pi-hole (no OS updates)
ansible pihole -m shell -a "pihole -up" -b

# Just gravity
ansible pihole -m shell -a "pihole -g" -b

# Just OS packages
ansible pihole -m apt -a "upgrade=dist" -b
```

---

## Integration with Cluster Updates

Update Pi-hole as part of full infrastructure update:

```bash
# 1. Update Pi-hole servers first (most critical)
ansible-playbook ansible/playbooks/infrastructure/update-pihole.yml

# 2. Update cluster nodes
ansible-playbook ansible/playbooks/update-cluster.yml

# 3. Update certificates if needed
ansible-playbook ansible/playbooks/infrastructure/update-certificates.yml

# 4. Verify everything
kubectl get nodes
kubectl get pods --all-namespaces
```

---

## Security Considerations

### Before Update
- ✅ DNS servers are redundant (secondary handles during primary update)
- ✅ Updates are serialized (one at a time)
- ✅ Services are verified after update
- ✅ Rollback procedure documented

### After Update
- [ ] Verify no security vulnerabilities remain: `apt list --upgradable`
- [ ] Check Pi-hole query logs for anomalies
- [ ] Review WireGuard VPN connections
- [ ] Update documentation if versions changed

---

## Credentials

**Pi-hole Admin**:
- URL: http://192.168.1.25/admin
- Username: admin
- Password: Admin123

⚠️ **SECURITY NOTE**: These credentials are documented in Git. See [SECURITY-UPDATE.md](../../../SECURITY-UPDATE.md) for remediation steps.

---

## Related Documentation

- [Pi-hole Official Docs](https://docs.pi-hole.net/)
- [DNS Setup Guide](../../docs/getting-started/dns-setup-guide.md)
- [Cluster Update Guide](../../docs/operations/cluster-lifecycle.md)
- [Security Update](../../SECURITY-UPDATE.md)

---

**Last Updated**: October 21, 2025
**Playbook Version**: 1.0
**Maintained By**: Infrastructure Team
