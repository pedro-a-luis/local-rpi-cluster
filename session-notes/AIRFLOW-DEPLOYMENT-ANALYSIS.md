# Apache Airflow Deployment Analysis & Recommendations

**Date**: 2025-10-20
**Cluster**: Raspberry Pi K3s (8 nodes)
**Current Status**: Partially Functional (Scheduler Running, Webserver Failing)

---

## Executive Summary

Airflow deployment on the Raspberry Pi cluster is experiencing multiple issues that prevent full functionality. The root causes are:

1. **Resource Constraints**: Raspberry Pi nodes (8GB RAM each) are under memory pressure (88-92% on some nodes)
2. **Gunicorn Timeout**: Webserver crashes due to "No response from gunicorn master within 120 seconds"
3. **Volume Attachment Issues**: Longhorn volumes experiencing multi-attach errors and permission issues
4. **Node Instability**: pi-worker-03 showing "NodeNotReady" events

**Recommendation**: Deploy dedicated PostgreSQL for Airflow with reduced resource requirements OR use lighter alternatives.

---

## Detailed Analysis

### 1. **Current Deployment Status**

#### Pods Status:
| Component | Status | Ready | Restarts | Issue |
|-----------|--------|-------|----------|-------|
| Scheduler | Running | 2/2 | 3 | ✅ Working but had early restarts |
| Webserver | CrashLoopBackOff | 0/1 | 6 | ❌ Gunicorn timeout (120s) |
| Triggerer | ContainerCreating | 0/2 | 0 | ❌ Volume attachment errors |
| Statsd | Running | 1/1 | 0 | ✅ Stable |

#### Key Errors Identified:

**Webserver Crash:**
```
[2025-10-20T14:00:23.850+0000] {webserver_command.py:223} ERROR - No response from gunicorn master within 120 seconds
[2025-10-20T14:00:32.752+0000] {webserver_command.py:224} ERROR - Shutting down webserver
```

**Triggerer Volume Issue:**
```
Warning  FailedAttachVolume  Multi-Attach error for volume "pvc-aa67448f-53f9-43ae-bf40-7471ce322bd8"
Volume is already used by pod(s) airflow-scheduler-76b4ccb8f9-8ghwb

volumeattachments.storage.k8s.io "csi-ec279ee590cb3ad43bd96617ead313e3520ab7f7e931c703489bcaf47d4d6769"
is forbidden: User "system:node:pi-worker-04" cannot get resource "volumeattachments"
```

### 2. **Resource Analysis**

#### Node Memory Usage:
```
pi-master:     7126Mi / 8192Mi (88%) ⚠️ HIGH
pi-worker-03:  7462Mi / 8192Mi (92%) ⚠️ CRITICAL
pi-worker-07:  6739Mi / 8192Mi (83%) ⚠️ HIGH
pi-worker-05:  4737Mi / 8192Mi (58%) ✓ OK
pi-worker-01:  2773Mi / 8192Mi (34%) ✓ OK
```

**Analysis**:
- 3 nodes are running at 83-92% memory usage
- Airflow webserver requires ~1-2GB RAM for gunicorn workers (4 workers)
- Scheduler requires ~512MB-1GB RAM
- Total Airflow footprint: **~3-4GB RAM minimum**

**Current Configuration**:
- Webserver: No resource limits set (requests unlimited)
- Scheduler: No resource limits set
- This causes pods to be scheduled on already-stressed nodes

### 3. **Root Causes**

#### A. **Gunicorn Timeout (Webserver)**
**Cause**: Gunicorn master process takes >120 seconds to respond
**Why**:
- Insufficient memory on node (92% usage on pi-worker-03)
- Gunicorn spawning 4 workers simultaneously overwhelms available resources
- Python startup + Flask app initialization + database connection pool setup = high initial resource spike

**Evidence**:
- Webserver scheduled on pi-worker-03 (92% memory usage)
- 6 crash-restart cycles indicate consistent failure
- Scheduler on same node (pi-worker-03) competes for resources

