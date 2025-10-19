# Infrastructure Improvements Roadmap

**Last Updated**: October 2025
**Cluster**: 8-node Raspberry Pi 5 K3s Cluster

This document tracks recommended improvements for backup, monitoring, performance, and additional services.

---

## Current Infrastructure Status

### Deployed Services
- **Monitoring**: Prometheus, Grafana ✅, Alertmanager, Node Exporter, Kube State Metrics
- **Logging**: Loki ✅, Promtail
- **Storage**: Longhorn (1.7TB), NFS (7.3TB)
- **Ingress**: Traefik
- **Dev Tools**: Code Server
- **Workflow**: Apache Airflow (planned)
- **Databases**: PostgreSQL 16-alpine ARM64 ✅

### Known Issues (URGENT)
- [x] Grafana: Init:0/1 status - FIXED ✅
- [x] Loki: Unknown status - FIXED ✅
- [x] PostgreSQL: ImagePullBackOff - FIXED ✅ (Re-deployed with ARM64 image)

---

## Phase 1: Fix Broken Services (URGENT - Week 0) ✅ COMPLETED

**Priority**: 🔴 CRITICAL
**Timeline**: 1-2 days
**Effort**: Low
**Status**: ✅ **COMPLETED - October 19, 2025**

### Tasks
- [x] Investigate and fix Grafana initialization failure ✅
- [x] Investigate and fix Loki pod status ✅
- [x] Fix PostgreSQL ImagePullBackOff (ARM64 image issue) ✅
- [x] Verify all monitoring dashboards are accessible ✅
- [x] Test log aggregation in Loki ✅

### Fixes Applied
1. **Grafana (Init:0/1 → Running 3/3)**
   - Root cause: Longhorn manager pod stuck on pi-worker-03 due to containerd sandbox corruption
   - Fix: Force deleted `longhorn-manager-z2w76`, DaemonSet recreated it successfully
   - Result: https://grafana.stratdata.org accessible (HTTP 302)

2. **Loki (Unknown → Running 1/1)**
   - Root cause: Pod in failed state due to pi-worker-03 Longhorn issues
   - Fix: Deleted failed pod `loki-0` and stuck `engine-image` + `csi-plugin` pods
   - Result: https://loki.stratdata.org/ready returns HTTP 200, actively ingesting logs

3. **PostgreSQL (ImagePullBackOff → Running 1/1)**
   - Root cause: Bitnami image `postgresql:17.6.0-debian-12-r4` not available for ARM64
   - Fix: Deleted broken deployment, re-deployed with `postgres:16-alpine` official image
   - Result: PostgreSQL 16.10 running on ARM64 (aarch64-unknown-linux-musl)

### Success Criteria
- ✅ Grafana accessible at https://grafana.stratdata.org
- ✅ Loki running and ingesting logs from all 8 nodes via Promtail
- ✅ PostgreSQL primary running (postgres:16-alpine ARM64)
- ✅ All monitoring dashboards functional
- ✅ All 8 Longhorn nodes Ready
- ✅ Resource usage: PostgreSQL using 3m CPU, 24Mi memory

---

## Phase 2: Critical Backup Infrastructure (Week 1) ✅ COMPLETED

**Priority**: 🔴 CRITICAL
**Timeline**: 3-5 days
**Effort**: Medium
**Status**: ✅ **COMPLETED - October 19, 2025**

### 1. Velero - Kubernetes Backup & Disaster Recovery ✅ DEPLOYED

**Status**: ✅ **DEPLOYED - v1.17.0**
**Why**: Automated Kubernetes resource and volume backups to MinIO S3 storage

#### Features
- Full cluster backup (namespaces, PVCs, resources)
- Scheduled automated backups
- Point-in-time recovery
- Cluster migration capability
- Volume snapshots

#### Deployment Specs
- **Storage Backend**: NFS on Synology DS118 (7.3TB available)
- **Resources**: ~500MB RAM
- **Backup Schedule**:
  - Daily incremental: 2 AM
  - Weekly full: Sunday 2 AM
  - Retention: 30 days daily, 12 weeks weekly
- **URL**: CLI-based (no web UI)

#### Backup Strategy
- **Daily**: All namespaces except kube-system
- **Weekly**: Full cluster backup including kube-system
- **Critical Data**:
  - Monitoring (Prometheus, Grafana, Loki)
  - Databases (PostgreSQL)
  - Dev Tools (Code Server)
  - Airflow (DAGs, logs, metadata)
  - Longhorn PVCs

