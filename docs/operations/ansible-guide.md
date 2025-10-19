# Ansible Management - Pi K3s Cluster

This document describes the Ansible automation for the Raspberry Pi K3s cluster, covering both cluster-level operations and infrastructure management.

## Architecture Overview

The cluster uses **two separate Ansible environments**:

### 1. Cluster-Level Ansible (On Pi Master)

**Location**: `/home/admin/ansible/` on pi-master (192.168.1.240)

**Purpose**: Cluster deployment, configuration, and application management

**Access**:
```bash
ssh -i ~/.ssh/pi_cluster admin@192.168.1.240
cd /home/admin/ansible
```

### 2. Infrastructure Ansible (This Repository)

**Location**: `./playbooks/` in this repository

**Purpose**: DNS, certificates, and ingress management for external services

**Access**:
```bash
cd ~/gitlab/local-rpi-cluster
ansible-playbook playbooks/update-certificates.yml
```

---

## Cluster-Level Ansible

Manages K3s cluster installation, node configuration, and application deployment.

### Inventory

**File**: `/home/admin/ansible/inventory/hosts.yml`

**Nodes**:
- **Master**: pi-master (192.168.1.240)
- **Workers**: pi-worker-01 through pi-worker-07 (192.168.1.241-247)

**Connection**:
- User: `admin`
- Python: `/usr/bin/python3`

### Available Playbooks

#### Installation & Setup

**`complete-k3s-install.yml`** - Complete cluster setup
```bash
ansible-playbook playbooks/complete-k3s-install.yml
```
- Configures base system settings
- Sets up NFS mounts
- Installs K3s on all nodes
- Configures backup automation

**`k3s-prep-nodes.yml`** - Prepare nodes for K3s
```bash
ansible-playbook playbooks/k3s-prep-nodes.yml
```
- System updates
- Required packages
- Kernel parameters
- cgroup configuration

**`k3s-install.yml`** - Install K3s only
```bash
ansible-playbook playbooks/k3s-install.yml
```

#### Application Management

**`k3s-install-apps.yml`** - Deploy all applications
```bash
ansible-playbook playbooks/k3s-install-apps.yml
```
- Longhorn storage
- Traefik ingress
- Cert-manager
- Prometheus + Grafana
- Loki logging

**`k3s-remove-apps.yml`** - Remove applications
```bash
ansible-playbook playbooks/k3s-remove-apps.yml
```

**`k3s-deploy-all.yml`** - Deploy specific apps
```bash
ansible-playbook playbooks/k3s-deploy-all.yml
```

#### Monitoring & Verification

**`k3s-app-status.yml`** - Check application status
```bash
ansible-playbook playbooks/k3s-app-status.yml
```
- Shows all pods, services, ingresses
- Certificate status
- Storage status

**`k3s-verify.yml`** - Verify cluster health
```bash
ansible-playbook playbooks/k3s-verify.yml
```

#### Maintenance

**`update-cluster.yml`** - Update all cluster nodes
```bash
ansible-playbook playbooks/update-cluster.yml
```

**`k3s-networking-fix.yml`** - Fix networking issues
```bash
ansible-playbook playbooks/k3s-networking-fix.yml
```

**`k3s-port-forward.yml`** - Set up port forwarding
```bash
ansible-playbook playbooks/k3s-port-forward.yml
```

#### Cleanup

**`complete-cleanup.yml`** - Full cluster teardown
```bash
ansible-playbook playbooks/complete-cleanup.yml
```
⚠️ **WARNING**: Removes K3s, data, and all configurations

**`k3s-cleanup.yml`** - Partial cleanup
```bash
ansible-playbook playbooks/k3s-cleanup.yml
```

**`k3s-force-delete-namespace.yml`** - Force delete stuck namespace
```bash
ansible-playbook playbooks/k3s-force-delete-namespace.yml
```

#### Storage

**`longhorn-install.yml`** - Install Longhorn storage
```bash
ansible-playbook playbooks/longhorn-install.yml
```

**`test-nfs.yml`** - Test NFS connectivity
```bash
ansible-playbook playbooks/test-nfs.yml
```

#### Specialized

**`monitoring-install.yml`** - Install monitoring stack
```bash
ansible-playbook playbooks/monitoring-install.yml
```

**`nginx-ingress-install.yml`** - Install NGINX ingress (legacy)
```bash
ansible-playbook playbooks/nginx-ingress-install.yml
```

### Roles

Located in `/home/admin/ansible/roles/`:

- **base**: Base system configuration
- **k3s**: K3s installation and configuration
- **k3s_storage**: Storage configuration (Longhorn, NFS)
- **nfs**: NFS client setup
- **backup**: Backup automation

### Configuration Files

**`ansible.cfg`**:
```ini
[defaults]
inventory = ./inventory/hosts.yml
roles_path = ./roles
group_vars = ./group_vars
host_key_checking = False
retry_files_enabled = False
stdout_callback = yaml
```

