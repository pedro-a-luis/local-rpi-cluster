# Raspberry Pi K3s Cluster - Project Status

**Last Updated**: October 21, 2025
**Cluster Version**: K3s v1.32.2+k3s1
**Overall Status**: ✅ **HEALTHY** - All critical services operational

---

## Quick Stats

| Metric | Value | Status |
|--------|-------|--------|
| **Nodes** | 8 (1 master + 7 workers) | ✅ All Ready |
| **Running Pods** | 116 | ✅ Healthy |
| **Failed Pods** | 0 | ✅ None |
| **Namespaces** | 19 | ✅ Active |
| **Services** | 8 exposed via ingress | ✅ All accessible |
| **Storage (Longhorn)** | ~721Gi allocated | ✅ Available |
| **Storage (NFS)** | 1000Gi allocated | ✅ Available |
| **Cluster Uptime** | 150 days | ✅ Stable |

---

## Infrastructure Overview

### Hardware
- **8x Raspberry Pi 5** (8GB RAM, 256GB NVMe each)
- **2x Raspberry Pi 3** (Pi-hole DNS servers)
- **Synology DS723+** (Certificates, 2TB NVMe)
- **Synology DS118** (NFS storage, 7.3TB)

### Network
- **Domain**: `*.stratdata.org` (Let's Encrypt wildcard cert)
- **DNS**: Pi-hole HA pair (192.168.1.25, 192.168.1.26)
- **Master**: pi-master (192.168.1.240)
- **Workers**: pi-worker-01 to 07 (192.168.1.241-247)

---

## Deployed Services

### Core Infrastructure
| Service | Namespace | Version | Status | URL |
|---------|-----------|---------|--------|-----|
| **K3s** | kube-system | v1.32.2+k3s1 | ✅ Running | - |
| **Traefik** | traefik | Latest | ✅ Running | Ingress controller |
| **Longhorn** | longhorn-system | v1.10.0 | ✅ Running | https://longhorn.stratdata.org |
| **Cert-Manager** | cert-manager | Latest | ✅ Running | - |
| **NFS Provisioner** | nfs-provisioner | Latest | ✅ Running | - |

### Monitoring & Logging
| Service | Namespace | Status | URL | Credentials |
|---------|-----------|--------|-----|-------------|
| **Grafana** | monitoring | ✅ Running (3/3) | https://grafana.stratdata.org | admin/Grafana123 |
| **Prometheus** | monitoring | ✅ Running (2/2) | - | - |
| **Alertmanager** | monitoring | ✅ Running (2/2) | - | - |
| **Loki** | logging | ✅ Running (1/1) | https://loki.stratdata.org | - |
| **Promtail** | logging | ✅ Running (8/8 DaemonSet) | - | - |

### Databases
| Service | Namespace | Type | Status | Purpose |
|---------|-----------|------|--------|---------|
| **PostgreSQL** | databases | PostgreSQL 16 | ✅ Running (1/1) | Shared application database |
| **Airflow PostgreSQL** | airflow | PostgreSQL 16 | ✅ Running (1/1) | Dedicated Airflow metadata |
| **Redis** | redis | Redis 7 | ✅ Running (1/1) | Message broker & caching |

### Applications
| Service | Namespace | Status | URL | Credentials |
|---------|-----------|--------|-----|-------------|
| **Apache Airflow** | airflow | ✅ Running (7/7) | https://airflow.stratdata.org | admin/admin123 |
| **Celery Workers** | financial-screener | ✅ Running (7/7 DaemonSet) | - | - |
| **Flower** | financial-screener | ✅ Running (1/1) | - | - |
| **Celery (standalone)** | celery | ✅ Running (4/4) | - | - |
| **Flower (standalone)** | celery | ✅ Running (1/1) | https://flower.stratdata.org | admin/flower123 |
| **Code Server** | dev-tools | ✅ Running (1/1) | https://code.stratdata.org | - |

### Backup & Disaster Recovery
| Service | Namespace | Status | Purpose |
|---------|-----------|--------|---------|
| **Velero** | velero | ✅ Running (1/1) | Kubernetes backup & restore |
| **Node Agent** | velero | ✅ Running (8/8 DaemonSet) | Volume snapshots |
| **MinIO** | velero | ✅ Running (1/1) | S3-compatible backup storage |
| **MinIO Console** | velero | ✅ Running | https://minio-console.stratdata.org |

---

## Storage Summary

### Persistent Volumes (Total: ~721Gi Longhorn + 1000Gi NFS)

| Namespace | Purpose | Size | Storage Class |
|-----------|---------|------|---------------|
| airflow | PostgreSQL data | 8Gi | longhorn |
| airflow | Scheduler logs | 100Gi | longhorn |
| airflow | Triggerer logs | 100Gi | longhorn |
| databases | PostgreSQL primary | 20Gi | longhorn |
| databases | PostgreSQL read replica | 20Gi | longhorn |
| dev-tools | Code Server workspace | 30Gi | longhorn |
| logging | Loki storage | 10Gi | longhorn |
| monitoring | Grafana data | 5Gi | longhorn |
| monitoring | Prometheus data | 10Gi | longhorn |
| monitoring | Alertmanager data | 5Gi | longhorn |
| redis | Redis persistence | 5Gi | longhorn |
| velero | MinIO S3 storage | 500Gi | nfs-client |
| velero | Velero backups | 500Gi | nfs-client |

**Longhorn Total**: ~313Gi allocated
**NFS Total**: 1000Gi allocated
**Total Cluster Storage**: ~1.3TiB

---

## Resource Usage

### Node Resource Summary (Latest)
| Node | CPU Usage | CPU % | Memory Usage | Memory % |
|------|-----------|-------|--------------|----------|
| pi-master | 472m | 11% | 4277Mi | 53% |
| pi-worker-01 | 136m | 3% | 2547Mi | 31% |
| pi-worker-02 | 136m | 3% | 1890Mi | 23% |
| pi-worker-03 | 607m | 15% | 3250Mi | 40% |
| pi-worker-04 | 139m | 3% | 2410Mi | 29% |
| pi-worker-05 | 158m | 3% | 2684Mi | 33% |
| pi-worker-06 | 136m | 3% | 2174Mi | 26% |
| pi-worker-07 | 202m | 5% | 2481Mi | 30% |

**Total Cluster**: ~2GB CPU / ~20GB RAM utilized
**Efficiency**: Good distribution, no hotspots

---

## Recent Fixes Applied (October 20-21, 2025)

### Session: Cluster Error Resolution ✅

**Issues Fixed:**
1. ✅ **Airflow** - Database migrations not run → Created migration job, all pods now running
2. ✅ **Financial-screener Celery Worker** - Redis connection failure → Deleted and recreated pod
3. ✅ **Financial-screener Flower** - CrashLoopBackOff (env var conflict) → Disabled service links
4. ✅ **Celery Flower** - Same service link issue → Disabled service links
5. ✅ **Logging Promtail** - Containerd sandbox error on pi-worker-02 → Deleted and recreated
6. ✅ **Longhorn pods** - 3 pods with sandbox errors on pi-worker-02 → Deleted and recreated
7. ✅ **Velero node-agent** - Sandbox error on pi-worker-02 → Deleted and recreated
8. ✅ **Airflow Ingress** - Created and configured with TLS
9. ✅ **Pi-hole DNS** - airflow.stratdata.org entry verified (already existed)
10. ✅ **Database Cleanup** - Dropped orphaned airflow database from shared PostgreSQL

**Result**: **Zero pods in error state** - All services healthy

---

## DNS Configuration

### Pi-hole DNS Records
All `*.stratdata.org` domains resolve to `192.168.1.240` (cluster master):

- grafana.stratdata.org
- longhorn.stratdata.org
- code.stratdata.org
- prometheus.stratdata.org
- loki.stratdata.org
- traefik.stratdata.org
- **airflow.stratdata.org** ✅
- **flower.stratdata.org** (celery namespace)

**Pi-hole Servers**:
- Primary: 192.168.1.25 (rpi-vpn-1)
- Secondary: 192.168.1.26 (rpi-vpn-2)
- Credentials: admin/Admin123

---

## Security Status

### ✅ Good Practices
- Let's Encrypt wildcard certificate for `*.stratdata.org`
- TLS/HTTPS for all exposed services
- Separate namespaces for isolation
- RBAC enabled on K3s
- Network policies (partial)
- Dedicated service accounts

### ⚠️ Known Security Issues (from October 6 audit)

**CRITICAL** (requires immediate action):
1. 🔴 Hardcoded credentials in Ansible playbooks (Git history)
2. 🔴 Previous self-signed certificates (now replaced with Let's Encrypt)
3. 🔴 No secrets encryption at rest
4. 🔴 Missing RBAC policies for some namespaces
5. 🔴 No network policies for pod-to-pod communication

**HIGH**:
- Exposed Kubernetes Dashboard without authentication
- Default service account tokens auto-mounted
- No Pod Security Standards enforced
- Missing audit logging
- No runtime security monitoring (Falco)

**See**: [docs/security/audit.md](docs/security/audit.md) for full audit report
**See**: [docs/security/remediation.md](docs/security/remediation.md) for remediation steps

---

## Backup Strategy

### Automated Backups

**Velero Schedules**:
- **Daily**: All namespaces (except kube-system) at 2:00 AM - 30 days retention
- **Weekly**: Full cluster backup (including kube-system) - Sunday 2:00 AM - 90 days retention
- **On-demand**: Manual backups via CLI

**etcd Snapshots**:
- **Frequency**: Every 6 hours
- **Retention**: 48 snapshots (12 days)
- **Location**: `/var/lib/rancher/k3s/server/db/snapshots/`

**Storage Backend**:
- MinIO S3 bucket `velero-backups` on NFS (Synology DS118)
- 500Gi allocated

**See**: [docs/operations/backup-recovery.md](docs/operations/backup-recovery.md)

---

## Database Status

### Shared PostgreSQL (databases namespace)
- **Version**: PostgreSQL 16.10 on aarch64
- **Active Databases**:
  - `appdb` - Financial screener application (financial_screener schema with 19 tables)
  - `postgres` - Default system database
- **Removed**: ~~airflow~~ (orphaned, dropped during cleanup)
- **Connection**: `postgresql://appuser:AppUser123@postgresql-primary.databases:5432/appdb`

### Airflow PostgreSQL (airflow namespace)
- **Version**: PostgreSQL 16 Alpine
- **Database**: postgres (Airflow metadata)
- **Connection**: `postgresql://postgres:postgres@airflow-postgresql.airflow:5432/postgres`
- **Storage**: 8Gi Longhorn PVC

---

## Known Limitations

1. **No GitOps** - Manual kubectl/helm deployments (consider ArgoCD/Flux)
2. **Limited monitoring alerts** - Alertmanager configured but minimal rules
3. **No service mesh** - Consider Istio/Linkerd for advanced traffic management
4. **Manual certificate rotation** - Automated via Synology but manual sync to cluster
5. **No disaster recovery testing** - Backups exist but not regularly tested
6. **Pi-hole Ansible access** - SSH keys not configured in WSL environment

---

## Documentation Structure

```
docs/
├── README.md                          # Documentation index
├── getting-started/
│   ├── cluster-access-guide.md       # Service URLs and credentials
│   └── dns-setup-guide.md            # Pi-hole DNS configuration
├── deployment/
│   ├── airflow.md                    # Airflow deployment guide
│   ├── celery.md                     # Celery & Redis deployment
│   └── postgresql.md                 # PostgreSQL ARM64 deployment
├── operations/
│   ├── ansible-guide.md              # Ansible automation guide
│   ├── backup-recovery.md            # Backup & disaster recovery
│   └── cluster-lifecycle.md          # Shutdown/startup procedures
├── security/
│   ├── audit.md                      # Security audit (Oct 6, 2025)
│   └── remediation.md                # Security remediation guide
├── development/
│   └── claude-guidelines.md          # Development guidelines
└── roadmap/
    └── improvements.md               # Infrastructure improvements tracker
```

### Root Documentation Files (to be consolidated)
- `AIRFLOW-DEPLOYMENT-ANALYSIS.md` → Move to session-notes/
- `CELERY-DEPLOYMENT-CHANGES.md` → Move to session-notes/
- `CELERY-REDIS-QUICKSTART.md` → Merge into docs/deployment/celery.md
- `FIXES-APPLIED.md` → Move to session-notes/
- `INFRASTRUCTURE-ANALYSIS.md` → Move to session-notes/
- `SESSION-SUMMARY-AIRFLOW-DEPLOYMENT.md` → Move to session-notes/
- `WSL-SETUP.md` → Move to docs/getting-started/

---

## Next Steps / Recommendations

### Immediate (This Week)
1. **Security**: Address critical security findings from audit
   - Rotate exposed credentials
   - Implement Ansible Vault
   - Enable Pod Security Standards
2. **Documentation**: Consolidate root-level docs into session-notes/
3. **Testing**: Perform disaster recovery test (restore from Velero backup)

### Short-term (This Month)
1. **Monitoring**: Expand Alertmanager rules for critical services
2. **GitOps**: Evaluate ArgoCD for declarative deployments
3. **Automation**: Fix Pi-hole Ansible access (SSH keys)
4. **Storage**: Configure Longhorn backup target to NFS

### Long-term (Next Quarter)
1. **Service Mesh**: Evaluate Istio/Linkerd for observability
2. **CI/CD**: Deploy Tekton or Jenkins for pipeline automation
3. **Multi-tenancy**: Implement resource quotas and limit ranges
4. **Observability**: Deploy Jaeger for distributed tracing

---

## Maintenance Schedule

### Automated
- **Daily 2:00 AM**: Velero incremental backups
- **Sunday 2:00 AM**: Velero full cluster backups
- **Every 6 hours**: K3s etcd snapshots
- **Every 15 minutes**: Pi-hole config sync (primary → secondary)

### Manual
- **Weekly**: Review Grafana dashboards and alerts
- **Monthly**: Check Longhorn storage usage and health
- **Quarterly (90 days)**:
  - Let's Encrypt certificate auto-renewal on Synology
  - Run: `ansible-playbook ansible/playbooks/infrastructure/update-certificates.yml`
- **As needed**: Cluster node updates via Ansible

---

## Support & References

### Access Points
- **Grafana**: https://grafana.stratdata.org (admin/Grafana123)
- **Longhorn**: https://longhorn.stratdata.org
- **Airflow**: https://airflow.stratdata.org (admin/admin123)
- **Code Server**: https://code.stratdata.org
- **MinIO Console**: https://minio-console.stratdata.org
- **Pi-hole**: http://192.168.1.25/admin (admin/Admin123)

### Key Documentation
- [Complete Documentation Index](docs/README.md)
- [Cluster Access Guide](docs/getting-started/cluster-access-guide.md)
- [Ansible Guide](docs/operations/ansible-guide.md)
- [Backup & Recovery](docs/operations/backup-recovery.md)
- [Security Audit](docs/security/audit.md)

### Troubleshooting
1. Check cluster status: `kubectl get nodes && kubectl get pods -A`
2. Review logs: Grafana → Explore → Loki
3. Check metrics: Grafana dashboards
4. Ansible playbooks: `/home/admin/ansible/` on pi-master
5. This documentation: `/root/gitlab/local-rpi-cluster/docs/`

---

**Maintained By**: Infrastructure Team
**Last Reviewed**: October 21, 2025
**Next Review**: November 21, 2025
