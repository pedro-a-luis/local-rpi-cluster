# Celery & Redis Deployment Guide

This guide covers deploying Celery distributed task queue with Redis as the message broker on the Raspberry Pi K3s cluster.

## Overview

**Components:**
- **Redis**: Message broker and result backend (shared service)
- **Celery Workers**: Execute asynchronous tasks
- **Celery Beat**: Periodic task scheduler
- **Flower**: Real-time monitoring web interface

**Access:**
- Flower UI: https://flower.stratdata.org
- Username: `admin`
- Password: `flower123`

## Architecture

```
┌─────────────────────────────────────────────┐
│ Celery Distributed Task Queue              │
│                                             │
│  ┌──────────┐      ┌──────────────┐       │
│  │  Flower  │─────▶│ Celery Beat  │       │
│  │  (UI)    │      │ (Scheduler)  │       │
│  └──────────┘      └──────┬───────┘       │
│       │                   │               │
│       │                   ▼               │
│       │          ┌─────────────────┐      │
│       └─────────▶│ Redis (Broker)  │      │
│                  └────────┬────────┘      │
│                           │               │
│                  ┌────────▼────────┐      │
│                  │ Celery Workers  │      │
│                  │ (2 replicas)    │      │
│                  └─────────────────┘      │
└─────────────────────────────────────────────┘
```

## Prerequisites

- K3s cluster running
- kubectl configured
- Longhorn storage available
- Traefik/Nginx ingress controller
- Let's Encrypt wildcard certificate

## Deployment

### Step 1: Deploy Redis

Redis is deployed as a shared service in its own namespace, available to all applications.

```bash
ansible-playbook ansible/playbooks/redis-install.yml
```

**What it does:**
- Creates `redis` namespace
- Deploys Redis 7 (Alpine) with persistence
- Creates 5Gi Longhorn PVC for data
- Configures Redis for optimal Kubernetes performance
- Exposes Redis service cluster-wide

**Verification:**
```bash
# Check Redis status
kubectl get pods -n redis
kubectl get svc -n redis

# Test Redis connection
kubectl run redis-test --rm -i --restart=Never --image=redis:7-alpine -n redis -- \
  redis-cli -h redis.redis.svc.cluster.local ping
# Expected output: PONG
```

### Step 2: Deploy Celery

```bash
ansible-playbook ansible/playbooks/celery-install.yml
```

**What it does:**
- Creates `celery` namespace
- Deploys 2 Celery worker replicas
- Deploys Celery Beat scheduler (1 replica)
- Deploys Flower monitoring UI
- Creates ingress for Flower web interface
- Copies TLS certificate to celery namespace

**Deployment takes:** ~2-3 minutes

### Step 3: Update DNS

Add Flower to your DNS configuration:

```bash
# Edit the DNS playbook
vim ansible/playbooks/infrastructure/update-pihole-dns.yml

# Add to the stratdata_services list:
#   - { name: "flower", ip: "192.168.1.240" }

# Run the DNS update
ansible-playbook ansible/playbooks/infrastructure/update-pihole-dns.yml
```

Or manually add to Pi-hole:
```bash
# SSH to Pi-hole
ssh admin@192.168.1.25

# Add DNS entry
echo "192.168.1.240 flower.stratdata.org" | sudo tee -a /etc/pihole/custom.list
sudo pihole restartdns
```

### Step 4: Verify Installation

```bash
# Check all pods are running
kubectl get pods -n celery
kubectl get pods -n redis

# Check services
kubectl get svc -n celery
kubectl get svc -n redis

# Check ingress
kubectl get ingress -n celery

# View Flower logs
kubectl logs -n celery -l component=flower

# View worker logs
kubectl logs -n celery -l component=worker
```

**Access Flower:**
1. Open https://flower.stratdata.org
2. Login: `admin` / `flower123`
3. You should see 2 active workers

## Configuration

### Redis Configuration

Redis is configured for Kubernetes workloads:

