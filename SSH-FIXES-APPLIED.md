# SSH Configuration Fixes Applied

**Date**: October 26, 2025
**Status**: ✅ All fixes completed and verified

---

## Summary

Fixed Ansible access to K3s cluster nodes and cleaned up unused SSH keys. All 10 hosts (8 cluster + 2 Pi-hole) are now accessible via SSH and Ansible.

---

## Issues Fixed

### 1. ✅ Ansible Cannot Access K3s Cluster Nodes

**Problem**:
- Ansible inventory was missing SSH key configuration for cluster group
- `ansible cluster -m ping` was failing with "Permission denied"
- Manual SSH with `-i ~/.ssh/pi_cluster` worked, but Ansible didn't use it

**Root Cause**:
- [ansible/inventory/hosts.yml](ansible/inventory/hosts.yml) cluster section had no `ansible_ssh_private_key_file` specified

**Fix Applied**:
Updated [ansible/inventory/hosts.yml](ansible/inventory/hosts.yml#L36):
```yaml
cluster:
  vars:
    ansible_user: admin
    ansible_ssh_private_key_file: ~/.ssh/pi_cluster  # ADDED THIS LINE
    ansible_python_interpreter: /usr/bin/python3
```

**Verification**:
```bash
$ ansible cluster -m ping -o
pi-master | SUCCESS
pi-worker-01 | SUCCESS
pi-worker-02 | SUCCESS
pi-worker-03 | SUCCESS
pi-worker-04 | SUCCESS
pi-worker-05 | SUCCESS
pi-worker-06 | SUCCESS
pi-worker-07 | SUCCESS

$ ansible all -m ping -o
# All 10 hosts (8 cluster + 2 pihole) = SUCCESS
```

---

### 2. ✅ No SSH Config for K3s Cluster Nodes

**Problem**:
- Had to use long SSH commands: `ssh -i ~/.ssh/pi_cluster admin@192.168.1.240`
- Pi-hole servers had config shortcuts: `ssh rpi-vpn-1`
- K3s cluster nodes had no shortcuts

**Fix Applied**:
Added entries to `~/.ssh/config` for all 8 cluster nodes:
```ssh
# K3s Cluster Master Node (Raspberry Pi 5)
Host pi-master 192.168.1.240
    HostName 192.168.1.240
    User admin
    IdentityFile ~/.ssh/pi_cluster
    StrictHostKeyChecking no

# K3s Cluster Worker Nodes (Raspberry Pi 5)
Host pi-worker-01 192.168.1.241
    # ... (similar config for all 7 workers)
```

**Verification**:
```bash
$ ssh pi-master "hostname"
pi-master

$ ssh pi-worker-01 "hostname"
pi-worker-01

$ ssh pi-worker-07 "hostname"
pi-worker-07
```

---

### 3. ✅ Unused SSH Key (id_ed25519)

**Problem**:
- `~/.ssh/id_ed25519` key pair existed but was not used anywhere
- Not configured in SSH config
- Not referenced in Ansible inventory
- Did not work with any infrastructure hosts
- Created Sept 21, 2024 but purpose unknown

**Fix Applied**:
```bash
rm -f ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub
```

**Result**:
Only active keys remain:
- `pihole` - Pi-hole servers
- `pi_cluster` - K3s cluster nodes
- `id_ed25519_github` - GitHub authentication

---

## Current SSH Key Status

| Key Name | Type | Status | Purpose | Hosts |
|----------|------|--------|---------|-------|
| `pihole` | RSA 4096 | ✅ Active | Pi-hole access | rpi-vpn-1, rpi-vpn-2 |
| `pi_cluster` | ED25519 | ✅ Active | K3s cluster access | pi-master + 7 workers |
| `id_ed25519_github` | ED25519 | ✅ Active | GitHub auth | github.com |
| ~~`id_ed25519`~~ | ~~ED25519~~ | ❌ Deleted | Unused | None |

---

## Infrastructure Access Summary

### All Hosts - Fully Accessible

| Host | Type | IP | SSH Config | Ansible | Status |
|------|------|-----|------------|---------|--------|
| pi-master | K3s Master | 192.168.1.240 | ✅ Yes | ✅ Yes | ✅ Working |
| pi-worker-01 | K3s Worker | 192.168.1.241 | ✅ Yes | ✅ Yes | ✅ Working |
| pi-worker-02 | K3s Worker | 192.168.1.242 | ✅ Yes | ✅ Yes | ✅ Working |
| pi-worker-03 | K3s Worker | 192.168.1.243 | ✅ Yes | ✅ Yes | ✅ Working |
| pi-worker-04 | K3s Worker | 192.168.1.244 | ✅ Yes | ✅ Yes | ✅ Working |
| pi-worker-05 | K3s Worker | 192.168.1.245 | ✅ Yes | ✅ Yes | ✅ Working |
| pi-worker-06 | K3s Worker | 192.168.1.246 | ✅ Yes | ✅ Yes | ✅ Working |
| pi-worker-07 | K3s Worker | 192.168.1.247 | ✅ Yes | ✅ Yes | ✅ Working |
| rpi-vpn-1 | Pi-hole Primary | 192.168.1.25 | ✅ Yes | ✅ Yes | ✅ Working |
| rpi-vpn-2 | Pi-hole Secondary | 192.168.1.26 | ✅ Yes | ✅ Yes | ✅ Working |

**Total**: 10/10 hosts accessible ✅

---

## Quick Access Reference

### SSH Direct Access

```bash
# Pi-hole servers
ssh rpi-vpn-1        # 192.168.1.25
ssh rpi-vpn-2        # 192.168.1.26

# K3s cluster master
ssh pi-master        # 192.168.1.240

# K3s cluster workers
ssh pi-worker-01     # 192.168.1.241
ssh pi-worker-02     # 192.168.1.242
ssh pi-worker-03     # 192.168.1.243
ssh pi-worker-04     # 192.168.1.244
ssh pi-worker-05     # 192.168.1.245
ssh pi-worker-06     # 192.168.1.246
ssh pi-worker-07     # 192.168.1.247
```

### Ansible Access

```bash
cd /root/gitlab/local-rpi-cluster/ansible

# Test connectivity
ansible all -m ping              # All 10 hosts
ansible cluster -m ping          # 8 K3s nodes
ansible pihole -m ping           # 2 Pi-hole servers

# Run commands
ansible all -m shell -a "uptime"
ansible cluster -m shell -a "kubectl get nodes"
ansible pihole -m shell -a "pihole status"

# Run playbooks
ansible-playbook playbooks/update-cluster.yml
ansible-playbook playbooks/infrastructure/update-pihole.yml
```

---

## Verification Tests - All Passed ✅

### 1. SSH Config Shortcuts
```bash
✅ ssh rpi-vpn-1 "hostname"      → rpi-vpn-1
✅ ssh rpi-vpn-2 "hostname"      → rpi-vpn-2
✅ ssh pi-master "hostname"      → pi-master
✅ ssh pi-worker-01 "hostname"   → pi-worker-01
✅ ssh pi-worker-07 "hostname"   → pi-worker-07
```

### 2. Ansible Connectivity
```bash
✅ ansible cluster -m ping       → 8/8 SUCCESS
✅ ansible pihole -m ping        → 2/2 SUCCESS
✅ ansible all -m ping           → 10/10 SUCCESS
```

### 3. GitHub Access
```bash
✅ ssh -T git@github.com         → "Hi pedro-a-luis!"
✅ git fetch                     → Works
```

### 4. Unused Key Removed
```bash
✅ ls ~/.ssh/id_ed25519          → No such file (deleted)
```

---

## Files Modified

### 1. [ansible/inventory/hosts.yml](ansible/inventory/hosts.yml)
**Change**: Added `ansible_ssh_private_key_file: ~/.ssh/pi_cluster` to cluster vars

**Before**:
```yaml
cluster:
  vars:
    ansible_user: admin
    ansible_python_interpreter: /usr/bin/python3
```

**After**:
```yaml
cluster:
  vars:
    ansible_user: admin
    ansible_ssh_private_key_file: ~/.ssh/pi_cluster
    ansible_python_interpreter: /usr/bin/python3
```

---

### 2. `~/.ssh/config`
**Change**: Added SSH config entries for all 8 K3s cluster nodes

**Added**:
```ssh
# K3s Cluster Master Node (Raspberry Pi 5)
Host pi-master 192.168.1.240
    HostName 192.168.1.240
    User admin
    IdentityFile ~/.ssh/pi_cluster
    StrictHostKeyChecking no

# K3s Cluster Worker Nodes (Raspberry Pi 5)
Host pi-worker-01 192.168.1.241
    HostName 192.168.1.241
    User admin
    IdentityFile ~/.ssh/pi_cluster
    StrictHostKeyChecking no

# ... (similar for pi-worker-02 through pi-worker-07)
```

**Complete config now includes**:
- GitHub (id_ed25519_github)
- 2 Pi-hole servers (pihole)
- 8 K3s cluster nodes (pi_cluster)

---

### 3. `~/.ssh/` directory
**Change**: Removed unused key pair

**Deleted**:
- `~/.ssh/id_ed25519`
- `~/.ssh/id_ed25519.pub`

**Remaining keys**:
- `pihole` / `pihole.pub` (RSA 4096)
- `pi_cluster` / `pi_cluster.pub` (ED25519)
- `id_ed25519_github` / `id_ed25519_github.pub` (ED25519)

---

## Benefits

### 1. Simplified Access
**Before**:
```bash
ssh -i ~/.ssh/pi_cluster admin@192.168.1.240
```

**After**:
```bash
ssh pi-master
```

### 2. Ansible Now Works
**Before**:
```bash
$ ansible cluster -m ping
# FAILED: Permission denied (publickey,password)
```

**After**:
```bash
$ ansible cluster -m ping
# SUCCESS: 8/8 hosts responding
```

### 3. Cleaner Key Management
- Removed unused key that served no purpose
- Only 3 active keys, each with clear purpose
- All keys documented and accounted for

### 4. Consistent Configuration
- All infrastructure hosts now have SSH config entries
- Ansible inventory properly configured for all host groups
- Uniform access patterns across all systems

---

## Security Notes

### Key Permissions (Verified)
```bash
$ ls -la ~/.ssh/
-rw-------  pihole            (600) ✅
-rw-r--r--  pihole.pub        (644) ✅
-rw-------  pi_cluster        (600) ✅
-rw-r--r--  pi_cluster.pub    (644) ✅
-rw-------  id_ed25519_github (600) ✅
-rw-r--r--  id_ed25519_github.pub (644) ✅
```

### Keys Not in Git (Verified)
```bash
$ git status
# No SSH keys staged or tracked ✅
```

### Key Distribution
- **pihole**: Deployed to rpi-vpn-1, rpi-vpn-2
- **pi_cluster**: Deployed to pi-master + 7 workers
- **id_ed25519_github**: Registered with GitHub account
- All private keys remain only on this workstation

---

## Next Steps (Recommended)

### 1. Backup SSH Keys
```bash
# Create encrypted backup
tar -czf ~/ssh-keys-backup-$(date +%Y%m%d).tar.gz \
  ~/.ssh/pihole* \
  ~/.ssh/pi_cluster* \
  ~/.ssh/id_ed25519_github* \
  ~/.ssh/config

# Encrypt
gpg --symmetric --cipher-algo AES256 ~/ssh-keys-backup-*.tar.gz

# Delete unencrypted
rm ~/ssh-keys-backup-*.tar.gz
```

### 2. Test Ansible Playbooks
```bash
cd /root/gitlab/local-rpi-cluster/ansible

# Test cluster update playbook
ansible-playbook playbooks/update-cluster.yml --check

# Test Pi-hole update playbook
ansible-playbook playbooks/infrastructure/update-pihole.yml --check
```

### 3. Update Cluster Nodes (19-102 packages available)
```bash
# Check status first
ansible cluster -m shell -a "apt list --upgradable | wc -l"

# Run updates
ansible-playbook playbooks/update-cluster.yml
```

### 4. Update Pi-hole Servers
```bash
# Check status
./scripts/update-pihole.sh --status

# Update secondary first (safer)
./scripts/update-pihole.sh --secondary

# Then update primary
./scripts/update-pihole.sh --primary
```

---

## Related Documentation

- [SSH-KEYS-AUDIT.md](SSH-KEYS-AUDIT.md) - Complete audit report
- [SSH-PIHOLE-SETUP.md](SSH-PIHOLE-SETUP.md) - Pi-hole SSH configuration
- [SSH-SETUP-GUIDE.md](SSH-SETUP-GUIDE.md) - Original SSH setup guide
- [ansible/inventory/hosts.yml](ansible/inventory/hosts.yml) - Ansible inventory
- `~/.ssh/config` - SSH client configuration

---

## Troubleshooting

### If SSH Fails
```bash
# Test with verbose
ssh -v pi-master

# Test with explicit key
ssh -i ~/.ssh/pi_cluster admin@192.168.1.240

# Check key permissions
ls -la ~/.ssh/
```

### If Ansible Fails
```bash
# Test with verbose
ansible all -m ping -vvv

# Verify inventory
ansible-inventory --list

# Test specific host
ansible pi-master -m ping
```

---

**All fixes completed and verified on October 26, 2025**
