# Celery & Redis Quick Start Guide

Quick deployment guide for Redis and Celery on your Raspberry Pi K3s cluster.

## TL;DR - Quick Deploy

SSH to your pi-master and run:

```bash
# SSH to pi-master
ssh -i ~/.ssh/pi_cluster admin@192.168.1.240

# Clone or pull latest code
cd ~/
git clone <your-repo-url> local-rpi-cluster || (cd local-rpi-cluster && git pull)
cd local-rpi-cluster

# Deploy Redis (message broker)
bash scripts/deployment/deploy-redis.sh

# Deploy Celery (task queue + monitoring)
bash scripts/deployment/deploy-celery.sh

# Add DNS entry for Flower UI
# On Pi-hole (192.168.1.25):
ssh admin@192.168.1.25
echo "192.168.1.240 flower.stratdata.org" | sudo tee -a /etc/pihole/custom.list
sudo pihole restartdns

# Access Flower
# https://flower.stratdata.org (admin/flower123)
```

## What Gets Installed

### Redis (Shared Service)
- **Namespace**: `redis`
- **Purpose**: Message broker and result backend for Celery (and other apps)
- **Storage**: 5Gi Longhorn persistent volume
- **Access**: `redis://redis.redis.svc.cluster.local:6379/0`

### Celery (Distributed Task Queue)
- **Namespace**: `celery`
- **Components**:
  - **2x Workers**: Execute tasks (2 concurrency each = 4 parallel tasks)
  - **1x Beat**: Periodic task scheduler (with writable emptyDir volume for schedule database)
  - **1x Flower**: Web monitoring UI at https://flower.stratdata.org

**Note:** Deployment includes fixes for:
- ✅ Dependency conflicts (uses `celery[redis]==5.3.4` without separate redis version)
- ✅ Beat read-only filesystem (schedule file stored in `/app/data` emptyDir volume)
- ✅ Flower startup delays (60s liveness probe, no readiness probe)

## Deployment Methods

### Method 1: Deployment Scripts (Recommended)

**On pi-master:**
```bash
ssh -i ~/.ssh/pi_cluster admin@192.168.1.240
cd ~/local-rpi-cluster

# Deploy Redis first
bash scripts/deployment/deploy-redis.sh

# Then deploy Celery
bash scripts/deployment/deploy-celery.sh
```

**Advantages:**
- Simple one-command deployment
- Built-in verification checks
- Clear status output

### Method 2: Ansible Playbooks

**From any machine with ansible and kubectl:**
```bash
cd ~/gitlab/local-rpi-cluster

# Deploy Redis
ansible-playbook ansible/playbooks/redis-install.yml

# Deploy Celery
ansible-playbook ansible/playbooks/celery-install.yml
```

**Requirements:**
- Ansible installed (`apt install ansible`)
- kubectl configured to access cluster
- sshpass installed (`apt install sshpass`)

### Method 3: Manual kubectl

**On pi-master:**
```bash
# Apply manifests directly
kubectl apply -f kubernetes/redis/redis-deployment.yaml
kubectl apply -f kubernetes/celery/celery-deployment.yaml
```

## Post-Deployment Setup

### 1. Add DNS Entry

**Option A: Using Ansible (recommended)**
```bash
cd ~/gitlab/local-rpi-cluster

# Edit the DNS playbook
vim ansible/playbooks/infrastructure/update-pihole-dns.yml

# Add to stratdata_services:
#   - { name: "flower", ip: "192.168.1.240" }

# Run the playbook
ansible-playbook ansible/playbooks/infrastructure/update-pihole-dns.yml
```

**Option B: Manual Pi-hole**
```bash
# SSH to primary Pi-hole
ssh admin@192.168.1.25

# Add DNS entry
echo "192.168.1.240 flower.stratdata.org" | sudo tee -a /etc/pihole/custom.list
sudo pihole restartdns

# Verify
nslookup flower.stratdata.org
```

### 2. Access Flower UI

1. Open https://flower.stratdata.org
2. Login: `admin` / `flower123`
3. You should see:
   - 2 active workers
   - Periodic "hello" tasks running every minute
   - Task statistics and history

### 3. Test Celery Tasks

**From any pod with Python:**
```bash
# Create test pod
kubectl run celery-test --rm -i --tty --image=python:3.11-slim -n celery -- bash

# Install celery
pip install celery[redis] redis

# Create test script
cat > test_tasks.py <<EOF
from celery import Celery

app = Celery('test',
             broker='redis://redis.redis.svc.cluster.local:6379/0',
             backend='redis://redis.redis.svc.cluster.local:6379/0')

# Import tasks from workers
from tasks import add, multiply, long_running

# Test simple task
result = add.delay(4, 4)
print(f"4 + 4 = {result.get()}")

# Test another task
result = multiply.delay(3, 7)
print(f"3 * 7 = {result.get()}")

# Test long-running task
print("Starting 10-second task...")
result = long_running.delay(10)
print(result.get())
EOF

python test_tasks.py
```