#### Deployment Summary

**Completed**:
- ✅ Deployed MinIO v5.x (S3-compatible object storage) - 500Gi NFS
- ✅ Installed Velero CLI v1.17.0 on pi-master
- ✅ Deployed Velero server and node-agent (8 DaemonSet pods)
- ✅ Configured MinIO as backup storage location
- ✅ Created daily backup schedule (2 AM, 30 days retention)
- ✅ Created weekly full backup schedule (3 AM Sunday, 90 days retention)
- ✅ Tested backup and restore successfully (databases namespace)
- ✅ Configured K3s etcd snapshots (every 6 hours, 48 snapshots retention)
- ✅ Created comprehensive backup documentation ([BACKUP-GUIDE.md](BACKUP-GUIDE.md))

**Resources Deployed**:
- MinIO: 1 pod (100m-500m CPU, 256Mi-1Gi RAM, 500Gi storage)
- Velero server: 1 pod (100m-500m CPU, 128Mi-512Mi RAM)
- Node-agent: 8 pods (100m-500m CPU, 128Mi-512Mi RAM each)
- Total: ~1.5-2GB RAM across cluster

**Backup Locations**:
- Primary: MinIO S3 bucket `velero-backups` (NFS-backed)
- etcd: `/var/lib/rancher/k3s/server/db/snapshots/` (local + NFS)

**Testing Results**:
- Backup time: ~30 seconds (50MB PostgreSQL database)
- Restore time: ~20 seconds
- Status: ✅ All tests passed

### 2. Additional Backup Improvements (Future Enhancements)

**Completed**:
- ✅ etcd snapshots configured (requires K3s restart to activate)
- ✅ Velero backup schedules automated
- ✅ Backup documentation created

**Pending** (future work):
- [ ] Database-specific backups (pg_dump cronjob for PostgreSQL)
- [ ] Longhorn backup target configuration (NFS)
- [ ] Offsite backup replication (rclone to cloud storage)
- [ ] Backup encryption (Velero encryption-key-secret)
- [ ] Grafana dashboard for backup monitoring
- [ ] AlertManager rules for backup failures

### Success Criteria ✅
- ✅ Velero running with daily/weekly backups
- ✅ Successfully restore test namespace from backup
- ✅ etcd snapshots configured (pending K3s restart)
- ✅ Backup procedures documented ([BACKUP-GUIDE.md](BACKUP-GUIDE.md))
- ✅ MinIO S3 storage operational (500Gi NFS)
- ✅ Node-agent running on all 8 nodes
- ⚠️ Backup monitoring pending (Phase 3)
- ⚠️ Offsite replication pending (future enhancement)

---

## Phase 3: Enhanced Monitoring & Observability (Week 2)

**Priority**: 🟡 HIGH
**Timeline**: 5-7 days
**Effort**: Medium-High

### 1. Thanos - Long-term Prometheus Storage

**Status**: ❌ Not Deployed
**Why**: Prometheus only retains ~15 days of metrics by default

#### Features
- Unlimited metric retention (years of data)
- Query across multiple Prometheus instances
- Automatic data downsampling for efficiency
- Deduplication
- Cost-effective long-term storage

#### Deployment Specs
- **Components**: Query, Store Gateway, Compactor, Sidecar
- **Storage**: NFS on Synology DS118 (7.3TB)
- **Resources**: ~1GB RAM total
- **Retention**:
  - Raw: 30 days
  - 5m downsampled: 90 days
  - 1h downsampled: 2 years
- **URL**: Integrated into Grafana data sources

#### Tasks
- [ ] Deploy Thanos sidecar to Prometheus
- [ ] Configure object storage (NFS-backed MinIO or direct NFS)
- [ ] Deploy Thanos Query component
- [ ] Deploy Thanos Store Gateway
- [ ] Deploy Thanos Compactor
- [ ] Configure Grafana to use Thanos Query
- [ ] Test long-term query performance
- [ ] Create Ansible playbook: `ansible/playbooks/infrastructure/thanos-install.yml`

### 2. Tempo - Distributed Tracing

**Status**: ❌ Not Deployed
**Why**: No distributed tracing capability for microservices debugging

#### Features
- Distributed request tracing
- Native Grafana integration
- OpenTelemetry compatible
- Service dependency mapping
- Performance bottleneck identification

