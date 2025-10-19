# Backup & Disaster Recovery Guide

**Last Updated**: October 19, 2025
**Backup Solution**: Velero + MinIO
**Cluster**: 8-node Raspberry Pi 5 K3s Cluster

---

## Overview

This cluster uses a comprehensive backup strategy:
- **Velero**: Kubernetes resource and volume backups
- **MinIO**: S3-compatible object storage backend (500GB NFS)
- **K3s etcd snapshots**: Cluster state backups (every 6 hours)
- **Automated schedules**: Daily and weekly backups

---

## Backup Infrastructure

### MinIO S3-Compatible Storage

**Deployment Details**:
- **Namespace**: `velero`
- **Storage**: 500Gi NFS (`nfs-client` storage class)
- **Access**:
  - API: `http://minio.velero.svc.cluster.local:9000`
  - Console (internal): `http://minio-console.velero.svc.cluster.local:9001`
  - Console (external): https://minio-console.stratdata.org
- **Credentials**:
  - Username: `minioadmin`
  - Password: `minioadmin123`

**Buckets**:
- `velero-backups`: Kubernetes backups
- `loki-data`: Loki logs storage (for future use)
- `tempo-data`: Tempo traces storage (for future use)
- `thanos-data`: Thanos metrics storage (for future use)

### Velero Backup System

**Deployment Details**:
- **Version**: v1.17.0
- **Namespace**: `velero`
- **Components**:
  - Velero server: 1 pod
  - Node-agent DaemonSet: 8 pods (one per node)
- **Backup Method**: Filesystem backups via node-agent (restic/kopia)
- **Storage Location**: MinIO (S3-compatible)

**Resources**:
- Velero server: 100m CPU / 128Mi memory (request), 500m CPU / 512Mi memory (limit)
- Node-agent per node: 100m CPU / 128Mi memory (request), 500m CPU / 512Mi memory (limit)

---

## Backup Schedules

### Daily Backup

**Schedule**: `0 2 * * *` (2 AM daily)

```bash
Namespaces:
  Included: All namespaces
  Excluded: kube-system, kube-public, kube-node-lease, velero
Retention: 30 days (720 hours)
Volumes: Filesystem backup enabled
Snapshots: Disabled
```

**What's backed up**:
- All application namespaces (monitoring, logging, databases, dev-tools, etc.)
- Kubernetes resources (deployments, services, configmaps, secrets, etc.)
- Persistent volume data (via filesystem backup)

**What's NOT backed up**:
- kube-system namespace (covered by weekly backup)
- Velero itself
- Node-level configuration

### Weekly Full Backup

**Schedule**: `0 3 * * 0` (3 AM every Sunday)

```bash
Namespaces:
  Included: All namespaces (including kube-system)
  Excluded: None
Retention: 90 days (2160 hours)
Volumes: Filesystem backup enabled
Snapshots: Disabled
```

**What's backed up**:
- Everything in the cluster
- kube-system namespace
- Complete cluster state

---

## Common Operations

### List Backups

```bash
# List all backups
velero backup get

# Describe a specific backup
velero backup describe <backup-name>

# Get backup logs
velero backup logs <backup-name>
```

### Create Manual Backup

```bash
# Backup specific namespace
velero backup create my-backup --include-namespaces databases

# Backup entire cluster
velero backup create full-backup --include-namespaces "*"

# Backup with volume snapshots
velero backup create vol-backup \
  --include-namespaces databases \
  --default-volumes-to-fs-backup

# Wait for backup to complete
velero backup create my-backup --wait
```

### Restore from Backup

```bash
# List available backups
velero backup get

# Restore entire backup
velero restore create --from-backup <backup-name>

# Restore specific namespace only
velero restore create --from-backup <backup-name> \
  --include-namespaces databases

# Restore to different namespace
velero restore create --from-backup <backup-name> \
  --namespace-mappings old-namespace:new-namespace

# Monitor restore progress
velero restore describe <restore-name>
velero restore logs <restore-name>
```

### Delete Backups

```bash
# Delete specific backup
velero backup delete <backup-name>

# Delete multiple backups
velero backup delete backup1 backup2 backup3

# Delete with confirmation
velero backup delete <backup-name> --confirm
```

### Manage Schedules

```bash
# List schedules
velero schedule get

# Describe schedule
velero schedule describe daily-backup

# Pause schedule
velero schedule pause daily-backup

# Resume schedule
velero schedule resume daily-backup

# Delete schedule
velero schedule delete daily-backup
```

---

## K3s etcd Snapshots

### Configuration

K3s etcd snapshots are configured in `/etc/rancher/k3s/config.yaml`:

```yaml
etcd-snapshot-schedule-cron: "0 */6 * * *"  # Every 6 hours
etcd-snapshot-retention: 48                  # Keep 48 snapshots (12 days)
etcd-snapshot-dir: /var/lib/rancher/k3s/server/db/snapshots
```

**Note**: K3s must be restarted for these settings to take effect.

### Manage etcd Snapshots

