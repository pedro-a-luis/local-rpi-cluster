# Cluster Shutdown & Startup Guide

**Last Updated**: October 19, 2025
**Cluster**: 8-node Raspberry Pi 5 K3s Cluster

---

## Overview

This guide covers safe shutdown and startup procedures for the entire K3s cluster. These procedures ensure data integrity and prevent corruption during power events or maintenance.

**Use Cases**:
- Planned maintenance
- Power outages (UPS battery running low)
- Hardware upgrades
- Cluster relocation
- Extended periods of non-use

---

## Quick Reference

### Shutdown Cluster

```bash
# Using shell script (recommended)
cd /root/gitlab/local-rpi-cluster
./scripts/cluster-shutdown.sh

# Using Ansible
ansible-playbook ansible/playbooks/cluster-shutdown.yml

# Force shutdown (skip confirmation)
./scripts/cluster-shutdown.sh --force
```

### Startup Cluster

```bash
# Using shell script (recommended)
cd /root/gitlab/local-rpi-cluster
./scripts/cluster-startup.sh

# Using Ansible
ansible-playbook ansible/playbooks/cluster-startup.yml

# Skip health checks
./scripts/cluster-startup.sh --skip-health-check
```

---

## Shutdown Procedure

### Method 1: Shell Script (Recommended)

**Location**: `scripts/cluster-shutdown.sh`

**Features**:
- Pre-shutdown backups (etcd snapshot + Velero)
- Graceful pod eviction
- Orderly node shutdown
- Detailed logging
- Interactive confirmation

**Steps**:

```bash
# 1. Navigate to project directory
cd /root/gitlab/local-rpi-cluster

# 2. Run shutdown script
./scripts/cluster-shutdown.sh

# 3. Confirm when prompted
# Type 'yes' to proceed

# 4. Monitor progress
# The script will show detailed progress for each step

# 5. Wait for completion
# All nodes will shutdown automatically
```

**What Happens**:

1. **Backup Creation** (2-5 minutes):
   - etcd snapshot saved
   - Velero full cluster backup initiated

2. **Node Cordoning** (30 seconds):
   - All nodes marked unschedulable
   - Prevents new pod scheduling

3. **Worker Draining** (5-10 minutes):
   - Pods gracefully evicted from workers
   - Pods migrate to master temporarily
   - Respects PodDisruptionBudgets

4. **K3s Agent Shutdown** (1 minute):
   - K3s agents stopped on all workers

5. **K3s Server Shutdown** (30 seconds):
   - K3s server stopped on master

6. **Node Shutdown** (2 minutes):
   - Workers shutdown sequentially
   - Master shuts down last (30 second warning)

**Total Time**: 10-20 minutes (depends on pod count)

**Logs**: `/var/log/cluster-shutdown/shutdown-YYYYMMDD-HHMMSS.log`

### Method 2: Ansible Playbook

**Location**: `ansible/playbooks/cluster-shutdown.yml`

**Prerequisites**:
- Ansible inventory configured
- SSH keys in place

**Steps**:

```bash
# Run from local-rpi-cluster directory
ansible-playbook ansible/playbooks/cluster-shutdown.yml

# With extra verbosity
ansible-playbook ansible/playbooks/cluster-shutdown.yml -vv
```

**Features**:
- Same functionality as shell script
- Better for automation/CI/CD
- Idempotent operations

### Manual Shutdown (Emergency)

If scripts fail, follow these steps:

```bash
# 1. SSH to master
ssh -i ~/.ssh/pi_cluster admin@192.168.1.240

# 2. Cordon nodes
kubectl cordon pi-master
kubectl cordon pi-worker-01 pi-worker-02 pi-worker-03 pi-worker-04 pi-worker-05 pi-worker-06 pi-worker-07

# 3. Drain workers (one at a time)
kubectl drain pi-worker-01 --ignore-daemonsets --delete-emptydir-data --timeout=300s --force

# 4. SSH to each worker and shutdown
ssh admin@192.168.1.241 'sudo shutdown -h now'

# 5. Stop K3s on master
sudo systemctl stop k3s

# 6. Shutdown master
sudo shutdown -h now
```

---

## Startup Procedure

### Method 1: Shell Script (Recommended)

**Location**: `scripts/cluster-startup.sh`