#### Deployment Specs
- **Storage**: S3-compatible (requires MinIO deployment)
- **Resources**: ~512MB RAM
- **URL**: Integrated into Grafana (no separate UI)
- **Integrations**: Airflow, custom apps, Kubernetes

#### Tasks
- [ ] Deploy MinIO for S3-compatible storage
- [ ] Deploy Tempo
- [ ] Configure Grafana data source
- [ ] Instrument sample application
- [ ] Test end-to-end tracing
- [ ] Create dashboards for trace visualization
- [ ] Create Ansible playbook: `ansible/playbooks/infrastructure/tempo-install.yml`

### 3. OpenTelemetry Collector

**Status**: ❌ Not Deployed
**Why**: Modern unified telemetry collection standard

#### Features
- Unified collection: metrics, logs, traces
- Vendor-agnostic observability
- Multi-destination export
- Built-in processors and exporters

#### Deployment Specs
- **Mode**: DaemonSet (on all nodes)
- **Resources**: ~500MB RAM total
- **Exporters**: Prometheus, Loki, Tempo

#### Tasks
- [ ] Deploy OpenTelemetry Operator
- [ ] Configure collector pipeline
- [ ] Set up exporters (Prometheus, Loki, Tempo)
- [ ] Instrument sample workloads
- [ ] Verify telemetry flow
- [ ] Create Ansible playbook: `ansible/playbooks/infrastructure/otel-install.yml`

### 4. Custom Dashboards & Alerts

#### Grafana Dashboards
- [ ] **Cluster Overview**: Multi-cluster view, resource usage
- [ ] **Longhorn Storage**: Volume health, I/O metrics, capacity
- [ ] **Traefik Ingress**: Request rates, response times, errors
- [ ] **Apache Airflow**: DAG runs, task success/failure, queue depth
- [ ] **Backup Status**: Velero backup success/failure, sizes
- [ ] **Node Health**: Per-node CPU, memory, disk, network, temperature
- [ ] **Application SLOs**: Uptime, error rates, latency percentiles

#### Alerting Rules
- [ ] **Critical**: Node down, disk >90%, pod crash loops
- [ ] **Warning**: High memory usage, slow I/O, certificate expiry <7 days
- [ ] **Info**: Backup completion, update available
- [ ] Configure AlertManager integrations (email, Slack, PagerDuty)

#### Tasks
- [ ] Import community dashboards for Longhorn, Traefik, Airflow
- [ ] Create custom cluster overview dashboard
- [ ] Define SLI/SLO metrics
- [ ] Create PrometheusRule CRDs for alerts
- [ ] Test alert firing and recovery
- [ ] Document alert runbooks

### 5. Uptime Kuma - Simple Uptime Monitoring

**Status**: ❌ Not Deployed
**Why**: Beautiful, simple UI for service availability

#### Features
- HTTP/HTTPS monitoring
- TCP/Ping monitoring
- Beautiful status page
- Multi-notification channels
- Response time tracking

#### Deployment Specs
- **Resources**: ~256MB RAM
- **Storage**: 1GB (SQLite)
- **URL**: https://uptime.stratdata.org

#### Tasks
- [ ] Deploy Uptime Kuma
- [ ] Configure monitors for all services
- [ ] Set up notification channels
- [ ] Create public status page (optional)
- [ ] Create Ansible playbook: `ansible/playbooks/infrastructure/uptime-kuma-install.yml`

### Success Criteria
- ✅ Thanos deployed with 2+ years retention
- ✅ Tempo tracing working end-to-end
- ✅ Custom dashboards for all critical services
- ✅ Alerting rules configured and tested
- ✅ Uptime Kuma monitoring all services

---

## Phase 4: Performance Optimization (Week 3)

**Priority**: 🟡 HIGH
**Timeline**: 3-5 days
**Effort**: Medium

### 1. Goldilocks - Resource Right-sizing

**Status**: ❌ Not Deployed
**Why**: Optimize resource allocation across 8 nodes (64GB RAM total)

#### Features
- VPA (Vertical Pod Autoscaler) recommendations
- Resource request/limit suggestions
- Dashboard showing over/under-provisioned pods
- Namespace-level optimization

#### Deployment Specs
- **Resources**: ~100MB RAM
- **URL**: https://goldilocks.stratdata.org (dashboard)

