# Ansible Playbooks for Pi Cluster Management

This directory contains Ansible playbooks for managing the Raspberry Pi K3s cluster infrastructure.

## Prerequisites

```bash
# Install required tools
apt update
apt install -y ansible sshpass

# Verify kubectl is configured
kubectl get nodes
```

## Available Playbooks

### Pi-hole DNS Management

**DNS Configuration:**
- **Primary**: rpi-vpn-1 (192.168.1.25)
- **Secondary**: rpi-vpn-2 (192.168.1.26)
- **Upstream DNS**: 8.8.8.8, 8.8.4.4
- **Sync**: Automatic every 15 minutes (rsync-based)
- **HA Mode**: Both servers active, synchronized configuration

#### 1. Update Pi-hole Servers

Updates Pi-hole, OS packages, and WireGuard on both DNS servers.

```bash
ansible-playbook playbooks/infrastructure/update-pihole.yml
```

**What it does:**
- Updates Pi-hole software
- Upgrades OS packages (apt dist-upgrade)
- Updates WireGuard VPN
- Updates gravity database
- Reboots if required (one server at a time)
- Verifies DNS resolution after update

**When to run:**
- Monthly or when Pi-hole updates are available
- After major OS security updates

#### 2. Update Pi-hole DNS Records

Updates DNS entries for cluster services in dnsmasq.

```bash
ansible-playbook playbooks/infrastructure/update-pihole-dns.yml
```

**What it does:**
- Generates dnsmasq configuration for cluster services
- Updates `/etc/dnsmasq.d/99-stratdata-local.conf` on both servers
- Restarts Pi-hole DNS service
- Verifies DNS resolution

**When to run:**
- When adding/removing cluster services
- When changing cluster IP address

#### 3. Backup Pi-hole Configuration

Backs up Pi-hole, dnsmasq, and WireGuard configurations.

```bash
ansible-playbook playbooks/infrastructure/backup-pihole.yml
```

**What it does:**
- Backs up /etc/pihole/ configuration
- Backs up /etc/dnsmasq.d/ DNS records
- Backs up /etc/wireguard/ VPN configuration
- Creates Pi-hole teleporter export
- Downloads backups to local machine
- Cleans up old backups (keeps last 5)

**When to run:**
- Before major updates
- Weekly/monthly for disaster recovery
- Before configuration changes

#### 4. Setup Pi-hole Sync

Configures rsync-based synchronization between primary and secondary Pi-hole servers.

```bash
ansible-playbook playbooks/infrastructure/setup-pihole-rsync-sync.yml
```

**What it does:**
- Creates sync script on secondary server
- Syncs gravity database from primary
- Syncs custom DNS entries
- Configures cron job (every 15 minutes)
- Ensures high availability

**When to run:**
- Once during initial setup (already configured)
- After rebuilding Pi-hole servers

#### 5. Setup Pi-hole Monitoring

Installs and configures Pi-hole Prometheus exporters for Grafana monitoring.

```bash
ansible-playbook playbooks/infrastructure/setup-pihole-monitoring.yml
```

**What it does:**
- Installs pihole-exporter on both servers
- Creates systemd service
- Configures Prometheus ServiceMonitor
- Exposes metrics on port 9617

**When to run:**
- Once during initial setup
- When adding monitoring dashboards

### Kubernetes Infrastructure

#### 6. Update Certificates

Exports Let's Encrypt wildcard certificate from Synology and updates Kubernetes TLS secrets.

```bash
ansible-playbook playbooks/update-certificates.yml
```

**What it does:**
- Exports certificate and private key from Synology
- Displays certificate expiry date
- Updates TLS secrets in multiple namespaces
- Verifies secret creation

**Namespaces updated:**
- monitoring (Grafana)
- longhorn-system (Longhorn)
- dev-tools (Code Server)

**When to run:**
- After Let's Encrypt certificate renewal (every 90 days)
- When adding new services that need TLS

#### 7. Update Ingress Routes

Updates Kubernetes ingress routes to use correct domain and certificates.

```bash
ansible-playbook playbooks/update-ingress.yml
```

**What it does:**
- Updates ingress host names
- Configures TLS settings
- Removes old cert-manager annotations
- Tests endpoint availability

**Services updated:**
- Grafana (monitoring/kube-prometheus-grafana)
- Longhorn (longhorn-system/longhorn-ingress)
- Code Server (dev-tools/codeserver)

## Configuration

### Environment Variables

```bash
# Set Synology password (optional, defaults are in playbook)
export SYNOLOGY_PASSWORD='your-password'
```

### Custom Variables

Edit the playbook files directly or create a vars file:

```bash
ansible-playbook playbooks/update-certificates.yml -e "synology_password='custom-pass'"
```

## Running on Pi Cluster

These playbooks are designed to run from any machine with kubectl access to the cluster.

**From local machine:**
```bash
git clone <repo>
cd local-rpi-cluster
ansible-playbook playbooks/update-certificates.yml
```

**From cluster master:**
```bash
ssh -i ~/.ssh/pi_cluster admin@192.168.1.240
cd /path/to/repo
ansible-playbook playbooks/update-certificates.yml
```

## Troubleshooting

**Error: "sshpass: command not found"**
```bash
apt install -y sshpass
```

**Error: "kubectl: command not found"**
```bash
# Ensure kubectl is in PATH or use full path
export PATH=$PATH:/usr/local/bin
```

**Error: "Permission denied (publickey,password)"**
```bash
# Verify Synology credentials
export SYNOLOGY_PASSWORD='correct-password'
# Or update the playbook vars
```

**Certificate export fails:**
```bash
# Verify certificate exists on Synology
ssh synology-ds723@192.168.1.20 'sudo ls -la /usr/syno/etc/certificate/_archive/Yxt8vg/'
```

## Maintenance Schedule

**Weekly:**
- Run `backup-pihole.yml` for disaster recovery

**Monthly:**
- Run `update-pihole.yml` to update DNS servers
- Run `update-ingress.yml` if adding new services

**Every 90 days (before Let's Encrypt expiry):**
- Synology auto-renews Let's Encrypt certificate
- Run `update-certificates.yml` to sync to cluster

**As needed:**
- Run `update-pihole-dns.yml` when adding/removing cluster services
- Run `update-ingress.yml` when modifying ingress configuration
- Run `backup-pihole.yml` before major changes

## See Also

- [dns-setup-guide.md](../dns-setup-guide.md) - DNS configuration guide
- [cluster-access-guide.md](../cluster-access-guide.md) - Cluster access information
- [claude.md](../claude.md) - Development guidelines
