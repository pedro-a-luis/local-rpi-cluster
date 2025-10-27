# SSH Keys Audit Report

**Date**: October 26, 2025
**Location**: `/root/.ssh/`

---

## Summary

| Key Name | Type | Bits | Status | Purpose |
|----------|------|------|--------|---------|
| `pihole` | RSA | 4096 | ✅ **IN USE** | Pi-hole servers access |
| `pi_cluster` | ED25519 | 256 | ✅ **IN USE** | K3s cluster nodes access |
| `id_ed25519_github` | ED25519 | 256 | ✅ **IN USE** | GitHub authentication |
| `id_ed25519` | ED25519 | 256 | ⚠️ **UNUSED** | Unknown/Redundant |

---

## Detailed Analysis

### ✅ Active Keys (IN USE)

#### 1. `~/.ssh/pihole` / `pihole.pub`
- **Type**: RSA 4096-bit
- **Created**: October 26, 2025
- **Comment**: pihole-admin
- **Purpose**: Access to Pi-hole DNS servers
- **Used by**:
  - SSH config for rpi-vpn-1 (192.168.1.25)
  - SSH config for rpi-vpn-2 (192.168.1.26)
  - Ansible inventory for pihole group
- **Deployed to**:
  - rpi-vpn-1 (`/home/admin/.ssh/authorized_keys`)
  - rpi-vpn-2 (`/home/admin/.ssh/authorized_keys`)
- **Verification**: ✅ Tested and working

```bash
# Test commands
ssh rpi-vpn-1  # Works
ssh rpi-vpn-2  # Works
ansible pihole -m ping  # SUCCESS
```

---

#### 2. `~/.ssh/pi_cluster` / `pi_cluster.pub`
- **Type**: ED25519 256-bit
- **Created**: May 27, 2024
- **Purpose**: Access to K3s cluster nodes (8x Raspberry Pi 5)
- **Used by**: Manual SSH connections (NOT configured in Ansible inventory yet)
- **Deployed to**: All cluster nodes (pi-master + 7 workers)
- **Verification**: ✅ Tested and working

```bash
# Test command
ssh -i ~/.ssh/pi_cluster admin@192.168.1.240  # Works (pi-master)
```

**⚠️ Issue**: Ansible inventory doesn't specify this key for cluster nodes, causing Ansible commands to fail:
```bash
ansible cluster -m ping  # FAILS - Permission denied
```

**Recommendation**: Update [ansible/inventory/hosts.yml](ansible/inventory/hosts.yml) cluster section to add:
```yaml
cluster:
  vars:
    ansible_user: admin
    ansible_ssh_private_key_file: ~/.ssh/pi_cluster
    ansible_python_interpreter: /usr/bin/python3
```

---

#### 3. `~/.ssh/id_ed25519_github` / `id_ed25519_github.pub`
- **Type**: ED25519 256-bit
- **Created**: October 18, 2024
- **Purpose**: GitHub authentication
- **Used by**: SSH config for github.com
- **Verification**: ✅ Tested and working

```bash
# Test command
ssh -T git@github.com  # "Hi pedro-a-luis! You've successfully authenticated"
```

**Git Repository**:
- Remote: `git@github.com:pedro-a-luis/local-rpi-cluster.git`
- Uses this key for push/pull operations

---

### ⚠️ Unused Keys (REDUNDANT)

#### 4. `~/.ssh/id_ed25519` / `id_ed25519.pub`
- **Type**: ED25519 256-bit
- **Created**: September 21, 2024
- **Status**: ⚠️ **UNUSED** - No references found
- **Not configured in**:
  - SSH config
  - Ansible inventory
  - Git configuration
- **Test results**: Does NOT work with cluster nodes or Pi-hole servers

**Recommendation**:
- **SAFE TO DELETE** if you don't need it for other systems
- Before deletion, check if deployed to any other systems you manage
- Consider if this was used for a previous setup that's no longer active

```bash
# To remove (after verifying it's not needed):
rm ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub
```

---

## SSH Configuration Status

### Current `~/.ssh/config`