## Verification Checklist

Run these commands to verify everything is working:

```bash
# Check all pods are running
kubectl get pods -n redis
kubectl get pods -n celery

# Should see:
# redis/redis-xxx              1/1 Running
# celery/celery-worker-xxx     1/1 Running (2 pods)
# celery/celery-beat-xxx       1/1 Running
# celery/celery-flower-xxx     1/1 Running

# Check services
kubectl get svc -n redis
kubectl get svc -n celery

# Check ingress
kubectl get ingress -n celery

# Test Redis connection
kubectl run redis-test --rm -i --restart=Never --image=redis:7-alpine -n redis -- \
  redis-cli -h redis.redis.svc.cluster.local ping
# Should output: PONG

# View worker logs
kubectl logs -n celery -l component=worker --tail=20

# View beat scheduler logs
kubectl logs -n celery -l component=beat --tail=20

# View Flower logs
kubectl logs -n celery -l component=flower --tail=20
```

## Common Tasks

### View Logs
```bash
# Worker logs
kubectl logs -n celery -l component=worker -f

# Beat scheduler logs
kubectl logs -n celery -l component=beat -f

# Flower monitoring logs
kubectl logs -n celery -l component=flower -f

# Redis logs
kubectl logs -n redis -l app=redis -f
```

### Scale Workers
```bash
# Scale to 4 workers
kubectl scale deployment celery-worker -n celery --replicas=4

# Verify
kubectl get pods -n celery -l component=worker
```

### Update Tasks
```bash
# Edit the ConfigMap
kubectl edit configmap celery-app -n celery

# Restart workers to load new tasks
kubectl rollout restart deployment/celery-worker -n celery
kubectl rollout restart deployment/celery-beat -n celery
```

### Restart Services
```bash
# Restart Redis
kubectl rollout restart deployment/redis -n redis

# Restart all Celery components
kubectl rollout restart deployment -n celery
```

## Resource Usage

**Redis:**
- Memory: 256Mi request, 512Mi limit
- CPU: 100m request, 500m limit
- Storage: 5Gi persistent volume

**Celery Workers (per pod):**
- Memory: 256Mi request, 512Mi limit
- CPU: 200m request, 1000m limit

**Celery Beat:**
- Memory: 128Mi request, 256Mi limit
- CPU: 100m request, 500m limit

**Celery Flower:**
- Memory: 128Mi request, 256Mi limit
- CPU: 100m request, 500m limit

**Total Resource Usage:**
- Memory: ~1.25Gi total
- CPU: ~2.1 cores max
- Storage: 5Gi

## Troubleshooting

### Workers not connecting to Redis
```bash
# Check Redis is running
kubectl get pods -n redis

# Test Redis from celery namespace
kubectl run redis-test --rm -i --restart=Never --image=redis:7-alpine -n celery -- \
  redis-cli -h redis.redis.svc.cluster.local ping

# Check worker logs
kubectl logs -n celery -l component=worker
```

### Flower not accessible
```bash
# Check Flower pod
kubectl get pods -n celery -l component=flower

# Check ingress
kubectl describe ingress celery-flower -n celery

# Check TLS secret
kubectl get secret stratdata-wildcard-tls -n celery

# Test direct access
kubectl port-forward -n celery deployment/celery-flower 5555:5555
# Visit http://localhost:5555
```

### Tasks not executing
```bash
# Check worker status in Flower
# https://flower.stratdata.org

# Check worker logs
kubectl logs -n celery -l component=worker --tail=100

# Check if workers are registered
kubectl exec -n celery -it deployment/celery-worker -- \
  celery -A tasks inspect active

# Check Redis queue
kubectl exec -n redis -it deployment/redis -- redis-cli llen celery
```

## Next Steps

1. **Customize Tasks**: Replace the example tasks in the ConfigMap with your own
2. **Integrate with Airflow**: Use Celery for Airflow task execution
3. **Add Monitoring**: Create Grafana dashboards for Celery metrics
4. **Production Hardening**: Add Redis password, increase resources as needed

## Documentation

- **Full Guide**: [docs/deployment/celery.md](docs/deployment/celery.md)
- **Ansible Playbooks**: [ansible/playbooks/redis-install.yml](ansible/playbooks/redis-install.yml), [ansible/playbooks/celery-install.yml](ansible/playbooks/celery-install.yml)
- **Deployment Scripts**: [scripts/deployment/](scripts/deployment/)

## Support

Issues? Check:
1. Pod status: `kubectl get pods -n redis -n celery`
2. Logs: `kubectl logs -n celery -l component=worker`
3. Flower UI: https://flower.stratdata.org
4. Full documentation: [docs/deployment/celery.md](docs/deployment/celery.md)

---

**Quick Reference:**
- **Flower UI**: https://flower.stratdata.org (admin/flower123)
- **Redis**: `redis://redis.redis.svc.cluster.local:6379/0`
- **Namespaces**: `redis`, `celery`
- **Workers**: 2 replicas, 2 concurrency = 4 parallel tasks