```bash
# List etcd snapshots (on pi-master)
sudo ls -lh /var/lib/rancher/k3s/server/db/snapshots/

# Create manual etcd snapshot
sudo k3s etcd-snapshot save --name manual-snapshot

# Restore from etcd snapshot (DANGEROUS - use with caution)
sudo systemctl stop k3s
sudo k3s server --cluster-reset --cluster-reset-restore-path=/var/lib/rancher/k3s/server/db/snapshots/<snapshot-name>
sudo systemctl start k3s
```

**WARNING**: etcd restore is a destructive operation. Only use during disaster recovery.

---

## Disaster Recovery Scenarios

### Scenario 1: Accidental Namespace Deletion

```bash
# 1. Find the most recent backup
velero backup get

# 2. Restore the deleted namespace
velero restore create --from-backup <backup-name> \
  --include-namespaces <deleted-namespace>

# 3. Monitor restore
velero restore describe <restore-name>

# 4. Verify resources
kubectl get all -n <deleted-namespace>
```

### Scenario 2: Corrupted Application

```bash
# 1. Delete the corrupted resources
kubectl delete namespace <app-namespace>

# 2. Wait for full deletion
kubectl get namespace <app-namespace>

# 3. Restore from known good backup
velero restore create --from-backup <backup-name> \
  --include-namespaces <app-namespace>

# 4. Verify application
kubectl get pods -n <app-namespace>
```

### Scenario 3: Full Cluster Recovery

**Prerequisites**: New K3s cluster installed

```bash
# 1. Install Velero on new cluster with same MinIO backend
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.10.0 \
  --bucket velero-backups \
  --secret-file ./credentials-velero \
  --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://minio.velero.svc:9000 \
  --use-node-agent

# 2. Verify backup location is available
velero backup-location get

# 3. List available backups
velero backup get

# 4. Restore latest full backup
velero restore create cluster-recovery \
  --from-backup weekly-full-backup-<date>

# 5. Monitor restoration
velero restore describe cluster-recovery

# 6. Verify all namespaces and resources
kubectl get namespaces
kubectl get pods -A
```

### Scenario 4: etcd Cluster State Recovery

**Use Case**: Kubernetes API server corrupted, cluster won't start

```bash
# 1. Stop K3s on master node
sudo systemctl stop k3s

# 2. List available etcd snapshots
sudo ls -lh /var/lib/rancher/k3s/server/db/snapshots/

# 3. Restore from snapshot
sudo k3s server \
  --cluster-reset \
  --cluster-reset-restore-path=/var/lib/rancher/k3s/server/db/snapshots/<snapshot-file>

# 4. Start K3s
sudo systemctl start k3s

# 5. Verify cluster
kubectl get nodes
kubectl get pods -A
```

---

## Backup Verification

### Automated Testing

Create a cronjob to regularly test restore procedures:

```bash
kubectl create -f - <<EOF
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup-test
  namespace: velero
spec:
  schedule: "0 4 * * 1"  # 4 AM every Monday
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: velero
          containers:
          - name: backup-test
            image: velero/velero:v1.17.0
            command:
            - /bin/sh
            - -c
            - |
              # Get latest backup
              LATEST_BACKUP=\$(velero backup get --output=json | jq -r '.items | sort_by(.metadata.creationTimestamp) | .[-1].metadata.name')
              # Restore to test namespace
              velero restore create test-restore-\$(date +%s) \\
                --from-backup \$LATEST_BACKUP \\
                --include-namespaces databases \\
                --namespace-mappings databases:test-restore-db
          restartPolicy: OnFailure
EOF
```

### Manual Verification

Weekly checklist:

- [ ] Verify latest daily backup completed successfully
- [ ] Check backup size is reasonable (not 0 bytes)
- [ ] Verify MinIO storage has sufficient space
- [ ] Test restore of critical namespace
- [ ] Check etcd snapshot count
- [ ] Review Velero logs for errors

---

## Monitoring

### Prometheus Metrics

Velero exposes Prometheus metrics. ServiceMonitor is enabled.

**Key metrics**:
- `velero_backup_success_total`: Successful backups
- `velero_backup_failure_total`: Failed backups
- `velero_backup_duration_seconds`: Backup duration
- `velero_restore_success_total`: Successful restores
- `velero_restore_failure_total`: Failed restores

### Grafana Dashboard

Import Velero Grafana dashboard:
- Dashboard ID: 11055
- URL: https://grafana.com/grafana/dashboards/11055

```bash
# Or manually add queries
sum(velero_backup_success_total) by (schedule)
sum(velero_backup_failure_total) by (schedule)
```

### Alerts

Configure AlertManager rules:

```yaml
groups:
  - name: velero
    rules:
      - alert: VeleroBackupFailed
        expr: velero_backup_failure_total > 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Velero backup failed"
          description: "Backup {{ $labels.schedule }} failed"

      - alert: VeleroNoRecentBackup
        expr: time() - velero_backup_last_successful_timestamp > 86400
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "No Velero backup in 24 hours"
```

---

## Storage Management

### Check MinIO Storage