#### Tasks
- [ ] Deploy Goldilocks
- [ ] Enable VPA recommendations for all namespaces
- [ ] Review recommendations for top 10 resource consumers
- [ ] Apply optimized resource requests/limits
- [ ] Monitor impact on resource utilization
- [ ] Create Ansible playbook: `ansible/playbooks/infrastructure/goldilocks-install.yml`

### 2. Performance Monitoring Enhancements

#### Node-level Performance
- [ ] Enable CPU frequency monitoring
- [ ] Monitor thermal throttling on RPi5
- [ ] Track disk I/O latency (NVMe)
- [ ] Network throughput monitoring

#### Application Performance
- [ ] Set up application performance baselines
- [ ] Configure SLI tracking (latency, error rate, throughput)
- [ ] Create performance regression alerts

#### Storage Performance
- [ ] Longhorn I/O latency dashboards
- [ ] NFS mount performance monitoring
- [ ] Volume IOPS and throughput tracking

### 3. Load Testing Infrastructure

**Status**: ❌ Not Deployed
**Why**: Test cluster capacity and service performance limits

#### Options
- **k6**: Modern load testing (Go-based)
- **Locust**: Python-based, distributed testing
- **Grafana k6**: Cloud + OSS integration

#### Tasks
- [ ] Choose load testing tool (recommend k6)
- [ ] Create baseline load tests for critical services
- [ ] Document performance benchmarks
- [ ] Schedule periodic load tests (monthly)
- [ ] Store results in Prometheus/Grafana

### Success Criteria
- ✅ Goldilocks deployed and providing recommendations
- ✅ Resource requests/limits optimized for top workloads
- ✅ Performance baselines documented
- ✅ Load testing framework in place
- ✅ 10-20% improvement in resource efficiency

---

## Phase 5: Data & Analytics Services (Week 4-5)

**Priority**: 🟢 MEDIUM
**Timeline**: 5-7 days
**Effort**: Medium-High

### 1. Apache Superset - Data Visualization

**Status**: ❌ Not Deployed
**Why**: Perfect complement to Airflow for visualizing pipeline data

#### Features
- Modern BI and data exploration
- SQL editor with autocomplete
- Interactive dashboards
- Multiple database connectors
- Chart builder

#### Deployment Specs
- **Resources**: ~2GB RAM
- **Database**: PostgreSQL (shared or dedicated)
- **Storage**: 5GB (Longhorn)
- **URL**: https://superset.stratdata.org
- **Auth**: Admin/password or LDAP

#### Tasks
- [ ] Deploy Superset via Helm
- [ ] Configure PostgreSQL backend
- [ ] Create Ingress with TLS
- [ ] Connect to data sources
- [ ] Create sample dashboards
- [ ] Integrate with Airflow (metadata DB)
- [ ] Create Ansible playbook: `ansible/playbooks/infrastructure/superset-install.yml`

### 2. JupyterHub - Multi-user Jupyter Notebooks

**Status**: ❌ Not Deployed
**Why**: Interactive data science and analysis platform

#### Features
- Multi-user Jupyter notebooks
- Kubernetes-native (spawn pods per user)
- Persistent storage per user
- Multiple kernel support (Python, R, Julia)
- Integration with data sources

#### Deployment Specs
- **Resources**: ~1GB base + 512MB-2GB per user
- **Storage**: 10GB per user (Longhorn)
- **URL**: https://jupyter.stratdata.org
- **Max Users**: 4-6 concurrent (resource constrained)

#### Tasks
- [ ] Deploy JupyterHub via Helm
- [ ] Configure spawner (KubeSpawner)
- [ ] Set up persistent storage
- [ ] Install common data science libraries
- [ ] Configure resource limits per user
- [ ] Test multi-user access
- [ ] Create Ansible playbook: `ansible/playbooks/infrastructure/jupyterhub-install.yml`

### 3. MinIO - S3-compatible Object Storage

**Status**: ❌ Not Deployed
**Why**: S3-compatible storage for data lakes, Airflow logs, Tempo traces

#### Features
- S3-compatible API
- Multi-tenant
- Versioning and lifecycle policies
- Web console
- High availability mode

#### Deployment Specs
- **Mode**: Distributed (4 nodes for HA)
- **Resources**: ~512MB RAM per instance
- **Storage**: NFS-backed or Longhorn (100GB+)
- **URL**:
  - Console: https://minio.stratdata.org
  - API: https://s3.stratdata.org

