# Infrastructure Improvements Roadmap - Updated

**Last Updated**: October 21, 2025
**Previous Version**: October 6, 2025
**Cluster**: 8-node Raspberry Pi 5 K3s Cluster (v1.32.2+k3s1)
**Overall Status**: ✅ **OPERATIONAL** - Core services healthy, security improvements needed

---

## Current Status Overview

### ✅ Completed Phases
- **Phase 1**: Fix Broken Services (Grafana, Loki, PostgreSQL) ✅
- **Phase 2**: Critical Backup Infrastructure (Velero, MinIO, etcd) ✅
- **Phase 2.5**: Apache Airflow Deployment ✅
- **Phase 2.6**: Celery & Redis Distributed Task Queue ✅

### 🚧 In Progress
- **Phase 3**: Security Hardening (CRITICAL - see SECURITY-UPDATE.md)

### 📋 Planned
- **Phase 4**: Enhanced Monitoring & Observability
- **Phase 5**: GitOps Implementation
- **Phase 6**: Service Mesh
- **Phase 7**: CI/CD Pipeline

---

## ✅ Recently Completed (October 2025)

### Phase 2.5: Apache Airflow Deployment ✅ COMPLETED
**Completed**: October 20, 2025
**Status**: ✅ Fully Operational

#### Deployment Details
- **Version**: Apache Airflow 3.0.2
- **Executor**: KubernetesExecutor
- **Database**: Dedicated PostgreSQL 16 (8Gi Longhorn PVC)
- **Storage**:
  - Logs: 200Gi (100Gi scheduler + 100Gi triggerer)
  - DAGs: Persistent volume
- **Access**: https://airflow.stratdata.org
- **Credentials**: admin/admin123

#### Components Deployed
- ✅ Airflow Scheduler (2/2 replicas)
- ✅ Airflow API Server (1/1)
- ✅ Airflow DAG Processor (2/2)
- ✅ Airflow Triggerer (2/2)
- ✅ Airflow StatsD (1/1)
- ✅ Airflow PostgreSQL (1/1)
- ✅ Ingress with TLS (Traefik)
- ✅ DNS entry in Pi-hole

#### Fixes Applied
- Database migrations run successfully
- Ingress configured and accessible
- Pi-hole DNS entry verified

---

### Phase 2.6: Cluster Error Resolution ✅ COMPLETED
**Completed**: October 21, 2025
**Status**: ✅ Zero Error Pods

#### Issues Fixed
1. ✅ Airflow database migrations
2. ✅ Financial-screener Celery worker (Redis connection)
3. ✅ Financial-screener Flower (CrashLoopBackOff - env var conflict)
4. ✅ Celery namespace Flower (same issue)
5. ✅ Logging Promtail (containerd sandbox error)
6. ✅ Longhorn pods (3 pods with sandbox errors)
7. ✅ Velero node-agent (sandbox error)
8. ✅ Airflow ingress creation
9. ✅ Database cleanup (dropped orphaned airflow DB)

**Result**: All 116 pods running successfully, zero errors

---

## 🔴 CRITICAL - Phase 3: Security Hardening (URGENT)

**Priority**: 🔴 **CRITICAL**
**Timeline**: 2-4 weeks
**Effort**: High
**Status**: 🚧 **IN PROGRESS** - Immediate action required

### Overview
Security audit from October 6, 2025 identified critical vulnerabilities that must be addressed immediately. See [SECURITY-UPDATE.md](../../SECURITY-UPDATE.md) for complete details.

### Week 1 - CRITICAL (Immediate Action)
- [ ] **Rotate ALL exposed credentials**
  - [ ] Synology admin password (currently: `Xd9auP$W@eX3` - exposed in Git)
  - [ ] Pi-hole admin password (currently: `Admin123`)
  - [ ] PostgreSQL appuser password (currently: `AppUser123`)
  - [ ] Grafana admin password (currently: `Grafana123`)
  - [ ] Airflow admin password (currently: `admin123`)
  - [ ] Flower password (currently: `flower123`)

- [ ] **Implement Ansible Vault**
  - [ ] Create encrypted vault file: `ansible/vars/vault.yml`
  - [ ] Migrate all hardcoded credentials to vault
  - [ ] Update 17+ playbooks to use vault variables
  - [ ] Add vault.yml to .gitignore
  - [ ] Document vault usage procedures

- [ ] **Enable K3s Secrets Encryption**
  - [ ] Create encryption config file
  - [ ] Restart K3s with encryption enabled
  - [ ] Re-encrypt existing secrets
  - [ ] Verify encryption working