**Features**:
- Automatic SSH connectivity checks
- Sequential node startup
- Health verification
- Smoke tests
- Detailed logging

**Steps**:

```bash
# 1. Ensure all nodes are powered on
# Either manually or via network power management

# 2. Navigate to project directory
cd /root/gitlab/local-rpi-cluster

# 3. Run startup script
./scripts/cluster-startup.sh

# 4. Wait for master to initialize
# Script will wait up to 2 minutes for master

# 5. Workers join automatically
# Each worker waits 1 minute to join

# 6. Review health check
# Script shows comprehensive cluster status

# 7. Run smoke tests (optional)
# Answer 'y' when prompted
```

**What Happens**:

1. **Master Node Check** (1-3 minutes):
   - Ping master node
   - Wait for SSH availability
   - Start K3s server
   - Wait for API server ready

2. **Worker Nodes** (1-2 minutes per worker):
   - Check each worker is online
   - Start K3s agent
   - Verify node joins cluster
   - Check node becomes Ready

3. **Node Uncordoning** (30 seconds):
   - Uncordon all nodes
   - Allow pod scheduling

4. **Pod Stabilization** (60 seconds):
   - Wait for pods to start
   - DaemonSets deploy to all nodes

5. **Health Verification** (2-3 minutes):
   - Check all nodes Ready
   - Verify system pods running
   - Check Longhorn storage
   - Verify Velero backup location
   - Check critical namespaces

6. **Smoke Tests** (optional, 1 minute):
   - Create test pod
   - Test DNS resolution
   - Cleanup test resources

**Total Time**: 10-20 minutes

**Logs**: `/var/log/cluster-startup/startup-YYYYMMDD-HHMMSS.log`

### Method 2: Ansible Playbook

**Location**: `ansible/playbooks/cluster-startup.yml`

**Steps**:

```bash
# Run from local-rpi-cluster directory
ansible-playbook ansible/playbooks/cluster-startup.yml

# With extra verbosity
ansible-playbook ansible/playbooks/cluster-startup.yml -vv
```

### Manual Startup (Emergency)

If scripts fail:

```bash
# 1. Power on all nodes
# Manually or via network management

# 2. Wait for master to boot (2-3 minutes)
ping 192.168.1.240

# 3. SSH to master
ssh -i ~/.ssh/pi_cluster admin@192.168.1.240

# 4. Start K3s server
sudo systemctl start k3s

# 5. Wait for API server
kubectl get nodes

# 6. Start each worker
for ip in 241 242 243 244 245 246 247; do
    ssh admin@192.168.1.$ip 'sudo systemctl start k3s-agent'
done

# 7. Uncordon nodes
kubectl uncordon --all

# 8. Verify
kubectl get nodes
kubectl get pods -A
```

---

## Common Scenarios

### Scenario 1: Planned Maintenance

**Use Case**: Upgrading cluster hardware, data center maintenance

```bash
# 1. Notify users of downtime window

# 2. Run shutdown script
./scripts/cluster-shutdown.sh

# 3. Perform maintenance

# 4. Run startup script
./scripts/cluster-startup.sh

# 5. Verify all services
kubectl get pods -A
```

### Scenario 2: Power Outage (UPS Running Low)

**Use Case**: UPS battery at 10%, need emergency shutdown

```bash
# Quick shutdown (skip backups if needed)
ssh admin@192.168.1.240 'sudo shutdown -h now' &
ssh admin@192.168.1.241 'sudo shutdown -h now' &
ssh admin@192.168.1.242 'sudo shutdown -h now' &
# ... continue for all nodes

# Or use script with force flag
./scripts/cluster-shutdown.sh --force
```

### Scenario 3: Single Node Reboot

**Use Case**: Rebooting one worker for OS updates

```bash
# 1. Cordon node
kubectl cordon pi-worker-03

# 2. Drain node
kubectl drain pi-worker-03 --ignore-daemonsets --delete-emptydir-data

# 3. Reboot node
ssh admin@192.168.1.243 'sudo reboot'

# 4. Wait for node to come back
# (about 2 minutes)

# 5. Uncordon node
kubectl uncordon pi-worker-03

# 6. Verify
kubectl get nodes
```

### Scenario 4: Master Node Reboot

**Use Case**: Master node kernel update

**WARNING**: Master reboot causes cluster downtime!

