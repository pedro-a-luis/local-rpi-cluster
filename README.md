# Raspberry Pi K3s Cluster

Infrastructure automation and documentation for an 8-node Raspberry Pi 5 Kubernetes (K3s) cluster.

**Status**: ✅ **HEALTHY** - 116 pods running, zero errors | [Full Status Report](PROJECT-STATUS.md)
**Security**: ⚠️ **ACTION REQUIRED** - Critical issues identified | [Security Update](SECURITY-UPDATE.md)
**Last Updated**: October 21, 2025

## Quick Status

- **Nodes**: 8/8 Ready (1 master + 7 workers)
- **Uptime**: 150 days
- **Services**: All operational and accessible
- **Recent Work**: Airflow deployed, cluster errors resolved, documentation updated

## Quick Start

**Access Services**:
- Grafana: https://grafana.stratdata.org (admin/Grafana123)
- Loki: https://loki.stratdata.org
- Longhorn: https://longhorn.stratdata.org
- Code Server: https://code.stratdata.org
- Airflow: https://airflow.stratdata.org (admin/admin123)
- Flower (Celery): https://flower.stratdata.org (admin/flower123)

**SSH Access**:
```bash
ssh -i ~/.ssh/pi_cluster admin@192.168.1.240
```

## Infrastructure

### Hardware
- **8x Raspberry Pi 5** (8GB RAM, 256GB NVMe each)
- **2x Raspberry Pi 3** (Pi-hole DNS servers)
- **Synology DS723+** (Certificates, 2TB NVMe storage)
- **Synology DS118** (NFS storage, 7.3TB)

### Network
- **DNS Servers**: rpi-vpn-1 (192.168.1.25), rpi-vpn-2 (192.168.1.26) - Pi-hole + WireGuard
- **Cluster Master**: pi-master (192.168.1.240)
- **Workers**: pi-worker-01 through 07 (192.168.1.241-247)
- **Domain**: `*.stratdata.org`

### Services
- **K3s**: Lightweight Kubernetes
- **Traefik**: Ingress controller
- **Longhorn**: Distributed storage (1.7TB)
- **Prometheus + Grafana**: Monitoring
- **Loki + Promtail**: Logging
- **Cert-Manager**: Certificate management
- **NFS Provisioner**: External storage (7.3TB)
- **Apache Airflow**: Workflow orchestration
- **Velero**: Kubernetes backup and disaster recovery
- **MinIO**: S3-compatible object storage (500GB)
- **PostgreSQL 16**: ARM64-compatible database
- **Redis**: Message broker and caching layer
- **Celery**: Distributed task queue with Flower monitoring

### Security
- Let's Encrypt wildcard certificate (`*.stratdata.org`)
- Trusted SSL/TLS (no browser warnings)
- WireGuard VPN for external access

## Documentation

### 📊 Status & Planning
- **[PROJECT-STATUS.md](PROJECT-STATUS.md)** - Comprehensive cluster status, metrics, and health report
- **[SECURITY-UPDATE.md](SECURITY-UPDATE.md)** - Security posture and critical action items
- **[Improvements Roadmap](docs/roadmap/improvements-updated.md)** - Infrastructure improvements and priorities

### 📚 Complete Documentation
**[Complete Documentation Index](docs/README.md)** - All documentation organized by category

### Getting Started
- **[Cluster Access Guide](docs/getting-started/cluster-access-guide.md)** - Service URLs, credentials, quick commands
- **[DNS Setup Guide](docs/getting-started/dns-setup-guide.md)** - DNS configuration and troubleshooting

### Deployment Guides
- **[Airflow Deployment](docs/deployment/airflow.md)** - Apache Airflow deployment and management
- **[PostgreSQL Deployment](docs/deployment/postgresql.md)** - PostgreSQL ARM64 deployment guide
- **[Celery & Redis Deployment](docs/deployment/celery.md)** - Distributed task queue deployment
- **[Celery Quick Start](CELERY-REDIS-QUICKSTART.md)** - Quick deployment guide for Celery and Redis

### Operations
- **[Ansible Guide](docs/operations/ansible-guide.md)** - Complete Ansible automation guide
  - Cluster-level operations (on pi-master)
  - Infrastructure operations (this repo)
  - Common workflows and troubleshooting
- **[Backup & Recovery](docs/operations/backup-recovery.md)** - Comprehensive backup and disaster recovery guide
- **[Cluster Lifecycle](docs/operations/cluster-lifecycle.md)** - Safe cluster shutdown and startup procedures

### Security
- **[Security Audit](docs/security/audit.md)** - Complete security assessment report
- **[Remediation Guide](docs/security/remediation.md)** - Step-by-step remediation guide