```yaml
# Memory: 256MB with LRU eviction
maxmemory: 256mb
maxmemory-policy: allkeys-lru

# Persistence: AOF + RDB snapshots
appendonly: yes
save 900 1    # After 900s if 1 key changed
save 300 10   # After 300s if 10 keys changed
save 60 10000 # After 60s if 10000 keys changed
```

**Connection string:**
```
redis://redis.redis.svc.cluster.local:6379/0
```

### Celery Configuration

**Workers:**
- Replicas: 2
- Concurrency: 2 per worker
- Max tasks per child: 1000
- Task time limit: 30 minutes

**Beat (Scheduler):**
- Replicas: 1 (must be single instance)
- Schedule file: `/app/data/celerybeat-schedule` (stored in emptyDir volume)
- Writable volume: `beat-data` mounted at `/app/data`
- Default schedules:
  - `hello`: Every minute (health check)
  - `cleanup_old_results`: Every 6 hours

**Flower (Monitoring):**
- Liveness probe: 60s initial delay (allows time for pip install)
- No readiness probe (to prevent premature restarts)

### Example Tasks

Default tasks included in `celery-app` ConfigMap:

```python
from tasks import add, multiply, hello, long_running

# Simple math tasks
result = add.delay(4, 4)
print(result.get())  # 8

# Long-running task
result = long_running.delay(duration=30)
print(result.get())  # "Task completed after 30 seconds"
```

## Customizing Tasks

### Method 1: Edit ConfigMap (Quick)

```bash
# Edit tasks directly
kubectl edit configmap celery-app -n celery

# Restart workers to pick up changes
kubectl rollout restart deployment/celery-worker -n celery
kubectl rollout restart deployment/celery-beat -n celery
```

### Method 2: Create Custom Image (Production)

1. **Create your tasks.py:**

```python
from celery import Celery
import time

app = Celery('myapp')

app.conf.update(
    broker_url='redis://redis.redis.svc.cluster.local:6379/0',
    result_backend='redis://redis.redis.svc.cluster.local:6379/0',
)

@app.task
def process_data(data):
    # Your custom logic
    time.sleep(5)
    return f"Processed: {data}"
```

2. **Create Dockerfile:**

```dockerfile
FROM python:3.11-slim

WORKDIR /app

RUN pip install celery[redis]==5.3.4 redis==5.0.1

COPY tasks.py /app/

CMD ["celery", "-A", "tasks", "worker", "--loglevel=info"]
```

3. **Build and push:**

```bash
docker build -t your-registry/celery-worker:latest .
docker push your-registry/celery-worker:latest
```

4. **Update deployment:**

```bash
# Edit the Celery playbook to use your custom image
vim ansible/playbooks/celery-install.yml

# Change image from python:3.11-slim to your-registry/celery-worker:latest
# Remove the pip install command

# Redeploy
ansible-playbook ansible/playbooks/celery-install.yml
```

## Scaling

### Scale Workers

```bash
# Scale to 4 workers
kubectl scale deployment celery-worker -n celery --replicas=4

# Verify
kubectl get pods -n celery -l component=worker
```

### Adjust Concurrency

Edit the playbook and redeploy:

```bash
vim ansible/playbooks/celery-install.yml
# Change: celery_concurrency: 4

ansible-playbook ansible/playbooks/celery-install.yml
```

### Scale Redis (if needed)

For high-load scenarios, consider Redis Cluster or Sentinel:

```bash
# For now, increase resources
kubectl edit deployment redis -n redis
# Increase memory/CPU limits
```

## Monitoring

### Flower Web UI

Access: https://flower.stratdata.org

**Features:**
- Real-time worker monitoring
- Task history and statistics
- Task execution rates
- Worker resource usage
- Manual task execution
- Task result inspection

### Kubernetes Monitoring

```bash
# Worker logs
kubectl logs -n celery -l component=worker --tail=100 -f

# Beat scheduler logs
kubectl logs -n celery -l component=beat --tail=100 -f

# Flower logs
kubectl logs -n celery -l component=flower --tail=100 -f

# Redis logs
kubectl logs -n redis -l app=redis --tail=100 -f

# Resource usage
kubectl top pods -n celery
kubectl top pods -n redis
```