```bash
# 1. Drain master (if it has workloads)
kubectl drain pi-master --ignore-daemonsets --delete-emptydir-data

# 2. Reboot master
ssh admin@192.168.1.240 'sudo reboot'

# 3. Wait for master (3-5 minutes)
# K3s server starts automatically

# 4. Verify cluster
kubectl get nodes

# 5. Uncordon if needed
kubectl uncordon pi-master
```

---

## Health Checks

### Post-Startup Verification

```bash
# 1. Check all nodes are Ready
kubectl get nodes

# Expected: All nodes STATUS=Ready

# 2. Check system pods
kubectl get pods -n kube-system

# Expected: All pods Running

# 3. Check Longhorn
kubectl get pods -n longhorn-system

# Expected: All manager, CSI, instance-manager pods Running

# 4. Check monitoring
kubectl get pods -n monitoring

# Expected: Prometheus, Grafana, Alertmanager Running

# 5. Check Velero
kubectl get pods -n velero
velero backup-location get

# Expected: Velero and node-agent pods Running, backup location Available

# 6. Test service access
curl -k https://grafana.stratdata.org
curl -k https://longhorn.stratdata.org

# Expected: HTTP 200 or 302 responses
```

### Critical Service Checklist

After startup, verify these services:

- [ ] **Kubernetes API**: `kubectl get nodes`
- [ ] **Longhorn Storage**: All nodes Ready
- [ ] **Grafana**: https://grafana.stratdata.org accessible
- [ ] **Prometheus**: Metrics collecting
- [ ] **Loki**: Logs aggregating
- [ ] **PostgreSQL**: Database pods running
- [ ] **MinIO**: Backup storage accessible
- [ ] **Velero**: Backup location Available

---

## Troubleshooting

### Shutdown Issues

#### Problem: Pods won't drain

```bash
# Check what's blocking
kubectl get pods -A | grep -v Running

# Force delete stuck pods
kubectl delete pod <pod-name> -n <namespace> --force --grace-period=0

# Continue with drain
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --force
```

#### Problem: Node won't shutdown

```bash
# SSH to node
ssh admin@<node-ip>

# Check systemd
sudo systemctl status k3s-agent  # or k3s for master

# Force stop if needed
sudo systemctl stop k3s-agent --force

# Force shutdown
sudo shutdown -h now

# Or hard power cycle as last resort
```

#### Problem: Backup fails during shutdown

```bash
# Skip backup and continue
# Edit script and set: BACKUP_BEFORE_SHUTDOWN=false

# Or manually backup later
velero backup create manual-backup --wait
```

### Startup Issues

#### Problem: Master K3s won't start

```bash
# SSH to master
ssh admin@192.168.1.240

# Check logs
sudo journalctl -u k3s -f

# Common fixes:
# 1. Check disk space
df -h /var/lib/rancher/k3s

# 2. Check etcd integrity
sudo k3s check-config

# 3. Restore from etcd snapshot if needed
sudo systemctl stop k3s
sudo k3s server --cluster-reset --cluster-reset-restore-path=/var/lib/rancher/k3s/server/db/snapshots/<snapshot-file>
sudo systemctl start k3s
```

#### Problem: Worker won't join cluster

```bash
# SSH to worker
ssh admin@<worker-ip>

# Check agent logs
sudo journalctl -u k3s-agent -f

# Common fixes:
# 1. Verify master is reachable
ping 192.168.1.240

# 2. Check token
sudo cat /var/lib/rancher/k3s/agent/node-password.crypt

# 3. Restart agent
sudo systemctl restart k3s-agent

# 4. Re-register if needed
sudo systemctl stop k3s-agent
sudo rm -rf /var/lib/rancher/k3s/agent
sudo systemctl start k3s-agent
```

#### Problem: Nodes stuck in NotReady

```bash
# Check node conditions
kubectl describe node <node-name>

# Common causes:
# 1. CNI (Flannel) not running
kubectl get pods -n kube-system | grep flannel

# 2. Kubelet not ready
ssh admin@<node-ip> 'sudo systemctl status kubelet'

# 3. Disk pressure
ssh admin@<node-ip> 'df -h'

# Fix: Usually resolves after 2-3 minutes, if not restart node
```

#### Problem: Pods stuck in Pending