#### Use Cases
- Tempo trace storage
- Thanos object storage (alternative to NFS)
- Airflow log storage
- Data lake for analytics
- Velero backup target

#### Tasks
- [ ] Deploy MinIO in distributed mode
- [ ] Create buckets: tempo, thanos, airflow-logs, backups, data-lake
- [ ] Configure lifecycle policies
- [ ] Set up access credentials
- [ ] Create DNS entries (minio, s3)
- [ ] Test S3 API compatibility
- [ ] Integrate with Tempo and Thanos
- [ ] Create Ansible playbook: `ansible/playbooks/infrastructure/minio-install.yml`

### 4. MLflow - ML Lifecycle Management

**Status**: ❌ Not Deployed
**Why**: Track ML experiments and manage models (if doing ML work)

#### Features
- Experiment tracking
- Model registry
- Model deployment
- Compare runs and models
- Integration with popular ML libraries

#### Deployment Specs
- **Resources**: ~1GB RAM
- **Database**: PostgreSQL
- **Storage**: MinIO (for artifacts)
- **URL**: https://mlflow.stratdata.org

#### Tasks
- [ ] Deploy MLflow server
- [ ] Configure PostgreSQL backend
- [ ] Configure MinIO artifact storage
- [ ] Test experiment tracking
- [ ] Create sample ML pipeline
- [ ] Integrate with JupyterHub
- [ ] Create Ansible playbook: `ansible/playbooks/infrastructure/mlflow-install.yml`

### Success Criteria
- ✅ Superset deployed with sample dashboards
- ✅ JupyterHub multi-user access working
- ✅ MinIO serving as S3 backend
- ✅ MLflow tracking experiments (if needed)
- ✅ End-to-end data pipeline: Airflow → Process → Superset

---

## Phase 6: Development & CI/CD (Week 6)

**Priority**: 🟢 MEDIUM
**Timeline**: 3-5 days
**Effort**: Medium

### 1. Gitea - Lightweight Git Hosting

**Status**: ❌ Not Deployed
**Why**: Self-hosted Git for DAG development and infrastructure code

#### Features vs GitLab CE
- **Gitea**: Lightweight (~512MB RAM), fast, simple
- **GitLab CE**: Full-featured (~4GB RAM), heavy, CI/CD built-in

**Recommendation**: Gitea (resource-constrained cluster)

#### Deployment Specs
- **Resources**: ~512MB RAM
- **Database**: PostgreSQL (shared)
- **Storage**: 20GB (Longhorn)
- **URL**: https://git.stratdata.org

#### Tasks
- [ ] Deploy Gitea
- [ ] Configure PostgreSQL backend
- [ ] Set up user accounts
- [ ] Migrate repos from GitHub/GitLab (optional)
- [ ] Configure webhooks for CI/CD
- [ ] Create organizations and repos
- [ ] Create Ansible playbook: `ansible/playbooks/infrastructure/gitea-install.yml`

### 2. Harbor - Container Registry

**Status**: ❌ Not Deployed
**Why**: Private Docker registry for custom images

#### Features
- Private container registry
- Vulnerability scanning
- Image signing
- Helm chart repository
- Replication

#### Deployment Specs
- **Resources**: ~2GB RAM
- **Database**: PostgreSQL
- **Storage**: 50GB+ (Longhorn)
- **URL**: https://harbor.stratdata.org

#### Use Cases
- Store custom Airflow DAG images
- Cache public images locally
- Private ML model serving images
- Custom application images

#### Tasks
- [ ] Deploy Harbor via Helm
- [ ] Configure PostgreSQL and Redis
- [ ] Set up Longhorn storage
- [ ] Create projects (airflow, ml, apps)
- [ ] Configure vulnerability scanning
- [ ] Test image push/pull
- [ ] Configure K3s to use Harbor
- [ ] Create Ansible playbook: `ansible/playbooks/infrastructure/harbor-install.yml`

### 3. ArgoCD - GitOps Continuous Delivery

**Status**: ❌ Not Deployed
**Why**: Declarative GitOps for infrastructure and application deployment

#### Features
- Git as single source of truth
- Automatic sync from Git repos
- Rollback capability
- Multi-cluster support
- Beautiful UI and CLI