### Grafana Integration

Create Prometheus ServiceMonitor for Celery metrics:

```yaml
# Optional: Expose Celery metrics
apiVersion: v1
kind: Service
metadata:
  name: celery-worker-metrics
  namespace: celery
spec:
  selector:
    component: worker
  ports:
  - name: metrics
    port: 9540
```

## Troubleshooting

### Workers Not Connecting to Redis

```bash
# Check Redis is running
kubectl get pods -n redis

# Test Redis from worker namespace
kubectl run redis-test --rm -i --restart=Never --image=redis:7-alpine -n celery -- \
  redis-cli -h redis.redis.svc.cluster.local ping

# Check worker logs
kubectl logs -n celery -l component=worker
```

### Tasks Not Executing

```bash
# Check worker status in Flower
# Visit https://flower.stratdata.org

# Check if workers are registered
kubectl exec -n celery -it deployment/celery-worker -- celery -A tasks inspect active

# Check Redis queue length
kubectl exec -n redis -it deployment/redis -- redis-cli llen celery
```

### Flower Not Accessible

```bash
# Check ingress
kubectl get ingress -n celery
kubectl describe ingress celery-flower -n celery

# Check TLS secret
kubectl get secret stratdata-wildcard-tls -n celery

# Check DNS
nslookup flower.stratdata.org
# Should return: 192.168.1.240

# Test direct pod access
kubectl port-forward -n celery deployment/celery-flower 5555:5555
# Visit http://localhost:5555
```

### High Memory Usage

```bash
# Check current usage
kubectl top pods -n celery
kubectl top pods -n redis

# Reduce worker concurrency
kubectl edit deployment celery-worker -n celery
# Change: --concurrency=1

# Reduce max tasks per child
# Edit ConfigMap: worker_max_tasks_per_child=100
```

### Beat Not Scheduling Tasks

```bash
# Check Beat logs
kubectl logs -n celery -l component=beat

# Ensure only 1 Beat replica
kubectl get deployment celery-beat -n celery
# Should show: 1/1

# Restart Beat
kubectl rollout restart deployment/celery-beat -n celery
```

### Beat: Read-only Filesystem Error

**Symptom:** Beat crashes with `OSError: [Errno 30] Read-only file system: 'celerybeat-schedule'`

**Cause:** Beat needs to write its schedule database, but the default `/app` directory is mounted from a ConfigMap (read-only).

**Solution:** Already fixed in deployment files. Beat uses:
- Schedule file at: `-s /app/data/celerybeat-schedule`
- Writable volume: `emptyDir` mounted at `/app/data`

If you see this error, verify the deployment has the `beat-data` volume:
```bash
kubectl get deployment celery-beat -n celery -o yaml | grep -A 5 volumes
```

### Flower Keeps Restarting

**Symptom:** Flower pod shows `CrashLoopBackOff` or frequent restarts

**Cause:** Readiness probe failing during pip install phase (takes 30-60 seconds)

**Solution:** Already fixed in deployment files. Flower now has:
- Liveness probe only (no readiness probe)
- 60s initial delay for liveness probe
- Allows time for pip install to complete

### Dependency Conflict Error

**Symptom:** Workers fail with `ERROR: Cannot install celery[redis]==5.3.4 and redis==5.0.1`

**Cause:** Celery 5.3.4 requires `redis<5.0.0` but we specified `redis==5.0.1`

**Solution:** Already fixed. Use `celery[redis]==5.3.4` only (includes compatible redis version):
```bash
pip install --no-cache-dir celery[redis]==5.3.4
# Do NOT specify redis version separately
```

## Backup & Recovery

### Backup Redis Data

```bash
# Manual backup
kubectl exec -n redis deployment/redis -- redis-cli BGSAVE

# Download RDB file
kubectl cp redis/redis-<pod-name>:/data/dump.rdb ./redis-backup.rdb

# Or use Velero for full namespace backup
velero backup create redis-backup --include-namespaces redis
velero backup create celery-backup --include-namespaces celery
```