### Development
- **[Claude Guidelines](docs/development/claude-guidelines.md)** - Development guidelines and cluster overview

### Roadmap
- **[Improvements Roadmap](docs/roadmap/improvements.md)** - Infrastructure improvements tracker

### Automation
- **[Ansible README](ansible/README.md)** - Complete Ansible automation guide (24 playbooks, 5 roles)
- **[Infrastructure Playbooks](ansible/playbooks/infrastructure/README.md)** - Infrastructure playbook details
- **[Security Playbooks](ansible/playbooks/security/)** - Security hardening playbooks
- **[Scripts Directory](scripts/README.md)** - Cluster management and deployment scripts

## Common Tasks

### Update SSL Certificates

After Let's Encrypt renewal on Synology (automatic every 90 days):

```bash
ansible-playbook ansible/playbooks/infrastructure/update-certificates.yml
```

### Add a New Service

1. Deploy to cluster:
   ```bash
   kubectl apply -f your-service.yml
   ```

2. Add DNS record:
   ```bash
   # Edit ansible/playbooks/infrastructure/update-dns-zone.yml
   ansible-playbook ansible/playbooks/infrastructure/update-dns-zone.yml
   ```

3. Create ingress:
   ```bash
   kubectl apply -f your-ingress.yml
   ```

### Check Cluster Status

```bash
kubectl get nodes
kubectl get pods -A
kubectl get ingress -A
```

Or use Grafana: https://grafana.stratdata.org

### Update Cluster Nodes

```bash
ssh admin@192.168.1.240
cd /home/admin/ansible
ansible-playbook playbooks/update-cluster.yml
```

## Architecture

```
Internet (87.103.15.249)
    ↓
stratdata.org (Public DNS)
    ↓
Router (192.168.1.1)
    ↓
┌─────────────────────────────────────────┐
│ Local Network (192.168.1.0/24)          │
│                                          │
│  Pi-hole DNS Servers (Primary HA pair)  │
│  ├─ rpi-vpn-1 (192.168.1.25)            │
│  │   ├─ Pi-hole DNS + Ad-blocking       │
│  │   ├─ WireGuard VPN                   │
│  │   └─ Upstream: 8.8.8.8, 8.8.4.4      │
│  └─ rpi-vpn-2 (192.168.1.26)            │
│      ├─ Pi-hole DNS + Ad-blocking       │
│      ├─ WireGuard VPN                   │
│      ├─ Upstream: 8.8.8.8, 8.8.4.4      │
│      └─ Auto-sync from primary (15min)  │
│                                          │
│  Synology DS723+ (192.168.1.20)         │
│  ├─ NFS Storage (2TB NVMe)              │
│  └─ Let's Encrypt Cert (*.stratdata.org)│
│                                          │
│  Pi Cluster Master (192.168.1.240)      │
│  ├─ K3s Control Plane                   │
│  ├─ Traefik Ingress                     │
│  │   ├─ grafana.stratdata.org           │
│  │   ├─ longhorn.stratdata.org          │
│  │   ├─ code.stratdata.org              │
│  │   └─ airflow.stratdata.org           │
│  └─ Worker Nodes (192.168.1.241-247)    │
│                                          │
│  Synology DS118 (192.168.1.10)          │
│  └─ NFS Storage (7.3TB)                 │
└─────────────────────────────────────────┘
```

## Repository Structure

```
~/gitlab/local-rpi-cluster/
├── README.md                    # This file
├── .env                         # Environment variables (gitignored)
├── docs/                        # All documentation
│   ├── README.md                # Documentation index
│   ├── getting-started/         # Initial setup guides
│   │   ├── cluster-access-guide.md
│   │   └── dns-setup-guide.md
│   ├── deployment/              # Service deployment guides
│   │   ├── airflow.md
│   │   └── postgresql.md
│   ├── operations/              # Operational guides
│   │   ├── ansible-guide.md
│   │   ├── backup-recovery.md
│   │   └── cluster-lifecycle.md
│   ├── security/                # Security documentation
│   │   ├── audit.md
│   │   └── remediation.md
│   ├── development/             # Development guidelines
│   │   └── claude-guidelines.md
│   └── roadmap/                 # Planning documents
│       └── improvements.md
├── scripts/                     # Automation scripts
│   ├── README.md                # Scripts documentation
│   ├── cluster/                 # Cluster management
│   │   ├── init.sh
│   │   ├── shutdown.sh
│   │   └── startup.sh
│   └── deployment/              # Service deployment
│       ├── deploy-airflow.sh
│       └── monitor.sh
├── config/                      # Configuration files
│   ├── README.md                # Configuration guide
│   └── .env.example             # Environment template
├── ansible/                     # Complete Ansible automation
│   ├── README.md                # Ansible overview
│   ├── ansible.cfg              # Ansible configuration
│   ├── requirements.txt         # Python dependencies
│   ├── inventory/
│   │   └── hosts.yml            # Master + 7 worker nodes
│   ├── group_vars/              # Group variables
│   ├── vars/                    # Additional variables
│   ├── roles/                   # 5 Ansible roles
│   │   ├── backup/              # Backup automation
│   │   ├── base/                # Base system config
│   │   ├── k3s/                 # K3s installation
│   │   ├── k3s_storage/         # Storage configuration
│   │   └── nfs/                 # NFS client setup
│   └── playbooks/               # All playbooks (24 total)
│       ├── infrastructure/      # DNS, certs, ingress (3 playbooks)
│       │   ├── README.md
│       │   ├── update-certificates.yml
│       │   ├── update-dns-zone.yml
│       │   ├── update-ingress.yml
│       │   └── templates/dns-zone.j2
│       └── (21 cluster playbooks)  # K3s cluster management
└── docker/                      # Container definitions (if any)
```

