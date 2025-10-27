# SSH Key Configuration Guide

**Current Status**:
- ✅ Cluster nodes (8/8) - SSH keys already configured
- ❌ Pi-hole servers (0/2) - Need SSH key setup

---

## Quick Setup - Pi-hole Servers

You need to manually copy the SSH key to the Pi-hole servers since this is the first time.

### Option 1: Interactive Password Entry (Easiest)

Run these commands and enter the password when prompted:

```bash
# Primary Pi-hole (password: Admin123)
ssh-copy-id -i ~/.ssh/pi_cluster.pub admin@192.168.1.25

# Secondary Pi-hole (password: Admin123)
ssh-copy-id -i ~/.ssh/pi_cluster.pub admin@192.168.1.26
```

**Expected output:**
```
Number of key(s) added: 1

Now try logging into the machine, with:   "ssh 'admin@192.168.1.25'"
and check to make sure that only the key(s) you wanted were added.
```

---

### Option 2: Using the Setup Script

After manually copying keys once, the script can test connectivity:

```bash
# Copy keys manually first (Option 1 above)
ssh-copy-id -i ~/.ssh/pi_cluster.pub admin@192.168.1.25
ssh-copy-id -i ~/.ssh/pi_cluster.pub admin@192.168.1.26

# Then test with the script
./scripts/setup-ssh-keys.sh --test
```

---

### Option 3: One-liner Setup

```bash
# Both servers at once
for ip in 192.168.1.25 192.168.1.26; do
    echo "Setting up SSH for admin@$ip"
    ssh-copy-id -i ~/.ssh/pi_cluster.pub admin@$ip
done
```

---

## Verification

### Test SSH Access (No Password)

```bash
# Test cluster master
ssh -i ~/.ssh/pi_cluster admin@192.168.1.240 "hostname"
# Should output: pi-master

# Test Pi-hole primary
ssh -i ~/.ssh/pi_cluster admin@192.168.1.25 "hostname"
# Should output: rpi-vpn-1

# Test Pi-hole secondary
ssh -i ~/.ssh/pi_cluster admin@192.168.1.26 "hostname"
# Should output: rpi-vpn-2

# Or use the test script
./scripts/setup-ssh-keys.sh --test
```

**Expected result:** All 10 hosts should show ✓ SSH working

---

## Update SSH Config (Optional but Recommended)

Add convenient shortcuts to your SSH config:

```bash
./scripts/setup-ssh-keys.sh --update-config
```

This allows you to use shortcuts:
```bash
ssh pi-master           # Instead of: ssh admin@192.168.1.240
ssh rpi-vpn-1           # Instead of: ssh admin@192.168.1.25
ssh pihole-primary      # Alias for rpi-vpn-1
ssh pi-worker-01        # Instead of: ssh admin@192.168.1.241
```

---

## Troubleshooting

### "Permission denied (publickey)"

**Problem:** Key not copied correctly

**Solution:**
```bash
# Verify key exists
ls -la ~/.ssh/pi_cluster*

# Try copying again
ssh-copy-id -i ~/.ssh/pi_cluster.pub admin@192.168.1.25

# Or manually
cat ~/.ssh/pi_cluster.pub | ssh admin@192.168.1.25 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

---

### "Could not resolve hostname"

**Problem:** DNS not working or wrong IP

**Solution:**
```bash
# Use IP directly
ssh-copy-id -i ~/.ssh/pi_cluster.pub admin@192.168.1.25

# Or check DNS
nslookup rpi-vpn-1
```

---

### "Connection refused" or "Timeout"

**Problem:** SSH service not running or firewall blocking

**Solution:**
```bash
# Check if host is reachable
ping 192.168.1.25

# Check if SSH port is open
nc -zv 192.168.1.25 22

# Or telnet
telnet 192.168.1.25 22
```

---

### Wrong Password

**Current Pi-hole Credentials:**
- Username: `admin`
- Password: `Admin123`

⚠️ **Note:** These need to be changed as per [SECURITY-UPDATE.md](SECURITY-UPDATE.md)

---

## What SSH Key Setup Does

1. **Copies your public key** to the remote server's `~/.ssh/authorized_keys`
2. **Enables passwordless login** for the user
3. **More secure** than password authentication
4. **Required for Ansible** to run without interactive passwords

---

## After Setup - What You Can Do

### 1. Run Ansible Playbooks

```bash
# Update Pi-hole servers
ansible-playbook ansible/playbooks/infrastructure/update-pihole.yml

# Or use the convenience script
./scripts/update-pihole.sh

# Update cluster
ansible-playbook ansible/playbooks/update-cluster.yml

# Update DNS entries
ansible-playbook ansible/playbooks/infrastructure/update-pihole-dns.yml
```

### 2. Quick SSH Access

```bash
# No more passwords needed!
ssh admin@192.168.1.25
ssh admin@192.168.1.26

# With SSH config shortcuts
ssh rpi-vpn-1
ssh pihole-primary
```

### 3. Run Commands on Multiple Hosts

```bash
# Check Pi-hole version on both servers
ansible pihole -m shell -a "pihole -v"

# Update gravity on both
ansible pihole -m shell -a "pihole -g" -b

# Check uptime on all cluster nodes
ansible cluster -m shell -a "uptime"
```

---

## Security Best Practices

### After SSH Key Setup

1. **Disable password authentication** (optional, more secure):
   ```bash
   ssh admin@192.168.1.25
   sudo nano /etc/ssh/sshd_config
   # Set: PasswordAuthentication no
   sudo systemctl restart sshd
   ```

2. **Protect your private key:**
   ```bash
   chmod 600 ~/.ssh/pi_cluster
   ```

3. **Backup your key:**
   ```bash
   cp ~/.ssh/pi_cluster ~/.ssh/pi_cluster.backup
   cp ~/.ssh/pi_cluster.pub ~/.ssh/pi_cluster.pub.backup
   ```

---

## Current Infrastructure Status

### ✅ SSH Keys Configured
- pi-master (192.168.1.240)
- pi-worker-01 (192.168.1.241)
- pi-worker-02 (192.168.1.242)
- pi-worker-03 (192.168.1.243)
- pi-worker-04 (192.168.1.244)
- pi-worker-05 (192.168.1.245)
- pi-worker-06 (192.168.1.246)
- pi-worker-07 (192.168.1.247)

### ⏳ Pending SSH Key Setup
- rpi-vpn-1 (192.168.1.25) - Pi-hole Primary
- rpi-vpn-2 (192.168.1.26) - Pi-hole Secondary

---

## Quick Commands Reference

```bash
# Setup SSH keys for Pi-hole servers
ssh-copy-id -i ~/.ssh/pi_cluster.pub admin@192.168.1.25
ssh-copy-id -i ~/.ssh/pi_cluster.pub admin@192.168.1.26

# Test connectivity
./scripts/setup-ssh-keys.sh --test

# Update SSH config
./scripts/setup-ssh-keys.sh --update-config

# Test with Ansible
ansible pihole -m ping

# Run Pi-hole update
./scripts/update-pihole.sh --status
```

---

**Last Updated:** October 21, 2025
**Key Location:** `~/.ssh/pi_cluster`
**Public Key:** `~/.ssh/pi_cluster.pub`