### Restore Redis Data

```bash
# Stop Celery workers
kubectl scale deployment celery-worker -n celery --replicas=0

# Upload RDB file
kubectl cp ./redis-backup.rdb redis/redis-<pod-name>:/data/dump.rdb

# Restart Redis
kubectl rollout restart deployment/redis -n redis

# Start workers
kubectl scale deployment celery-worker -n celery --replicas=2
```

## Security

### Change Flower Password

```bash
# Edit deployment
kubectl edit deployment celery-flower -n celery

# Change: --basic-auth=admin:NEWPASSWORD

# Or update the playbook and redeploy
vim ansible/playbooks/celery-install.yml
ansible-playbook ansible/playbooks/celery-install.yml
```

### Secure Redis

For production, add Redis password:

```bash
# Edit Redis ConfigMap
kubectl edit configmap redis-config -n redis

# Add: requirepass yourpassword

# Restart Redis
kubectl rollout restart deployment/redis -n redis

# Update Celery broker URL
kubectl edit configmap celery-app -n celery
# Change: redis://redis.redis.svc.cluster.local:6379/0
# To: redis://:yourpassword@redis.redis.svc.cluster.local:6379/0
```

## Performance Tuning

### For High Throughput

```yaml
# Increase workers and concurrency
celery_workers: 4
celery_concurrency: 4

# Increase Redis memory
redis_memory_limit: "1Gi"

# Disable task result storage if not needed
result_backend: None
task_ignore_result: True
```

### For Long-Running Tasks

```yaml
# Reduce concurrency, increase timeout
celery_concurrency: 1
task_time_limit: 3600  # 1 hour

# Increase worker memory
memory_limit: "1Gi"
```

## Maintenance

### Update Celery Version

```bash
# Edit playbook
vim ansible/playbooks/celery-install.yml

# Change: celery[redis]==5.4.0

# Redeploy
ansible-playbook ansible/playbooks/celery-install.yml
```

### Clean Up Old Results

Execute cleanup task manually:

```bash
kubectl exec -n celery -it deployment/celery-worker -- \
  python -c "from tasks import cleanup_old_results; cleanup_old_results.delay()"
```

Or configure shorter result expiry:

```python
app.conf.result_expires = 3600  # 1 hour
```

## Uninstallation

```bash
# Remove Celery
kubectl delete namespace celery

# Remove Redis (careful - other apps may use it!)
kubectl delete namespace redis

# Remove DNS entry
ansible-playbook ansible/playbooks/infrastructure/update-pihole-dns.yml
```

## Integration Examples

### Airflow Integration

```python
# In Airflow DAG
from airflow.operators.python import PythonOperator
from celery import Celery

celery_app = Celery(broker='redis://redis.redis.svc.cluster.local:6379/0')

def trigger_celery_task():
    from tasks import process_data
    result = process_data.delay(data="airflow-data")
    return result.get()

task = PythonOperator(
    task_id='celery_task',
    python_callable=trigger_celery_task,
)
```

### Python Application

```python
from celery import Celery

app = Celery('myapp',
             broker='redis://redis.redis.svc.cluster.local:6379/0',
             backend='redis://redis.redis.svc.cluster.local:6379/0')

# Import tasks
from tasks import add

# Execute task
result = add.delay(4, 4)
print(f"Result: {result.get()}")
```

## References

- **Celery Documentation**: https://docs.celeryq.dev/
- **Redis Documentation**: https://redis.io/docs/
- **Flower Documentation**: https://flower.readthedocs.io/
- **Ansible Playbooks**: [ansible/playbooks/README.md](../../ansible/playbooks/README.md)

## Support

For issues:
1. Check logs: `kubectl logs -n celery -l component=worker`
2. Check Flower UI: https://flower.stratdata.org
3. Review this guide
4. Check [Ansible Guide](../operations/ansible-guide.md)

---

**Last Updated**: October 2025
**Cluster Version**: K3s v1.x
**Celery Version**: 5.3.4
**Redis Version**: 7-alpine