**Notes**:
- **Infrastructure playbooks** (`ansible/playbooks/infrastructure/`) - Run from anywhere
- **Cluster playbooks** (`ansible/playbooks/*.yml`) - Run on pi-master
- **Scripts** - Bash automation for cluster lifecycle and deployments
- Active cluster Ansible lives at `/home/admin/ansible/` on pi-master (192.168.1.240)

## Troubleshooting

### Can't Access Services

1. **Configure DNS settings** (Required for local access):

   **Windows**: Control Panel → Network → Change adapter settings → vEthernet (VM Internet Access) → Properties → TCP/IPv4
   - **Preferred DNS**: 192.168.1.25
   - **Alternate DNS**: 192.168.1.26

   **Linux/Mac**: Edit `/etc/resolv.conf` or use NetworkManager:
   ```bash
   nmcli con mod "Your Connection" ipv4.dns "192.168.1.25 192.168.1.26"
   nmcli con up "Your Connection"
   ```

2. **Verify DNS resolution**:
   ```bash
   nslookup grafana.stratdata.org
   # Should return: 192.168.1.240 (from Pi-hole)
   ```

3. **Alternative: Use hosts file** (Windows: `C:\Windows\System32\drivers\etc\hosts`):
   ```
   192.168.1.240  grafana.stratdata.org
   192.168.1.240  longhorn.stratdata.org
   192.168.1.240  code.stratdata.org
   192.168.1.240  airflow.stratdata.org
   ```
   - Remove `#` at the start (makes them comments)
   - Flush DNS: `ipconfig /flushdns`

4. **Verify ingress**:
   ```bash
   kubectl get ingress -A
   curl -I https://192.168.1.240
   ```

### SSL Certificate Warnings

Should not happen with Let's Encrypt certificate. If you see warnings:

```bash
# Verify certificate
curl -vI https://grafana.stratdata.org 2>&1 | grep issuer
# Should show: issuer: C=US; O=Let's Encrypt; CN=E6

# If wrong, update certificates
ansible-playbook playbooks/update-certificates.yml
```

### Cluster Issues

```bash
# SSH to master
ssh -i ~/.ssh/pi_cluster admin@192.168.1.240

# Check nodes
kubectl get nodes

# Check pods
kubectl get pods -A

# Check logs
kubectl logs -n <namespace> <pod-name>

# Run cluster verification
cd /home/admin/ansible
ansible-playbook playbooks/k3s-app-status.yml
```

See [Ansible Guide](docs/operations/ansible-guide.md) for more troubleshooting playbooks.

## Maintenance Schedule

### Daily
- Automated backups to Synology DS118

### Weekly
- Monitor Grafana dashboards
- Check disk usage in Longhorn

### Monthly
- Review logs in Loki
- Check for security updates

### Quarterly (every 90 days)
- Let's Encrypt certificate auto-renews on Synology
- Run: `ansible-playbook playbooks/update-certificates.yml`

### As Needed
- Update cluster nodes: `ansible-playbook playbooks/update-cluster.yml`
- Add/remove services
- Scale cluster

## Support

For issues or questions:
1. Check [documentation index](docs/README.md)
2. Review logs in Grafana/Loki
3. Check cluster status playbooks
4. Consult [Ansible Guide](docs/operations/ansible-guide.md) for automation

## License

Internal infrastructure - not for public distribution.

---

**Last Updated**: October 2025
**Cluster Version**: K3s v1.x
**Maintained By**: Admin