```ssh
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_github
  IdentitiesOnly yes

# Pi-hole DNS Servers (Raspberry Pi 3)
Host rpi-vpn-1 192.168.1.25
    HostName 192.168.1.25
    User admin
    IdentityFile ~/.ssh/pihole
    StrictHostKeyChecking no

Host rpi-vpn-2 192.168.1.26
    HostName 192.168.1.26
    User admin
    IdentityFile ~/.ssh/pihole
    StrictHostKeyChecking no
```

### Missing Configuration

No SSH config entries for K3s cluster nodes. Consider adding:

```ssh
# K3s Cluster Nodes (Raspberry Pi 5)
Host pi-master 192.168.1.240
    HostName 192.168.1.240
    User admin
    IdentityFile ~/.ssh/pi_cluster
    StrictHostKeyChecking no

Host pi-worker-* 192.168.1.24[1-7]
    User admin
    IdentityFile ~/.ssh/pi_cluster
    StrictHostKeyChecking no
```

---

## Ansible Inventory Status

### Current Configuration

✅ **Pi-hole group** - Properly configured:
```yaml
pihole:
  vars:
    ansible_user: admin
    ansible_ssh_private_key_file: ~/.ssh/pihole
```

⚠️ **Cluster group** - Missing SSH key configuration:
```yaml
cluster:
  vars:
    ansible_user: admin
    # MISSING: ansible_ssh_private_key_file: ~/.ssh/pi_cluster
    ansible_python_interpreter: /usr/bin/python3
```

---

## Infrastructure Access Matrix

| Infrastructure | Servers | Key Used | SSH Config | Ansible Config | Status |
|----------------|---------|----------|------------|----------------|--------|
| **Pi-hole DNS** | rpi-vpn-1, rpi-vpn-2 | `pihole` | ✅ Yes | ✅ Yes | ✅ Working |
| **K3s Cluster** | pi-master + 7 workers | `pi_cluster` | ❌ No | ❌ No | ⚠️ Manual Only |
| **GitHub** | github.com | `id_ed25519_github` | ✅ Yes | N/A | ✅ Working |

---

## Recommendations

### 1. Fix Ansible Access to K3s Cluster (HIGH PRIORITY)

Update [ansible/inventory/hosts.yml](ansible/inventory/hosts.yml):

```yaml
cluster:
  children:
    master:
      hosts:
        pi-master:
          ansible_host: 192.168.1.240
          node_ip: 192.168.1.240
    workers:
      hosts:
        pi-worker-01:
          ansible_host: 192.168.1.241
          node_ip: 192.168.1.241
        # ... (other workers)
  vars:
    ansible_user: admin
    ansible_ssh_private_key_file: ~/.ssh/pi_cluster  # ADD THIS LINE
    ansible_python_interpreter: /usr/bin/python3
```

**Verification**:
```bash
cd /root/gitlab/local-rpi-cluster/ansible
ansible cluster -m ping  # Should succeed
ansible all -m ping      # Should succeed (both cluster and pihole)
```

---

### 2. Add K3s Cluster SSH Config (MEDIUM PRIORITY)

Add to `~/.ssh/config`:

```ssh
# K3s Cluster Nodes (Raspberry Pi 5)
Host pi-master 192.168.1.240
    HostName 192.168.1.240
    User admin
    IdentityFile ~/.ssh/pi_cluster
    StrictHostKeyChecking no

Host pi-worker-01 192.168.1.241
    HostName 192.168.1.241
    User admin
    IdentityFile ~/.ssh/pi_cluster
    StrictHostKeyChecking no

Host pi-worker-02 192.168.1.242
    HostName 192.168.1.242
    User admin
    IdentityFile ~/.ssh/pi_cluster
    StrictHostKeyChecking no

# ... (add remaining workers)
```

**Benefits**:
- Simpler SSH commands: `ssh pi-master` instead of `ssh -i ~/.ssh/pi_cluster admin@192.168.1.240`
- Consistent with Pi-hole configuration style

---

### 3. Remove Unused SSH Key (LOW PRIORITY)

If `id_ed25519` is not used elsewhere:

```bash
# Check if key is deployed anywhere
ssh -i ~/.ssh/id_ed25519 admin@192.168.1.240  # Test cluster
ssh -i ~/.ssh/id_ed25519 admin@192.168.1.25   # Test pihole

# If both fail and you don't recognize the key's purpose:
rm ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub
```