```bash
# Get MinIO pod
kubectl get pods -n velero -l app=minio

# Check disk usage
kubectl exec -n velero <minio-pod> -- df -h /data

# Check bucket sizes
kubectl exec -n velero <minio-pod> -- \
  mc du myminio/velero-backups --recursive
```

### Clean Up Old Backups

```bash
# List backups older than 30 days
velero backup get | grep -E "^(NAME|.*30d.*)"

# Delete old backups (manual)
velero backup delete <old-backup-name> --confirm

# Or let TTL handle it automatically (configured in schedules)
```

### Expand MinIO Storage

```bash
# Resize NFS PVC
kubectl patch pvc minio -n velero -p '{"spec":{"resources":{"requests":{"storage":"1Ti"}}}}'

# Verify resize
kubectl get pvc -n velero minio
```

---

## Backup Performance

### Current Performance

Based on test backup of databases namespace:
- **Backup time**: ~30 seconds
- **Backup size**: ~50MB (PostgreSQL 20Gi volume)
- **Restore time**: ~20 seconds

### Optimization Tips

1. **Exclude unnecessary data**:
   ```bash
   velero backup create opt-backup \
     --exclude-resources=events,endpoints
   ```

2. **Backup during low-traffic periods**:
   - Daily: 2 AM
   - Weekly: 3 AM Sunday

3. **Use resource filters**:
   ```bash
   velero backup create filtered \
     --include-resources=deployments,statefulsets,configmaps,secrets
   ```

4. **Parallel backups**:
   Configure `--default-backup-ttl` and `--default-volume-snapshot-locations`

---

## Troubleshooting

### Backup Stuck in Progress

```bash
# Check Velero logs
kubectl logs -n velero deployment/velero -f

# Check node-agent logs
kubectl logs -n velero -l name=node-agent --all-containers

# Describe backup
velero backup describe <backup-name> --details

# Delete stuck backup
velero backup delete <backup-name> --confirm
```

### Restore Failures

```bash
# Get restore details
velero restore describe <restore-name> --details

# Check restore logs
velero restore logs <restore-name>

# Common issues:
# - Namespace already exists: Delete first or use --namespace-mappings
# - PVC conflicts: Delete PVCs first
# - Resource conflicts: Use --existing-resource-policy=update
```

### MinIO Connection Issues

```bash
# Test MinIO connectivity
kubectl exec -n velero deployment/velero -- \
  curl -I http://minio.velero.svc.cluster.local:9000

# Check MinIO pod
kubectl get pods -n velero -l app=minio
kubectl logs -n velero -l app=minio

# Verify secret
kubectl get secret -n velero cloud-credentials -o yaml
```

### Node-Agent Not Running

```bash
# Check DaemonSet
kubectl get daemonset -n velero node-agent

# Check node-agent pods
kubectl get pods -n velero -l name=node-agent

# Check logs
kubectl logs -n velero -l name=node-agent --tail=50

# Restart node-agent
kubectl rollout restart daemonset/node-agent -n velero
```

---

## Security Considerations

### Current State

- ✅ MinIO credentials stored in Kubernetes secrets
- ✅ Backups stored on NFS (local network only)
- ⚠️ No backup encryption enabled
- ⚠️ MinIO credentials use default values

### Recommendations

1. **Enable backup encryption**:
   ```bash
   # Generate encryption key
   kubectl create secret generic velero-backup-encryption \
     --from-literal=encryption-key=$(openssl rand -base64 32) \
     -n velero

   # Update backup location
   velero backup-location set default \
     --encryption-key-secret=velero-backup-encryption
   ```

2. **Rotate MinIO credentials**:
   ```bash
   # Update MinIO root password
   kubectl exec -n velero <minio-pod> -- \
     mc admin user add myminio newuser newpassword

   # Update Velero secret
   kubectl create secret generic cloud-credentials \
     --from-literal=cloud='[default]\naws_access_key_id=newuser\naws_secret_access_key=newpassword' \
     -n velero --dry-run=client -o yaml | kubectl apply -f -

   # Restart Velero
   kubectl rollout restart deployment/velero -n velero
   ```

3. **Offsite backup replication** (Phase 2 enhancement):
   - Configure MinIO mirror to external S3/Backblaze B2
   - Use rclone for periodic offsite sync

---

## Future Enhancements

- [ ] Enable backup encryption
- [ ] Configure offsite backup replication
- [ ] Implement backup verification automation
- [ ] Add backup size trending dashboard
- [ ] Configure backup notifications (Slack/email)
- [ ] Document application-specific restore procedures
- [ ] Create runbooks for each disaster recovery scenario
- [ ] Implement backup retention policies per namespace
- [ ] Add pre/post backup hooks for databases

---

## Related Documentation

- [IMPROVEMENTS-ROADMAP.md](IMPROVEMENTS-ROADMAP.md) - Infrastructure improvements tracker
- [README.md](README.md) - Main cluster documentation
- [POSTGRESQL-DEPLOYMENT.md](POSTGRESQL-DEPLOYMENT.md) - PostgreSQL backup specifics

---

**Maintained By**: Admin
**Review Frequency**: Monthly
**Last Review**: October 19, 2025