### Week 2-3 - HIGH Priority
- [ ] **Implement RBAC Policies**
  - [ ] Audit current service account permissions
  - [ ] Create least-privilege RBAC per namespace
  - [ ] Remove cluster-admin bindings where not needed
  - [ ] Document RBAC policies

- [ ] **Deploy Network Policies**
  - [ ] Implement default-deny policies per namespace
  - [ ] Create specific allow rules for required communication
  - [ ] Isolate sensitive namespaces (databases, monitoring)
  - [ ] Test pod-to-pod communication

- [ ] **Enable Pod Security Standards**
  - [ ] Apply baseline PSS to all namespaces
  - [ ] Apply restricted PSS to databases, monitoring
  - [ ] Fix non-compliant pods
  - [ ] Document PSS policies

- [ ] **Disable Auto-mount of Service Account Tokens**
  - [ ] Add `automountServiceAccountToken: false` to deployments
  - [ ] Manually mount only where needed
  - [ ] Test applications

### Month 1 - MEDIUM Priority
- [ ] **Enable K3s Audit Logging**
  - [ ] Configure audit policy
  - [ ] Ship logs to Loki
  - [ ] Create Grafana audit dashboard
  - [ ] Set up alerts for suspicious activity

- [ ] **Deploy Falco (Runtime Security)**
  - [ ] Install Falco via Helm
  - [ ] Configure Falcosidekick
  - [ ] Create alert rules
  - [ ] Integrate with Alertmanager

- [ ] **Implement Image Scanning**
  - [ ] Deploy Trivy for vulnerability scanning
  - [ ] Configure pre-deployment scanning
  - [ ] Create vulnerability reports
  - [ ] Set up auto-remediation

- [ ] **Configure Traefik Rate Limiting**
  - [ ] Add rate limit middleware
  - [ ] Apply to public ingresses
  - [ ] Test and tune limits

### Success Criteria
- ✅ All credentials rotated and in Ansible Vault
- ✅ Zero hardcoded credentials in Git
- ✅ Secrets encrypted at rest in etcd
- ✅ RBAC policies enforced per namespace
- ✅ Network policies limiting pod-to-pod communication
- ✅ Pod Security Standards applied
- ✅ Audit logging enabled and monitored
- ✅ Runtime security monitoring (Falco) operational
- ✅ All container images scanned for vulnerabilities

---

## 🟡 Phase 4: Enhanced Monitoring & Observability

**Priority**: 🟡 MEDIUM
**Timeline**: 2-3 weeks
**Effort**: Medium-High
**Status**: 📋 **PLANNED**

### 4.1 Thanos - Long-term Metrics Storage
**Status**: ❌ Not Deployed
**Why**: Prometheus retention limited to ~15 days

#### Features
- Unlimited metric retention (years of data)
- Query across multiple Prometheus instances
- Automatic downsampling
- Deduplication

#### Tasks
- [ ] Deploy Thanos sidecar to Prometheus
- [ ] Configure MinIO bucket for metrics storage
- [ ] Deploy Thanos Query
- [ ] Deploy Thanos Store Gateway
- [ ] Deploy Thanos Compactor
- [ ] Configure Grafana to use Thanos
- [ ] Test long-term queries

#### Resources
- Storage: 100Gi NFS (expandable)
- Memory: ~1GB total
- Retention: Raw 30d, 5m 90d, 1h 2yr

---

### 4.2 Tempo - Distributed Tracing
**Status**: ❌ Not Deployed
**Why**: No distributed tracing for microservices

#### Features
- End-to-end request tracing
- Native Grafana integration
- OpenTelemetry compatible
- Service dependency mapping

#### Tasks
- [ ] Configure MinIO bucket for traces
- [ ] Deploy Tempo
- [ ] Configure Grafana data source
- [ ] Instrument Airflow for tracing
- [ ] Instrument Celery workers
- [ ] Create trace visualization dashboards

#### Resources
- Storage: 50Gi NFS
- Memory: ~512MB

---

### 4.3 Expanded Alerting Rules
**Status**: ⚠️ Partial
**Current**: Basic infrastructure alerts only

#### Tasks
- [ ] Application-level alerts
  - [ ] Airflow DAG failures
  - [ ] Celery task failures
  - [ ] Database connection issues
  - [ ] PostgreSQL performance degradation
- [ ] Security alerts
  - [ ] Failed authentication attempts
  - [ ] Unusual API access patterns
  - [ ] Certificate expiration warnings
  - [ ] Policy violations
- [ ] Business metrics alerts
  - [ ] Data collection failures
  - [ ] Processing delays
  - [ ] API rate limit warnings

---

### 4.4 Custom Grafana Dashboards
**Status**: ⚠️ Partial