**⚠️ Caution**: Only delete if you're certain it's not used for:
- Other Raspberry Pi systems not in this inventory
- External servers or services
- CI/CD pipelines
- Backup systems

---

### 4. Security Best Practices

#### Key Permissions (Already Correct)
```bash
ls -la ~/.ssh/
# Private keys: -rw------- (600) ✅
# Public keys:  -rw-r--r-- (644) ✅
```

#### Key Backup
Consider backing up active keys securely:

```bash
# Create encrypted backup
tar -czf ~/ssh-keys-backup-$(date +%Y%m%d).tar.gz \
  ~/.ssh/pihole \
  ~/.ssh/pihole.pub \
  ~/.ssh/pi_cluster \
  ~/.ssh/pi_cluster.pub \
  ~/.ssh/id_ed25519_github \
  ~/.ssh/id_ed25519_github.pub \
  ~/.ssh/config

# Encrypt the backup
gpg --symmetric --cipher-algo AES256 ~/ssh-keys-backup-*.tar.gz

# Store encrypted file safely, delete unencrypted version
rm ~/ssh-keys-backup-*.tar.gz
```

#### Git Security
✅ Keys are NOT in Git repository (verified)
✅ `.gitignore` should include `*.pem`, `*.key`, `id_rsa*`, etc.

---

## Testing Commands

### Test All Active Keys

```bash
# 1. Test Pi-hole access
echo "=== Testing Pi-hole Keys ==="
ssh rpi-vpn-1 "hostname"          # Should: rpi-vpn-1
ssh rpi-vpn-2 "hostname"          # Should: rpi-vpn-2
ansible pihole -m ping            # Should: SUCCESS

# 2. Test K3s Cluster access (manual)
echo "=== Testing K3s Cluster Keys ==="
ssh -i ~/.ssh/pi_cluster admin@192.168.1.240 "hostname"  # Should: pi-master
ssh -i ~/.ssh/pi_cluster admin@192.168.1.241 "hostname"  # Should: pi-worker-01

# 3. Test GitHub access
echo "=== Testing GitHub Key ==="
ssh -T git@github.com             # Should: "Hi pedro-a-luis!"
cd /root/gitlab/local-rpi-cluster && git fetch  # Should: work

# 4. Test unused key
echo "=== Testing Unused Key ==="
ssh -i ~/.ssh/id_ed25519 admin@192.168.1.240 2>&1 | grep -q "Permission denied" && echo "UNUSED (as expected)"
```

---

## Quick Reference

### SSH Commands

```bash
# Pi-hole servers (configured)
ssh rpi-vpn-1
ssh rpi-vpn-2

# K3s cluster nodes (manual - need full command)
ssh -i ~/.ssh/pi_cluster admin@192.168.1.240  # pi-master
ssh -i ~/.ssh/pi_cluster admin@192.168.1.241  # pi-worker-01
# ... etc

# GitHub
git push/pull  # Uses id_ed25519_github automatically
```

### Ansible Commands

```bash
cd /root/gitlab/local-rpi-cluster/ansible

# Pi-hole (working)
ansible pihole -m ping
ansible pihole -m shell -a "pihole status"

# K3s Cluster (not working - needs fix in recommendation #1)
ansible cluster -m ping  # Currently FAILS
ansible all -m ping      # Currently FAILS on cluster hosts
```

---

## File Locations

### SSH Keys
- Private keys: `/root/.ssh/pihole`, `/root/.ssh/pi_cluster`, `/root/.ssh/id_ed25519_github`, `/root/.ssh/id_ed25519`
- Public keys: Same names with `.pub` extension
- SSH config: `/root/.ssh/config`

### Ansible Configuration
- Inventory: `/root/gitlab/local-rpi-cluster/ansible/inventory/hosts.yml`
- Ansible config: `/root/gitlab/local-rpi-cluster/ansible/ansible.cfg`

### Documentation
- This report: `/root/gitlab/local-rpi-cluster/SSH-KEYS-AUDIT.md`
- Pi-hole setup: `/root/gitlab/local-rpi-cluster/SSH-PIHOLE-SETUP.md`
- Previous SSH guide: `/root/gitlab/local-rpi-cluster/SSH-SETUP-GUIDE.md`

---

**Report generated on October 26, 2025**
