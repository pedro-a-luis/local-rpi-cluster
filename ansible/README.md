# Ansible Automation for Pi K3s Cluster

Complete Ansible automation for the Raspberry Pi K3s cluster, including both cluster-level operations and infrastructure management.

## Directory Structure

```
ansible/
├── README.md                    # This file
├── ansible.cfg                  # Ansible configuration
├── requirements.txt             # Python dependencies
├── inventory/
│   └── hosts.yml                # Node inventory (master + 7 workers + 2 Pi-hole servers)
├── group_vars/                  # Group variables
├── vars/                        # Additional variables
├── roles/                       # Ansible roles (5 total)
│   ├── backup/                  # Backup automation
│   ├── base/                    # Base system configuration
│   ├── k3s/                     # K3s installation and config
│   ├── k3s_storage/             # Storage configuration
│   └── nfs/                     # NFS client setup
└── playbooks/                   # All playbooks (22 total)
    ├── infrastructure/          # Infrastructure playbooks (5)
    │   ├── README.md
    │   ├── update-pihole.yml
    │   ├── update-pihole-dns.yml
    │   ├── backup-pihole.yml
    │   ├── update-certificates.yml
    │   └── update-ingress.yml
    └── (17 cluster playbooks)   # K3s cluster management
```

## Two Types of Playbooks

### 1. Infrastructure Playbooks (`playbooks/infrastructure/`)

**Purpose**: Pi-hole DNS, SSL certificates, and ingress configuration
**Run from**: Anywhere with kubectl and SSH access to infrastructure servers

```bash
# Pi-hole management
ansible-playbook playbooks/infrastructure/update-pihole.yml
ansible-playbook playbooks/infrastructure/update-pihole-dns.yml
ansible-playbook playbooks/infrastructure/backup-pihole.yml

# Kubernetes infrastructure
ansible-playbook playbooks/infrastructure/update-certificates.yml
ansible-playbook playbooks/infrastructure/update-ingress.yml
```

### 2. Cluster Playbooks (`playbooks/*.yml`)

**Purpose**: K3s cluster installation and management
**Run from**: pi-master at `/home/admin/ansible/`

```bash
ssh -i ~/.ssh/pi_cluster admin@192.168.1.240
cd /home/admin/ansible
ansible-playbook playbooks/complete-k3s-install.yml
```

## Quick Reference - Cluster Playbooks

### Installation (3 playbooks)
- `complete-k3s-install.yml` (15KB) - Complete cluster setup
- `k3s-prep-nodes.yml` (6.3KB) - Prepare nodes
- `k3s-install.yml` (5.5KB) - Install K3s only

### Applications (4 playbooks)
- `k3s-install-apps.yml` (13KB) - Deploy all apps
- `k3s-remove-apps.yml` (13KB) - Remove apps
- `longhorn-install.yml` (5.9KB) - Storage
- `monitoring-install.yml` (6.9KB) - Monitoring

### Monitoring (2 playbooks)
- `k3s-app-status.yml` (4.8KB) - Check status
- `k3s-verify.yml` (6.1KB) - Verify health

### Maintenance (4 playbooks)
- `update-cluster.yml` (8.8KB) - Update nodes
- `k3s-networking-fix.yml` (7.4KB) - Fix networking
- `k3s-port-forward.yml` (3.5KB) - Port forwarding
- `k3s-force-delete-namespace.yml` (6.3KB) - Force delete

### Cleanup (2 playbooks)
- `complete-cleanup.yml` (8.5KB) - ⚠️ Full teardown
- `k3s-cleanup.yml` (3.8KB) - Partial cleanup

### Testing (1 playbook)
- `security.yml` (480B) - Security checks

## Common Workflows

### Initial Setup
```bash
# 1. On pi-master - Install cluster
ssh -i ~/.ssh/pi_cluster admin@192.168.1.240
cd /home/admin/ansible
ansible-playbook playbooks/complete-k3s-install.yml

# 2. From local - Configure infrastructure
cd ~/gitlab/local-rpi-cluster/ansible
ansible-playbook playbooks/infrastructure/update-certificates.yml
ansible-playbook playbooks/infrastructure/update-ingress.yml
```

### Regular Maintenance
```bash
# Every 90 days - Update certificates
ansible-playbook playbooks/infrastructure/update-certificates.yml

# Monthly - Update cluster nodes
ssh admin@192.168.1.240
cd /home/admin/ansible
ansible-playbook playbooks/update-cluster.yml

# Daily - Check status
ansible-playbook playbooks/k3s-app-status.yml
```

### Troubleshooting
```bash
# Check health
ansible-playbook playbooks/k3s-verify.yml

# Fix networking
ansible-playbook playbooks/k3s-networking-fix.yml

# Force delete namespace
ansible-playbook playbooks/k3s-force-delete-namespace.yml
```

## Inventory

**Master**: pi-master (192.168.1.240)
**Workers**: pi-worker-01 through 07 (192.168.1.241-247)
**User**: admin
**Python**: /usr/bin/python3

## Roles

- **base** - System configuration
- **k3s** - K3s installation
- **k3s_storage** - Longhorn + NFS
- **nfs** - NFS client
- **backup** - Backup automation

## Notes

- This is a **copy** for version control
- **Active cluster playbooks**: `/home/admin/ansible/` on pi-master
- **Infrastructure playbooks**: Can run from anywhere
- Keep both locations in sync

## See Also

- [playbooks/infrastructure/README.md](playbooks/infrastructure/README.md) - Infrastructure details
- [../ANSIBLE.md](../ANSIBLE.md) - Complete documentation
- [../README.md](../README.md) - Repository overview