#### B. **Volume Multi-Attach Error (Triggerer)**
**Cause**: Longhorn volume PVC `pvc-aa67448f` already attached to scheduler, triggerer cannot attach
**Why**:
- Airflow DAGs persistence volume (`ReadWriteOnce` access mode)
- Both scheduler and triggerer trying to mount the same PVC
- Longhorn doesn't support multi-attach for RWO volumes across different pods

**Evidence**:
```
Multi-Attach error for volume "pvc-aa67448f-53f9-43ae-bf40-7471ce322bd8"
Volume is already used by pod(s) airflow-scheduler-76b4ccb8f9-8ghwb
```

#### C. **Volume Attachment Permission Error**
**Cause**: Node pi-worker-04 cannot read volumeattachments API resource
**Why**: RBAC permissions issue or node registration problem

**Evidence**:
```
User "system:node:pi-worker-04" cannot get resource "volumeattachments"
in API group "storage.k8s.io"
```

#### D. **Database Not Optimized for Raspberry Pi**
**Cause**: Using shared PostgreSQL originally configured for other workloads
**Why**:
- External PostgreSQL connection pooling not tuned for Airflow
- Network latency adds overhead to every DB query
- Airflow makes MANY small DB queries (scheduler heartbeats, task state checks)

### 4. **Why External PostgreSQL Approach Failed**

Using the existing shared PostgreSQL (`postgresql-primary.databases.svc.cluster.local`) has these issues:

1. **Connection Pool Contention**: Shared with financial-screener and other apps
2. **No Airflow-Specific Tuning**: PostgreSQL settings not optimized for Airflow's query patterns
3. **Network Overhead**: Extra latency for every DB call (Airflow scheduler makes 100s of queries/sec)
4. **Migration Complexity**: Airflow 2.10.5 vs 3.0.2 schema incompatibility caused issues

---

## Alternative Solutions

### **OPTION 1: Dedicated PostgreSQL for Airflow (RECOMMENDED)**

#### Approach:
Deploy a lightweight PostgreSQL instance exclusively for Airflow with resource limits.

#### Benefits:
- ✅ Full Airflow functionality (no compromises)
- ✅ Isolated from other workload database issues
- ✅ Can tune PostgreSQL specifically for Airflow (smaller shared_buffers, etc.)
- ✅ Easier troubleshooting and maintenance
- ✅ No schema migration conflicts

#### Resource Requirements:
```yaml
PostgreSQL:
  CPU: 200m (0.2 cores)
  Memory: 512Mi
  Storage: 5Gi

Total Airflow Stack with dedicated PostgreSQL:
  CPU: ~1.5 cores
  Memory: ~4.5GB
  Storage: 20Gi (5Gi DB + 5Gi DAGs + 10Gi logs)
```

#### Implementation:
```bash
# Use postgres:16-alpine (ARM64 compatible, lightweight)
helm install airflow apache-airflow/airflow \
  --namespace airflow \
  --version 1.16.0 \
  --set postgresql.enabled=true \
  --set postgresql.image.tag=16-alpine \
  --set postgresql.primary.resources.requests.memory=512Mi \
  --set postgresql.primary.resources.requests.cpu=200m \
  --set postgresql.primary.resources.limits.memory=1Gi \
  --set postgresql.primary.resources.limits.cpu=500m \
  --set executor=LocalExecutor \
  --set webserver.resources.requests.memory=1Gi \
  --set webserver.resources.requests.cpu=500m \
  --set webserver.resources.limits.memory=2Gi \
  --set scheduler.resources.requests.memory=512Mi \
  --set scheduler.resources.requests.cpu=300m \
  --set dags.persistence.enabled=true \
  --set dags.persistence.size=5Gi \
  --set logs.persistence.enabled=true \
  --set logs.persistence.size=10Gi
```