#### Tasks
- [ ] Airflow operations dashboard
- [ ] Celery task queue dashboard
- [ ] PostgreSQL performance dashboard
- [ ] Security monitoring dashboard
- [ ] Backup status dashboard
- [ ] Cost/resource optimization dashboard

---

## 🟢 Phase 5: GitOps Implementation

**Priority**: 🟢 MEDIUM
**Timeline**: 2-3 weeks
**Effort**: Medium
**Status**: 📋 **PLANNED**

### 5.1 ArgoCD Deployment
**Why**: Declarative GitOps, automated deployments, drift detection

#### Features
- Automated deployment from Git
- Drift detection and self-healing
- Rollback capabilities
- Multi-environment support
- Web UI for deployment visualization

#### Tasks
- [ ] Deploy ArgoCD
- [ ] Configure Git repository connection
- [ ] Create application manifests
- [ ] Migrate existing deployments to ArgoCD
  - [ ] Start with dev-tools namespace
  - [ ] Migrate monitoring
  - [ ] Migrate databases
  - [ ] Migrate applications
- [ ] Configure automated sync policies
- [ ] Set up Slack/email notifications
- [ ] Create ArgoCD access documentation

#### Resources
- Memory: ~500MB
- Storage: 5Gi
- Access: https://argocd.stratdata.org

---

### 5.2 Repository Structure Reorganization

#### Tasks
- [ ] Create dedicated GitOps repository or branch
- [ ] Organize manifests by environment/namespace
- [ ] Implement Kustomize overlays for environments
- [ ] Document GitOps workflow
- [ ] Set up branch protection and PR workflows

---

## 🟢 Phase 6: Service Mesh (Istio/Linkerd)

**Priority**: 🟢 LOW
**Timeline**: 3-4 weeks
**Effort**: High
**Status**: 📋 **FUTURE**

### Why Service Mesh?
- Mutual TLS between services
- Advanced traffic management
- Circuit breaking and retries
- Detailed observability
- A/B testing and canary deployments

### Evaluation Criteria
- **Istio**: Feature-rich, heavier resource usage (~500MB per node)
- **Linkerd**: Lightweight (~200MB per node), simpler
- **Recommendation**: Start with Linkerd for resource efficiency

### Tasks
- [ ] Evaluate Linkerd vs Istio
- [ ] Deploy service mesh control plane
- [ ] Inject sidecars to selected namespaces
- [ ] Configure mTLS policies
- [ ] Set up traffic management rules
- [ ] Integrate with Prometheus/Grafana
- [ ] Create service mesh dashboards
- [ ] Document service mesh usage

---

## 🟢 Phase 7: CI/CD Pipeline

**Priority**: 🟢 LOW
**Timeline**: 2-3 weeks
**Effort**: Medium-High
**Status**: 📋 **FUTURE**

### 7.1 Tekton or Jenkins Deployment
**Why**: Automated build, test, and deployment pipelines

#### Features
- Kubernetes-native CI/CD
- Pipeline as code
- Multi-arch builds (ARM64)
- Integration with ArgoCD

#### Tasks
- [ ] Evaluate Tekton vs Jenkins
- [ ] Deploy CI/CD platform
- [ ] Create sample pipeline
- [ ] Configure image registry
- [ ] Set up automated testing
- [ ] Integrate with GitOps (ArgoCD)
- [ ] Document pipeline usage

---

### 7.2 Container Registry
**Status**: ❌ Not Deployed
**Current**: Using Docker Hub, local images

#### Options
- Harbor (full-featured, image scanning)
- GitLab Container Registry
- Nexus Repository

