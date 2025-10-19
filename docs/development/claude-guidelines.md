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

---

## CRITICAL: New Application Deployment Pattern

**When deploying new applications to the cluster, ALWAYS follow this pattern:**

### 1. Create Ansible Playbook
Location: `ansible/playbooks/<app-name>-install.yml`

Example structure (follow existing patterns like `airflow-install.yml` or `celery-install.yml`):
```yaml
---
# Ansible Playbook: Install <App Name> in K3s Cluster
#
# Usage: ansible-playbook ansible/playbooks/<app>-install.yml
#
# Requirements:
#   - kubectl configured
#   - Helm installed (if using Helm charts)
#   - Longhorn storage class available

- name: Install <App Name> in K3s Cluster
  hosts: localhost
  gather_facts: no
  vars:
    app_namespace: "<app-name>"
    app_domain: "<app>.stratdata.org"
    tls_secret_name: "stratdata-wildcard-tls"

  tasks:
    - name: Create namespace
    - name: Copy TLS certificate (if web UI)
    - name: Deploy application (Helm or kubectl apply)
    - name: Create Ingress (if web UI)
    - name: Wait for deployment
    - name: Display installation summary
```

### 2. Create Deployment Script
Location: `scripts/deployment/deploy-<app-name>.sh`

**Purpose:** Quick deployment script that can be run on pi-master without Ansible

Example structure:
```bash
#!/bin/bash
# <App Name> Quick Deployment Script
# Run this on pi-master (192.168.1.240)

set -e

NAMESPACE="<app-name>"
DOMAIN="<app>.stratdata.org"

echo "========================================="
echo " <App Name> K3s Deployment"
echo "========================================="

# 1. Create namespace
# 2. Deploy resources (kubectl apply)
# 3. Create ingress (if needed)
# 4. Display status and next steps
```

### 3. Create Kubernetes Manifests (Optional)
Location: `kubernetes/<app-name>/<app-name>-deployment.yaml`

**Purpose:** Standalone manifests for reference or manual deployment

### 4. Create Documentation
Location: `docs/deployment/<app-name>.md`

**Must include:**
- Overview and architecture
- Prerequisites
- Deployment instructions (all 3 methods)
- Configuration options
- Verification steps
- Troubleshooting
- Scaling and monitoring
- Integration examples

### 5. Create Quick Start Guide (Optional)
Location: `<APP-NAME>-QUICKSTART.md` (root level for major apps)

**Purpose:** TL;DR deployment guide for quick reference

### 6. Update Main Documentation

**Update these files:**
1. `README.md`:
   - Add service to "Access Services" list
   - Add service to "Services" list
   - Add link to deployment guide

2. `docs/README.md`:
   - Add deployment guide to index

3. Infrastructure playbooks (if has web UI):
   - Add DNS entry to `ansible/playbooks/infrastructure/update-pihole-dns.yml`

### Deployment Methods Priority

**Always provide these 3 deployment methods (in order of preference):**

1. **Deployment Script** (Recommended for users)
   - Location: `scripts/deployment/deploy-<app>.sh`
   - Runs on pi-master with kubectl
   - No external dependencies
   - Built-in verification

2. **Ansible Playbook** (For automation)
   - Location: `ansible/playbooks/<app>-install.yml`
   - Runs from anywhere with ansible + kubectl
   - Idempotent and parameterized
   - Better for CI/CD

3. **Manual kubectl** (For troubleshooting)
   - Direct kubectl apply of manifests
   - Location: `kubernetes/<app>/`
   - Useful for debugging

### Example: Celery & Redis Deployment

**Files created:**
```
ansible/playbooks/
  ├── redis-install.yml          # Redis Ansible deployment
  └── celery-install.yml         # Celery Ansible deployment

scripts/deployment/
  ├── deploy-redis.sh            # Redis quick deploy
  └── deploy-celery.sh           # Celery quick deploy

kubernetes/
  ├── redis/redis-deployment.yaml    # Redis manifests
  └── celery/celery-deployment.yaml  # Celery manifests

docs/deployment/
  └── celery.md                  # Full deployment guide

CELERY-REDIS-QUICKSTART.md      # Quick start guide (root)

README.md                        # Updated with service info
```

### Namespace Guidelines

**Shared Services** (used by multiple apps):
- Use dedicated namespace: `redis`, `postgresql`, `minio`
- Examples: Redis (message broker), PostgreSQL (database)

**Application-Specific Services**:
- Use app namespace: `airflow`, `celery`, `grafana`
- Keep app components together

**Don't mix** application logic with shared infrastructure services

### Storage Guidelines

**Use Longhorn** for:
- Application data that needs persistence
- Database storage
- Application state

**Use NFS** for:
- Large file storage
- Shared data across many pods
- Backups

**Storage sizes:**
- Small apps: 1-5Gi
- Medium apps: 5-20Gi
- Large apps: 20-100Gi
- Check available: `kubectl get pvc -A`

### Ingress Guidelines

**Always:**
- Use `ingressClassName: nginx`
- Reference TLS secret: `stratdata-wildcard-tls`
- Copy TLS secret to app namespace from `monitoring` namespace
- Use domain pattern: `<app>.stratdata.org`

**Template:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <app>-ingress
  namespace: <app-namespace>
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - <app>.stratdata.org
    secretName: stratdata-wildcard-tls
  rules:
  - host: <app>.stratdata.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: <app-service>
            port:
              number: <port>
```

### DNS Guidelines

**After deploying app with web UI:**

1. Update Pi-hole DNS playbook:
   ```bash
   vim ansible/playbooks/infrastructure/update-pihole-dns.yml
   # Add to stratdata_services list:
   #   - { name: "<app>", ip: "192.168.1.240" }
   ```

2. Run DNS update:
   ```bash
   ansible-playbook ansible/playbooks/infrastructure/update-pihole-dns.yml
   ```

**Or manually:**
```bash
ssh admin@192.168.1.25
echo "192.168.1.240 <app>.stratdata.org" | sudo tee -a /etc/pihole/custom.list
sudo pihole restartdns
```

### Documentation Template

Every deployment guide must include:

1. **Overview** - What is it, why deployed
2. **Architecture** - Diagram of components
3. **Prerequisites** - Dependencies, requirements
4. **Deployment** - All 3 methods (script, ansible, manual)
5. **Configuration** - How to customize
6. **Verification** - How to test it works
7. **Monitoring** - Logs, metrics, dashboards
8. **Troubleshooting** - Common issues and solutions
9. **Scaling** - How to scale up/down
10. **Backup & Recovery** - How to backup/restore
11. **Security** - Credentials, hardening
12. **Maintenance** - Updates, cleanup
13. **Integration** - How other apps use it
14. **Uninstallation** - How to remove

### DON'T

❌ **Don't** create files without following the pattern
❌ **Don't** use only kubectl manifests without scripts/playbooks
❌ **Don't** forget to update README.md and docs
❌ **Don't** deploy without creating documentation
❌ **Don't** use hardcoded IPs (use service DNS names)
❌ **Don't** forget to add DNS entries for web UIs
❌ **Don't** mix shared services with app namespaces

### DO

✅ **Do** follow the 3-method deployment pattern
✅ **Do** create comprehensive documentation
✅ **Do** use existing patterns (check airflow-install.yml, celery-install.yml)
✅ **Do** test all deployment methods
✅ **Do** provide troubleshooting steps
✅ **Do** include verification commands
✅ **Do** update all documentation indexes

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