#### Why This Works:
- **LocalExecutor** instead of KubernetesExecutor (simpler, less overhead)
- **Resource Limits** prevent node exhaustion
- **postgres:16-alpine** is lightweight (~35MB image vs 200MB+)
- **Dedicated DB** eliminates network overhead and contention

---

### **OPTION 2: Reduce Airflow Footprint (Minimal Mode)**

#### Approach:
Deploy Airflow with minimal components on less-loaded nodes.

#### Configuration:
```yaml
# Disable components
triggerer.enabled: false
statsd.enabled: false

# Use LocalExecutor (no KubernetesExecutor overhead)
executor: LocalExecutor

# Reduce webserver workers
webserver.workers: 2  # down from 4

# Set resource limits
webserver.resources:
  requests:
    memory: 512Mi
    cpu: 250m
  limits:
    memory: 1Gi
    cpu: 500m

scheduler.resources:
  requests:
    memory: 256Mi
    cpu: 200m
  limits:
    memory: 512Mi
    cpu: 400m

# Use NodeSelector to avoid high-memory nodes
nodeSelector:
  kubernetes.io/hostname: pi-worker-01  # or 02, 04, 06 (lower memory usage)
```

#### Benefits:
- ✅ Lower resource footprint (~1.5GB total)
- ✅ Can use external PostgreSQL
- ❌ No distributed task execution (LocalExecutor limitation)
- ❌ Limited scalability

---

### **OPTION 3: Lightweight Alternatives to Airflow**

If Airflow proves too resource-intensive, consider these alternatives:

#### **A. Celery + Celery Beat (Already Deployed!)**

**You already have this running!**

```python
# Use Celery for periodic tasks instead of Airflow
from celery import Celery
from celery.schedules import crontab

app = Celery('tasks', broker='redis://redis.redis.svc.cluster.local:6379/0')

app.conf.beat_schedule = {
    'run-every-morning': {
        'task': 'tasks.data_collection',
        'schedule': crontab(hour=6, minute=0),
    },
}
```

**Benefits**:
- ✅ Already deployed and stable (7/7 workers running)
- ✅ Very lightweight (~50MB per worker)
- ✅ Flower UI for monitoring (already working)
- ❌ No fancy DAG visualization like Airflow
- ❌ Less sophisticated dependency management

**Resource Usage**: ~350MB total (vs 4GB for Airflow)

#### **B. Kubernetes CronJobs**

For simple scheduled tasks:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: data-collector
spec:
  schedule: "0 6 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: collector
            image: your-image
            command: ["python", "collect_data.py"]
          restartPolicy: OnFailure
```

**Benefits**:
- ✅ Native Kubernetes solution
- ✅ Minimal overhead (no persistent components)
- ❌ No web UI
- ❌ Limited workflow capabilities

**Resource Usage**: ~0MB (only runs during job execution)

#### **C. Prefect 2.0 (Lightweight)**

Modern alternative to Airflow:

```bash
# Lighter than Airflow, ~1.5GB total footprint
helm install prefect prefecthq/prefect-server \
  --set postgresql.enabled=true
```

**Benefits**:
- ✅ Modern Python 3.8+ async architecture
- ✅ ~40% less memory than Airflow
- ✅ Better Raspberry Pi compatibility
- ❌ Newer, less mature ecosystem

**Resource Usage**: ~1.5-2GB total

---

## Recommended Action Plan

### **IMMEDIATE: Option 1 - Deploy with Dedicated PostgreSQL**

```bash
# 1. Clean up current deployment
kubectl delete namespace airflow