#### Tasks
- [ ] Deploy container registry
- [ ] Configure TLS (https://registry.stratdata.org)
- [ ] Set up image scanning
- [ ] Configure retention policies
- [ ] Migrate existing images
- [ ] Update deployments to use private registry

---

## 🔵 Phase 8: Additional Enhancements

**Priority**: 🔵 NICE TO HAVE
**Status**: 📋 **BACKLOG**

### Infrastructure
- [ ] Multi-cluster federation (if expanding)
- [ ] External DNS automation
- [ ] Automated node provisioning
- [ ] Cluster autoscaling (if needed)
- [ ] Disaster recovery site (cloud backup)

### Applications
- [ ] Internal developer portal (Backstage)
- [ ] API Gateway (Kong, Ambassador)
- [ ] Service catalog
- [ ] Documentation platform (internal wiki)
- [ ] ChatOps integration (Slack bot for cluster ops)

### Data & ML
- [ ] JupyterHub for data science workloads
- [ ] MLflow for ML experiment tracking
- [ ] Kubeflow for ML pipelines
- [ ] Data lake (MinIO + Hive/Presto)

### Developer Experience
- [ ] Local development with Tilt or Skaffold
- [ ] Development namespaces per developer
- [ ] Automated test environments
- [ ] Pull request preview environments

---

## Completed Phases Summary

### ✅ Phase 1: Fix Broken Services (October 19, 2025)
- Grafana: Init:0/1 → Running 3/3
- Loki: Unknown → Running 1/1
- PostgreSQL: ImagePullBackOff → Running 1/1 (ARM64 image)

### ✅ Phase 2: Critical Backup Infrastructure (October 19, 2025)
- Velero v1.17.0 deployed
- MinIO S3 storage (500Gi NFS)
- Daily incremental backups (2 AM, 30 days)
- Weekly full backups (Sunday 2 AM, 90 days)
- etcd snapshots (every 6 hours, 48 snapshots)
- Node-agent on all 8 nodes
- Successful backup/restore testing

### ✅ Phase 2.5: Apache Airflow (October 20, 2025)
- Airflow 3.0.2 with KubernetesExecutor
- Dedicated PostgreSQL 16
- 208Gi storage (8Gi DB + 200Gi logs)
- Accessible at https://airflow.stratdata.org
- All 7 components running

### ✅ Phase 2.6: Cluster Error Resolution (October 21, 2025)
- Fixed 10+ pod errors across 6 namespaces
- Zero error pods remaining
- All services healthy and accessible
- Database cleanup completed

---

## Resource Planning

### Current Cluster Resources (8 nodes)
- **Total CPU**: 32 cores (4 cores × 8 nodes)
- **Total RAM**: 64GB (8GB × 8 nodes)
- **Total Storage**: 2TB NVMe (256GB × 8 nodes)
- **NFS Storage**: 7.3TB (Synology DS118)

### Current Usage
- **CPU**: ~2GB utilized (~6% cluster-wide)
- **RAM**: ~21GB utilized (~33% cluster-wide)
- **Longhorn**: ~313Gi / 1.7TB (~18%)
- **NFS**: ~1TB / 7.3TB (~14%)

### Remaining Capacity
- **CPU**: ~30GB available
- **RAM**: ~43GB available
- **Longhorn**: ~1.4TB available
- **NFS**: ~6.3TB available

**Assessment**: ✅ Significant headroom for planned phases

---

## Priority Order (Next 3 Months)

### Month 1 - November 2025
**Focus**: Security & Compliance
1. 🔴 Rotate all exposed credentials (Week 1)
2. 🔴 Implement Ansible Vault (Week 1)
3. 🔴 Enable secrets encryption (Week 1)
4. 🟠 RBAC policies (Week 2-3)
5. 🟠 Network policies (Week 2-3)
6. 🟠 Pod Security Standards (Week 3-4)

### Month 2 - December 2025
**Focus**: Advanced Security & Monitoring
1. 🟠 Enable audit logging (Week 1)
2. 🟠 Deploy Falco (Week 1-2)
3. 🟠 Implement image scanning (Week 2)
4. 🟡 Deploy Thanos (Week 3-4)
5. 🟡 Expand alerting rules (Week 3-4)

### Month 3 - January 2026
**Focus**: GitOps & Observability
1. 🟢 Deploy ArgoCD (Week 1-2)
2. 🟢 Migrate deployments to GitOps (Week 2-3)
3. 🟡 Deploy Tempo (Week 3)
4. 🟡 Create custom dashboards (Week 4)

---

## Success Metrics

### Security
- ✅ Zero hardcoded credentials in repository
- ✅ All secrets encrypted at rest
- ✅ RBAC policies on all namespaces
- ✅ Network policies enforced
- ✅ Pod Security Standards applied
- ✅ Runtime security monitoring active

### Reliability
- ✅ Zero error pods
- ✅ 99.9% service uptime
- ✅ Successful DR drill quarterly
- ✅ All backups completing successfully
- ✅ Mean time to recovery < 30 minutes

### Observability
- ✅ All services monitored
- ✅ Critical alerts configured
- ✅ Log retention > 90 days
- ✅ Metric retention > 1 year
- ✅ Distributed tracing operational

### Automation
- ✅ GitOps for all deployments
- ✅ Automated testing in CI/CD
- ✅ Self-healing via ArgoCD
- ✅ Automated certificate rotation

---

## References

- [Project Status](../../PROJECT-STATUS.md)
- [Security Update](../../SECURITY-UPDATE.md)
- [Security Audit](../security/audit.md)
- [Security Remediation](../security/remediation.md)
- [Backup & Recovery Guide](../operations/backup-recovery.md)
- [Ansible Guide](../operations/ansible-guide.md)

---

**Last Updated**: October 21, 2025
**Next Review**: November 21, 2025
**Maintained By**: Infrastructure Team