#### Deployment Specs
- **Resources**: ~512MB RAM
- **Storage**: 5GB (Longhorn)
- **URL**: https://argocd.stratdata.org

#### GitOps Workflow
1. Update manifest in Git
2. ArgoCD detects change
3. Auto-sync to cluster
4. Monitor deployment status

#### Tasks
- [ ] Deploy ArgoCD
- [ ] Configure Git repository connections
- [ ] Create applications for:
  - Infrastructure (monitoring, logging, storage)
  - Data platform (Airflow, Superset, JupyterHub)
  - Development tools (Gitea, Harbor)
- [ ] Set up auto-sync policies
- [ ] Configure notifications
- [ ] Migrate existing deployments to GitOps
- [ ] Create Ansible playbook: `ansible/playbooks/infrastructure/argocd-install.yml`

### Success Criteria
- ✅ Gitea hosting infrastructure repos
- ✅ Harbor storing custom images
- ✅ ArgoCD managing deployments via GitOps
- ✅ End-to-end workflow: Git push → ArgoCD sync → Deployment

---

## Phase 7: Collaboration & Knowledge Management (Week 7)

**Priority**: 🟢 LOW-MEDIUM
**Timeline**: 2-3 days
**Effort**: Low

### 1. Wiki.js - Documentation Platform

**Status**: ❌ Not Deployed
**Why**: Centralize documentation, runbooks, team knowledge

#### Features
- Modern, fast wiki
- Markdown editor with live preview
- Git-backed storage
- Search functionality
- Access control

#### Deployment Specs
- **Resources**: ~512MB RAM
- **Database**: PostgreSQL
- **Storage**: 5GB (Longhorn)
- **URL**: https://wiki.stratdata.org

#### Content
- Service documentation
- Runbooks and procedures
- Architecture diagrams
- Troubleshooting guides
- Best practices

#### Tasks
- [ ] Deploy Wiki.js
- [ ] Configure PostgreSQL backend
- [ ] Set up Git sync (optional)
- [ ] Create initial pages
- [ ] Migrate existing documentation
- [ ] Create Ansible playbook: `ansible/playbooks/infrastructure/wiki-install.yml`

### 2. Nextcloud - File Sync & Collaboration (Optional)

**Status**: ❌ Not Deployed
**Why**: Self-hosted file sharing (heavy on resources)

#### Features
- File sync and share
- Calendar and contacts
- Collaborative editing
- Mobile apps

#### Deployment Specs
- **Resources**: ~2GB RAM
- **Database**: PostgreSQL
- **Storage**: 100GB+ (NFS)
- **URL**: https://cloud.stratdata.org

**Note**: Resource-intensive; consider only if needed.

---

## Phase 8: Message Queue & Streaming (Week 8+)

**Priority**: 🟢 LOW
**Timeline**: 3-5 days
**Effort**: Medium

### 1. Redis - In-memory Cache

**Status**: ❌ Not Deployed
**Why**: Caching layer, session storage, Airflow Celery backend

#### Features
- In-memory key-value store
- Pub/sub messaging
- Persistence options
- High performance

#### Deployment Specs
- **Mode**: Sentinel (HA) or single instance
- **Resources**: ~256MB-1GB RAM
- **Storage**: 5GB (persistence)
- **URL**: Internal service (no ingress)

#### Use Cases
- Airflow CeleryExecutor backend (if switching from Kubernetes)
- Application caching
- Session storage
- Rate limiting

#### Tasks
- [ ] Deploy Redis (bitnami/redis Helm chart)
- [ ] Configure persistence
- [ ] Set up monitoring
- [ ] Test connectivity
- [ ] Create Ansible playbook: `ansible/playbooks/infrastructure/redis-install.yml`

### 2. RabbitMQ - Message Broker

**Status**: ❌ Not Deployed
**Why**: Reliable message queue for async workflows

#### Features
- Message queuing
- Multiple messaging protocols
- Management UI
- Clustering support

#### Deployment Specs
- **Resources**: ~512MB RAM
- **Storage**: 5GB (Longhorn)
- **URL**: https://rabbitmq.stratdata.org (management UI)

#### Use Cases
- Decouple microservices
- Async job processing
- Event-driven architecture

#### Tasks
- [ ] Deploy RabbitMQ
- [ ] Configure vhosts and users
- [ ] Set up monitoring
- [ ] Create sample producer/consumer
- [ ] Create Ansible playbook: `ansible/playbooks/infrastructure/rabbitmq-install.yml`

