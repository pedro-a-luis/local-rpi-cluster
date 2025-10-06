# Claude Development Guidelines

## Core Development Philosophy

### KISS Principle (Keep It Simple, Stupid)
- **Simple > Complex**: Always choose the simplest solution that works
- **Explicit > Implicit**: Make code behavior obvious and transparent
- **Fast > Perfect**: Optimize for performance and maintainability over theoretical perfection
- **Measurable > Theoretical**: Focus on benchmarkable improvements

### YAGNI (You Aren't Gonna Need It)
- Don't build features until they are actually needed
- Remove unused code and functions regularly
- Focus on current requirements, not future possibilities
- Prefer editing existing files over creating new ones

### Design Principles
- **Single Responsibility**: Each function should have one clear purpose
- **Fail Fast**: Validate inputs early and provide clear error messages

---

## Project: Local RPI Cluster

This repository contains configuration and deployment scripts for the Raspberry Pi K3s cluster.

### Repository Structure

```
~/gitlab/local-rpi-cluster/
├── README.md                    # Repository overview and quick start
├── claude.md                    # This file - development guidelines
├── ANSIBLE.md                   # Complete Ansible documentation
├── cluster-access-guide.md      # Service access and credentials
├── dns-setup-guide.md           # DNS configuration instructions
├── cluster-init.sh              # Full cluster initialization script
├── monitor-deployment.sh        # Deployment monitoring script
└── ansible/                     # Complete Ansible automation (unified)
    ├── README.md                # Ansible overview and quick reference
    ├── ansible.cfg              # Ansible configuration
    ├── inventory/hosts.yml      # Master + 7 worker nodes
    ├── roles/                   # 5 Ansible roles (backup, base, k3s, storage, nfs)
    └── playbooks/               # All playbooks (24 total)
        ├── infrastructure/      # 3 infrastructure playbooks
        │   ├── update-certificates.yml
        │   ├── update-dns-zone.yml
        │   ├── update-ingress.yml
        │   └── templates/dns-zone.j2
        └── (21 cluster playbooks)  # K3s management

Note: Active cluster Ansible is at /home/admin/ansible/ on pi-master (192.168.1.240)
```

### Cluster Overview

**Hardware:**
- 8x Raspberry Pi 5 (8GB RAM each)
- 234GB NVMe storage per node
- Gigabit Ethernet networking

**Network:**
- Synology DS118 (192.168.1.10): NFS storage server
- Synology DS723 (192.168.1.20): DNS server
- Pi Cluster Master (192.168.1.240): K3s control plane
- Pi Workers (192.168.1.241-247): K3s worker nodes

**Services Deployed:**
- Longhorn: Distributed storage
- Traefik: Ingress controller
- Cert-Manager: SSL certificates
- Prometheus + Grafana: Monitoring
- Loki + Promtail: Logging
- NFS Provisioner: External storage

**Domain:** `*.stratdata.org`

### Key Credentials

See `cluster-access-guide.md` for full details.

### Development Notes

- Cluster managed via Ansible
  - Active cluster Ansible: `/home/admin/ansible/` on pi-master
  - Repository copy: `./ansible/` in this repo (unified structure)
  - Infrastructure playbooks: `./ansible/playbooks/infrastructure/`
- Prefer Ansible playbooks for cluster-wide changes
- Use `kubectl` for quick service management
- All services use Let's Encrypt wildcard certificate (*.stratdata.org)
- NFS storage available: 7.3TB from DS118 (192.168.1.10)
- Local storage available: 1.7TB distributed (Longhorn)
- DNS Server: Synology DS723+ (192.168.1.20)

### Quick Commands

```bash
# Monitor deployment
./monitor-deployment.sh

# Access cluster
ssh -i ~/.ssh/pi_cluster admin@192.168.1.240

# Check cluster status
kubectl get nodes
kubectl top nodes

# View services
kubectl get svc -A
kubectl get ing -A
```