```bash
# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Common causes:
# 1. Longhorn not ready yet - wait 2-3 minutes
kubectl get pods -n longhorn-system

# 2. PVC issues
kubectl get pvc -A

# 3. Resource constraints
kubectl top nodes
```

---

## Emergency Procedures

### Full Cluster Restore from Backup

If cluster is completely broken:

```bash
# 1. Fresh K3s install on master
curl -sfL https://get.k3s.io | sh -

# 2. Install Velero
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.10.0 \
  --bucket velero-backups \
  --secret-file ./credentials-velero \
  --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://minio.velero.svc:9000

# 3. List available backups
velero backup get

# 4. Restore latest backup
velero restore create cluster-recovery \
  --from-backup <latest-backup-name>

# 5. Monitor restore
velero restore describe cluster-recovery

# 6. Verify cluster
kubectl get all -A
```

### etcd Restore (Master Corruption)

If etcd database is corrupted:

```bash
# 1. Stop K3s
sudo systemctl stop k3s

# 2. List snapshots
sudo ls -lh /var/lib/rancher/k3s/server/db/snapshots/

# 3. Restore from snapshot
sudo k3s server \
  --cluster-reset \
  --cluster-reset-restore-path=/var/lib/rancher/k3s/server/db/snapshots/<snapshot-file>

# 4. Start K3s
sudo systemctl start k3s

# 5. Verify
kubectl get nodes
```

---

## Best Practices

### Before Shutdown

- ✅ Notify all users of downtime window
- ✅ Create fresh Velero backup
- ✅ Create etcd snapshot
- ✅ Document any ongoing incidents
- ✅ Verify backup storage has sufficient space
- ✅ Check UPS battery level

### During Shutdown

- ✅ Monitor logs for errors
- ✅ Ensure proper drain sequence (workers first, master last)
- ✅ Wait for pod migrations to complete
- ✅ Don't force shutdown unless necessary

### After Startup

- ✅ Verify all nodes Ready
- ✅ Check all critical services
- ✅ Review pod status across all namespaces
- ✅ Test service endpoints
- ✅ Check Grafana dashboards
- ✅ Verify Velero backup location
- ✅ Run smoke tests

### Regular Testing

- Test shutdown/startup monthly during maintenance windows
- Practice emergency procedures quarterly
- Update runbooks based on lessons learned
- Document any issues encountered

---

## Automation & Scheduling

### Scheduled Maintenance Windows

Create a cron job for planned weekly restarts (optional):

```bash
# Weekly restart - Sunday 3 AM
0 3 * * 0 /root/gitlab/local-rpi-cluster/scripts/cluster-shutdown.sh --force
30 3 * * 0 # Manual power-on or WOL
0 4 * * 0 /root/gitlab/local-rpi-cluster/scripts/cluster-startup.sh --skip-health-check
```

### Integration with UPS

If using a UPS with network management:

```bash
# Add to UPS shutdown script
UPS_BATTERY_LOW_THRESHOLD=15

if [ $UPS_BATTERY -lt $UPS_BATTERY_LOW_THRESHOLD ]; then
    /root/gitlab/local-rpi-cluster/scripts/cluster-shutdown.sh --force
fi
```

---

## Related Documentation

- [BACKUP-GUIDE.md](BACKUP-GUIDE.md) - Backup and recovery procedures
- [README.md](README.md) - Main cluster documentation
- [IMPROVEMENTS-ROADMAP.md](IMPROVEMENTS-ROADMAP.md) - Infrastructure improvements
- [cluster-access-guide.md](cluster-access-guide.md) - Service access and credentials

---

## Scripts Reference

### Shell Scripts

| Script | Location | Purpose |
|--------|----------|---------|
| cluster-shutdown.sh | `scripts/cluster-shutdown.sh` | Graceful cluster shutdown |
| cluster-startup.sh | `scripts/cluster-startup.sh` | Cluster initialization and health check |

### Ansible Playbooks

| Playbook | Location | Purpose |
|----------|----------|---------|
| cluster-shutdown.yml | `ansible/playbooks/cluster-shutdown.yml` | Automated shutdown via Ansible |
| cluster-startup.yml | `ansible/playbooks/cluster-startup.yml` | Automated startup via Ansible |

---

**Maintained By**: Admin
**Review Frequency**: Quarterly
**Last Review**: October 19, 2025
**Last Test**: TBD (test during next maintenance window)