### 3. Apache Kafka (Resource-intensive)

**Status**: ❌ Not Deployed
**Why**: Event streaming (only if needed, very resource-hungry)

**Note**: Requires 2-4GB RAM. Only deploy if event streaming is critical.

---

## Phase 9: Advanced Monitoring (Week 9+)

**Priority**: 🟢 LOW
**Timeline**: Variable
**Effort**: High

### 1. Pixie - Auto-instrumented Observability

**Status**: ❌ Not Deployed
**Why**: See API calls, DB queries without code changes (eBPF magic)

#### Features
- Auto-instrumentation via eBPF
- No code changes required
- Real-time debugging
- Application-level insights

#### Deployment Specs
- **Resources**: ~2GB RAM
- **Architecture**: ARM64 support (check compatibility)

**Note**: Verify ARM64/RPi5 support before deployment.

### 2. Kubecost / OpenCost

**Status**: ❌ Not Deployed
**Why**: Cost visibility (interesting for homelab power usage)

#### Features
- Cost per namespace/pod/service
- Resource efficiency metrics
- Recommendations

#### Deployment Specs
- **Resources**: ~500MB RAM
- **URL**: https://kubecost.stratdata.org

---

## Summary & Resource Allocation

### Total Additional Resource Requirements

| Phase | Service | RAM | Storage | Priority |
|-------|---------|-----|---------|----------|
| 1 | Velero | 500MB | NFS | 🔴 Critical |
| 3 | Thanos | 1GB | NFS | 🟡 High |
| 3 | Tempo | 512MB | MinIO | 🟡 High |
| 3 | OpenTelemetry | 500MB | - | 🟡 High |
| 3 | Uptime Kuma | 256MB | 1GB | 🟡 High |
| 4 | Goldilocks | 100MB | - | 🟡 High |
| 5 | Superset | 2GB | 5GB | 🟢 Medium |
| 5 | JupyterHub | 1GB base | 10GB/user | 🟢 Medium |
| 5 | MinIO | 2GB (4 pods) | 100GB+ | 🟢 Medium |
| 5 | MLflow | 1GB | MinIO | 🟢 Medium |
| 6 | Gitea | 512MB | 20GB | 🟢 Medium |
| 6 | Harbor | 2GB | 50GB | 🟢 Medium |
| 6 | ArgoCD | 512MB | 5GB | 🟢 Medium |
| 7 | Wiki.js | 512MB | 5GB | 🟢 Low |
| 8 | Redis | 256MB | 5GB | 🟢 Low |
| 8 | RabbitMQ | 512MB | 5GB | 🟢 Low |

### **Total if deploying all:**
- **RAM**: ~13.5GB additional (currently have 64GB total)
- **Storage**: ~200GB Longhorn + NFS for backups/object storage

### **Realistic Deployment (Phases 1-6):**
- **RAM**: ~10GB additional
- **Storage**: ~150GB

### Current Cluster Capacity
- **Nodes**: 8x Raspberry Pi 5 (8GB RAM each) = 64GB total
- **Storage**: 1.7TB Longhorn + 7.3TB NFS
- **Available RAM**: ~40GB usable after system overhead

**Verdict**: Cluster can handle Phases 1-6 comfortably. Phases 7-9 are optional.

---

## Next Steps

1. **Immediate**: Fix broken services (Grafana, Loki, PostgreSQL)
2. **Week 1**: Deploy Velero for backup
3. **Week 2**: Enhanced monitoring (Thanos, Tempo)
4. **Week 3**: Performance optimization (Goldilocks)
5. **Week 4-6**: Data platform and CI/CD
6. **Week 7+**: Optional services

---

## Related Documentation

- [README.md](README.md) - Main documentation
- [ANSIBLE.md](ANSIBLE.md) - Ansible automation guide
- [SECURITY-AUDIT.md](SECURITY-AUDIT.md) - Security assessment
- [SECURITY-REMEDIATION-GUIDE.md](SECURITY-REMEDIATION-GUIDE.md) - Security fixes
- [AIRFLOW-DEPLOYMENT.md](AIRFLOW-DEPLOYMENT.md) - Airflow deployment guide
- [cluster-access-guide.md](cluster-access-guide.md) - Access credentials

---

**Maintained By**: Admin
**Review Frequency**: Monthly
**Last Review**: October 2025