# 2. Deploy fresh with embedded PostgreSQL
helm install airflow apache-airflow/airflow \
  --namespace airflow \
  --create-namespace \
  --version 1.16.0 \
  --set executor=LocalExecutor \
  --set postgresql.enabled=true \
  --set postgresql.image.registry=docker.io \
  --set postgresql.image.repository=postgres \
  --set postgresql.image.tag=16-alpine \
  --set postgresql.primary.resources.requests.memory=512Mi \
  --set postgresql.primary.resources.limits.memory=1Gi \
  --set postgresql.primary.persistence.size=5Gi \
  --set webserver.defaultUser.enabled=true \
  --set webserver.defaultUser.username=admin \
  --set webserver.defaultUser.password=admin123 \
  --set webserver.resources.requests.memory=1Gi \
  --set webserver.resources.limits.memory=2Gi \
  --set scheduler.resources.requests.memory=512Mi \
  --set scheduler.resources.limits.memory=1Gi \
  --set dags.persistence.enabled=true \
  --set dags.persistence.size=5Gi \
  --set logs.persistence.enabled=true \
  --set logs.persistence.size=10Gi \
  --set nodeSelector.node-role\\.kubernetes\\.io/worker=true

# 3. Apply existing Ingress (already created)
# DNS already configured

# 4. Wait for deployment
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=airflow -n airflow --timeout=10m
```

### **Expected Outcome:**
- Deployment time: 5-10 minutes
- Resource usage: ~4GB RAM, ~1.5 CPU cores
- All components: ✅ Running
- Web UI: ✅ Accessible at https://airflow.stratdata.org

### **If Still Fails:**
Fall back to **Option 3A** (Use existing Celery + Beat)

---

## Comparison Matrix

| Solution | RAM Usage | Setup Time | Functionality | UI Quality | Stability |
|----------|-----------|------------|---------------|------------|-----------|
| **Airflow + Dedicated PostgreSQL** | 4GB | 10min | ★★★★★ | ★★★★★ | ★★★★☆ |
| **Airflow + External PostgreSQL** | 3GB | 15min | ★★★★★ | ★★★★★ | ★★☆☆☆ (current) |
| **Airflow Minimal** | 1.5GB | 10min | ★★★☆☆ | ★★★★☆ | ★★★☆☆ |
| **Celery + Beat** | 350MB | 0min (deployed) | ★★★☆☆ | ★★★☆☆ | ★★★★★ |
| **Kubernetes CronJobs** | ~0MB | 5min | ★★☆☆☆ | ☆☆☆☆☆ | ★★★★★ |
| **Prefect 2.0** | 2GB | 15min | ★★★★☆ | ★★★★☆ | ★★★★☆ |

---

## Technical Specifications

### Hardware Constraints:
- **Node Memory**: 8GB per node (8192Mi total)
- **Available Memory per Node**: ~1.5-2GB after system overhead
- **CPU**: 4 cores per Pi 5 node
- **Storage**: Longhorn distributed storage (RWO volumes)

### Current Issues Summary:
1. ❌ **Webserver**: Gunicorn timeout due to memory pressure
2. ❌ **Triggerer**: Volume multi-attach error (Longhorn RWO limitation)
3. ❌ **Resource Limits**: None set, causing scheduling on overloaded nodes
4. ⚠️ **Node Stability**: pi-worker-03 showing intermittent NodeNotReady
5. ⚠️ **Volume Permissions**: RBAC issue with volumeattachments on pi-worker-04

### Root Cause Chain:
```
Resource-intensive Airflow deployment
  → No resource limits set
    → Scheduled on already-loaded nodes (88-92% memory)
      → Gunicorn can't spawn workers in 120s
        → Webserver crashes
          → CrashLoopBackOff
```

---

## Conclusion

**Primary Recommendation**: Deploy Airflow with dedicated PostgreSQL using LocalExecutor and explicit resource limits.

**Rationale**:
1. Dedicated PostgreSQL eliminates external dependency issues
2. LocalExecutor sufficient for small-to-medium workloads
3. Resource limits prevent node exhaustion
4. postgres:16-alpine is ARM64 native and lightweight
5. Proven approach for Raspberry Pi deployments

**Fallback**: If resource constraints remain, use existing Celery infrastructure which is already stable and operational.