**Group Variables**: `/home/admin/ansible/group_vars/`
**Host Variables**: `/home/admin/ansible/vars/`

---

## Infrastructure Ansible

Manages DNS, SSL certificates, and ingress configuration for external access.

### Available Playbooks

Located in `./playbooks/` in this repository:

#### 1. Update Certificates

**`update-certificates.yml`** - Sync Let's Encrypt from Synology
```bash
ansible-playbook playbooks/update-certificates.yml
```

**What it does**:
- Exports wildcard certificate from Synology DS723+
- Updates TLS secrets in monitoring, longhorn-system, dev-tools
- Verifies certificate expiry

**When to run**:
- After Let's Encrypt renewal (every 90 days)
- When adding new services requiring TLS

#### 2. Update DNS Zone

**`update-dns-zone.yml`** - Update DNS records
```bash
ansible-playbook playbooks/update-dns-zone.yml
```

**What it does**:
- Generates DNS zone file from template
- Deploys to Synology DS723+ DNS Server
- Restarts BIND
- Tests DNS resolution

**When to run**:
- Adding/removing services
- Changing cluster IP addresses

#### 3. Update Ingress

**`update-ingress.yml`** - Update K8s ingress routes
```bash
ansible-playbook playbooks/update-ingress.yml
```

**What it does**:
- Updates ingress host names
- Configures TLS settings
- Removes old cert-manager annotations
- Tests endpoints

**When to run**:
- Changing domain names
- Updating TLS configuration
- Adding new services

### Templates

**`templates/dns-zone.j2`** - BIND zone file template
```jinja2
$TTL 86400
@       IN      SOA     ns1.{{ zone_name }}. admin.{{ zone_name }}. (
                        {{ serial }} ; Serial
                        ...
```

---

## Common Workflows

### Initial Cluster Setup

1. Prepare nodes:
   ```bash
   ssh admin@192.168.1.240
   cd /home/admin/ansible
   ansible-playbook playbooks/k3s-prep-nodes.yml
   ```

2. Complete installation:
   ```bash
   ansible-playbook playbooks/complete-k3s-install.yml
   ```

3. Verify cluster:
   ```bash
   ansible-playbook playbooks/k3s-verify.yml
   kubectl get nodes
   ```

4. Configure DNS and certificates (from local machine):
   ```bash
   cd ~/gitlab/local-rpi-cluster
   ansible-playbook playbooks/update-dns-zone.yml
   ansible-playbook playbooks/update-certificates.yml
   ansible-playbook playbooks/update-ingress.yml
   ```

### Adding a New Service

1. Deploy application to cluster (on pi-master):
   ```bash
   kubectl apply -f new-service.yml
   ```

2. Add DNS record (from local):
   ```bash
   # Edit playbooks/update-dns-zone.yml
   # Add to dns_records list
   ansible-playbook playbooks/update-dns-zone.yml
   ```

3. Update ingress if needed:
   ```bash
   # Edit playbooks/update-ingress.yml
   # Add to ingress_routes list
   ansible-playbook playbooks/update-ingress.yml
   ```

### Certificate Renewal

**Automatic**: Synology auto-renews Let's Encrypt certificate

**Manual sync required**:
```bash
cd ~/gitlab/local-rpi-cluster
ansible-playbook playbooks/update-certificates.yml
```

### Cluster Updates

Update all nodes:
```bash
ssh admin@192.168.1.240
cd /home/admin/ansible
ansible-playbook playbooks/update-cluster.yml
```

### Troubleshooting

**Check application status**:
```bash
ssh admin@192.168.1.240
cd /home/admin/ansible
ansible-playbook playbooks/k3s-app-status.yml
```

**Fix networking issues**:
```bash
ansible-playbook playbooks/k3s-networking-fix.yml
```

**Force delete stuck namespace**:
```bash
ansible-playbook playbooks/k3s-force-delete-namespace.yml
```

---

## Best Practices

1. **Always run from correct location**:
   - Cluster operations: From pi-master `/home/admin/ansible`
   - Infrastructure operations: From this repo `./playbooks/`

2. **Test before production**:
   - Use `--check` mode for dry-runs
   - Verify with status playbooks before making changes

3. **Backup before major changes**:
   - Cluster has automated backups to Synology
   - Export kubeconfig before changes

4. **Use Git for infrastructure playbooks**:
   - Commit changes to this repository
   - Track modifications to DNS, certificates, ingress

5. **Document custom changes**:
   - Update playbook comments
   - Add to this documentation

---

## Environment Variables

**Infrastructure playbooks**:
```bash
export SYNOLOGY_PASSWORD='your-password'
```

**Cluster playbooks**:
Set in `/home/admin/ansible/group_vars/` or `/home/admin/ansible/vars/`

---

## See Also

- [cluster-access-guide.md](cluster-access-guide.md) - Access information
- [dns-setup-guide.md](dns-setup-guide.md) - DNS configuration details
- [playbooks/README.md](playbooks/README.md) - Infrastructure playbook documentation
- [claude.md](claude.md) - Development guidelines
