# Celery Deployment Changes - October 2025

This document describes the changes made to the Celery deployment to fix issues encountered during initial deployment.

## Issues Fixed

### 1. Dependency Conflict Error ✅

**Problem:**
```
ERROR: Cannot install celery[redis]==5.3.4 and redis==5.0.1
The conflict is caused by:
    The user requested redis==5.0.1
    celery[redis] 5.3.4 depends on redis!=4.5.5, <5.0.0 and >=4.5.2
```

**Root Cause:**
- Celery 5.3.4 requires `redis<5.0.0`
- We were explicitly installing `redis==5.0.1` which conflicts

**Solution:**
- Use `celery[redis]==5.3.4` only (includes compatible redis version)
- Remove explicit `redis==5.0.1` specification

**Files Changed:**
- `scripts/deployment/deploy-celery.sh`
- `ansible/playbooks/celery-install.yml`
- `kubernetes/celery/celery-deployment.yaml`

**Change:**
```bash
# Before
pip install --no-cache-dir celery[redis]==5.3.4 redis==5.0.1

# After
pip install --no-cache-dir celery[redis]==5.3.4
```

### 2. Beat Read-Only Filesystem Error ✅

**Problem:**
```
OSError: [Errno 30] Read-only file system: 'celerybeat-schedule'
```

**Root Cause:**
- Celery Beat needs to write its schedule database (`celerybeat-schedule`)
- Default working directory `/app` is mounted from ConfigMap (read-only)
- Beat tries to write schedule file in current directory by default

**Solution:**
1. Added `emptyDir` volume named `beat-data` mounted at `/app/data`
2. Updated Beat command to use schedule file in writable location: `-s /app/data/celerybeat-schedule`

**Files Changed:**
- `scripts/deployment/deploy-celery.sh`
- `ansible/playbooks/celery-install.yml`
- `kubernetes/celery/celery-deployment.yaml`

**Changes:**

```yaml
# Added to Beat deployment spec.template.spec.containers[0]:
volumeMounts:
- name: celery-app
  mountPath: /app
- name: beat-data              # NEW
  mountPath: /app/data          # NEW

# Added to Beat deployment spec.template.spec:
volumes:
- name: celery-app
  configMap:
    name: celery-app
    defaultMode: 0755
- name: beat-data               # NEW
  emptyDir: {}                  # NEW
```

```bash
# Updated Beat command:
# Before
celery -A tasks beat --loglevel=info

# After
celery -A tasks beat --loglevel=info -s /app/data/celerybeat-schedule
```

### 3. Flower Restart Loop ✅

**Problem:**
- Flower pod continuously restarting
- Status: `CrashLoopBackOff` or frequent restarts
- Logs showed Flower starting successfully but then being killed

**Root Cause:**
- Readiness probe was checking too early (10s initial delay)
- `pip install celery[redis]` takes 30-60 seconds on first run
- Kubernetes killed the pod before Flower could start

**Solution:**
1. Removed readiness probe (not needed for this use case)
2. Increased liveness probe initial delay to 60 seconds
3. Added timeout to liveness probe

**Files Changed:**
- `scripts/deployment/deploy-celery.sh`
- `ansible/playbooks/celery-install.yml`
- `kubernetes/celery/celery-deployment.yaml`

**Changes:**

```yaml
# Before
livenessProbe:
  httpGet:
    path: /
    port: 5555
  initialDelaySeconds: 30
  periodSeconds: 10
readinessProbe:                 # REMOVED
  httpGet:
    path: /
    port: 5555
  initialDelaySeconds: 10
  periodSeconds: 5

# After
livenessProbe:
  httpGet:
    path: /
    port: 5555
  initialDelaySeconds: 60       # Increased from 30
  periodSeconds: 10
  timeoutSeconds: 5             # Added
# No readiness probe
```

## Summary of Changes

### Files Modified:

1. **Deployment Script:** `scripts/deployment/deploy-celery.sh`
   - Fixed dependency specification (removed `redis==5.0.1`)
   - Added Beat emptyDir volume and mount
   - Updated Beat command with schedule file path
   - Removed Flower readiness probe
   - Increased Flower liveness probe delay

2. **Ansible Playbook:** `ansible/playbooks/celery-install.yml`
   - Same changes as deployment script

3. **Kubernetes Manifests:** `kubernetes/celery/celery-deployment.yaml`
   - Same changes as deployment script

4. **Documentation:** `docs/deployment/celery.md`
   - Added configuration details about Beat volume
   - Added troubleshooting sections for all three issues
   - Updated Celery configuration section

5. **Quick Start:** `CELERY-REDIS-QUICKSTART.md`
   - Added note about fixes included in deployment

## Current Deployment Status

All pods are now running successfully:

```bash
NAME                             READY   STATUS    RESTARTS   AGE
celery-beat-9554dc9f8-vl84x      1/1     Running   0          Xm
celery-flower-58c5b9859-tdt7f    1/1     Running   0          Xm
celery-worker-64d8d5dd99-cvzcg   1/1     Running   0          Xm
celery-worker-64d8d5dd99-gkqrj   1/1     Running   0          Xm
redis-66b5b54686-4rr28           1/1     Running   0          Xm
```

## Deployment Configuration

### Beat Configuration:
```yaml
Schedule file: /app/data/celerybeat-schedule
Volume: emptyDir (ephemeral)
Mount point: /app/data
```

**Note:** Beat schedule is ephemeral (stored in emptyDir). If the Beat pod is deleted, the schedule will be rebuilt from the task definitions in the ConfigMap. This is acceptable for our use case.

### Flower Configuration:
```yaml
Liveness probe: 60s initial delay
Readiness probe: None
Timeout: 5s
```

### Worker Configuration:
```yaml
Replicas: 2
Concurrency: 2 per worker
Total parallel tasks: 4
```

## Testing

### Verify Deployment:
```bash
# Check all pods are running
kubectl get pods -n celery -n redis

# Check Beat logs (should see "beat: Starting...")
kubectl logs -n celery -l component=beat --tail=20

# Check Flower is accessible
curl -I https://flower.stratdata.org
```

### Test Task Execution:
```bash
# Create test pod
kubectl run celery-test --rm -i --tty --image=python:3.11-slim -n celery -- bash

# Inside the pod:
pip install celery[redis]
python -c "
from celery import Celery
app = Celery('test', broker='redis://redis.redis.svc.cluster.local:6379/0')
result = app.send_task('tasks.add', args=[4, 4])
print('Task sent:', result.id)
"
```

## Future Improvements

### Optional: Persistent Beat Schedule

If you want Beat's schedule to persist across pod restarts:

```yaml
# Replace emptyDir with PVC
volumes:
- name: beat-data
  persistentVolumeClaim:
    claimName: beat-pvc
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: beat-pvc
  namespace: celery
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
```

**Benefit:** Schedule state persists across restarts
**Drawback:** Requires Longhorn storage, adds complexity

### Optional: Custom Celery Image

Instead of `pip install` on every pod start, create a custom image:

```dockerfile
FROM python:3.11-slim
WORKDIR /app
RUN pip install --no-cache-dir celery[redis]==5.3.4
COPY tasks.py /app/
CMD ["celery", "-A", "tasks", "worker", "--loglevel=info"]
```

**Benefit:** Faster pod startup, consistent versions
**Drawback:** Need to maintain custom image, rebuild for changes

## Conclusion

All deployment issues have been resolved and documented. The deployment files now include these fixes by default. Future deployments will work out of the box without manual patching.

---

**Date:** October 19, 2025
**Fixed by:** Claude (Sonnet 4.5)
**Status:** All issues resolved ✅
