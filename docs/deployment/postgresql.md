# PostgreSQL Deployment Guide (ARM64)

**Deployed**: October 19, 2025
**Version**: PostgreSQL 16.10 (Alpine Linux)
**Architecture**: ARM64 (aarch64-unknown-linux-musl)

---

## Overview

PostgreSQL is deployed as a single-instance StatefulSet using the official ARM64-compatible `postgres:16-alpine` image.

### Deployment Details
- **Namespace**: `databases`
- **Image**: `docker.io/library/postgres:16-alpine`
- **Storage**: 20Gi Longhorn PVC
- **Resources**:
  - Requests: 200m CPU, 512Mi memory
  - Limits: 1 CPU, 1Gi memory
  - Actual usage: ~3m CPU, ~24Mi memory

---

## Access Information

### Connection Details

**Service Endpoints**:
- **Primary (internal)**: `postgresql-primary.databases.svc.cluster.local:5432`
- **Headless service**: `postgresql-primary-hl.databases.svc.cluster.local:5432`

**Credentials** (stored in Kubernetes secret):
- **Database**: `appdb`
- **User**: `appuser`
- **Password**: Stored in secret `postgresql` key `password`

### Connection String

```bash
postgresql://appuser:PASSWORD@postgresql-primary.databases.svc.cluster.local:5432/appdb
```

---

## Common Operations

### Connect to PostgreSQL

```bash
# Using kubectl exec
kubectl exec -it -n databases postgresql-primary-0 -- psql -U appuser -d appdb

# Get password from secret
kubectl get secret postgresql -n databases -o jsonpath='{.data.password}' | base64 -d
```

### Check Status

```bash
# Pod status
kubectl get pods -n databases

# Logs
kubectl logs -n databases postgresql-primary-0 -f

# Resource usage
kubectl top pod postgresql-primary-0 -n databases

# Database version
kubectl exec -n databases postgresql-primary-0 -- psql -U appuser -d appdb -c "SELECT version();"
```

### List Databases

```bash
kubectl exec -n databases postgresql-primary-0 -- psql -U appuser -d appdb -c "\l"
```

### Backup Database

```bash
# Backup to file
kubectl exec -n databases postgresql-primary-0 -- pg_dump -U appuser appdb > backup.sql

# Backup with compression
kubectl exec -n databases postgresql-primary-0 -- pg_dump -U appuser -Fc appdb > backup.dump
```

### Restore Database

```bash
# From SQL file
cat backup.sql | kubectl exec -i -n databases postgresql-primary-0 -- psql -U appuser -d appdb

# From compressed dump
kubectl cp backup.dump databases/postgresql-primary-0:/tmp/
kubectl exec -n databases postgresql-primary-0 -- pg_restore -U appuser -d appdb /tmp/backup.dump
```

---

## Kubernetes Resources

### Services

```bash
kubectl get svc -n databases
```

| Service | Type | Endpoint | Purpose |
|---------|------|----------|---------|
| postgresql-primary | ClusterIP | 10.43.124.235:5432 | Primary database access |
| postgresql-primary-hl | ClusterIP (None) | Headless | StatefulSet discovery |

### Persistent Volume

```bash
kubectl get pvc -n databases
```

- **PVC**: `data-postgresql-primary-0`
- **Volume**: `pvc-686009a9-accf-4240-9fa6-d39af8793549`
- **Size**: 20Gi
- **StorageClass**: Longhorn

---

## Deployment Manifest

Location: `/root/gitlab/local-rpi-cluster/ansible/playbooks/infrastructure/postgresql-arm64.yml`

Applied manifest: `/tmp/postgresql-primary.yaml`

### Key Configuration

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgresql-primary
  namespace: databases
spec:
  serviceName: postgresql-primary-hl
  replicas: 1
  template:
    spec:
      containers:
        - name: postgresql
          image: postgres:16-alpine
          env:
            - name: POSTGRES_USER
              value: "appuser"
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgresql
                  key: password
            - name: POSTGRES_DB
              value: "appdb"
            - name: PGDATA
              value: /var/lib/postgresql/data/pgdata
```

---

## Troubleshooting

### Pod Not Starting

```bash
# Check pod events
kubectl describe pod postgresql-primary-0 -n databases

# Check logs
kubectl logs -n databases postgresql-primary-0

# Check PVC status
kubectl get pvc -n databases
```

### Connection Issues

```bash
# Test from another pod
kubectl run -it --rm psql-test --image=postgres:16-alpine --restart=Never -- \
  psql -h postgresql-primary.databases.svc.cluster.local -U appuser -d appdb

# Check service endpoints
kubectl get endpoints -n databases postgresql-primary
```

### Performance Issues

```bash
# Check resource usage
kubectl top pod postgresql-primary-0 -n databases

# Check disk I/O
kubectl exec -n databases postgresql-primary-0 -- df -h

# Check active connections
kubectl exec -n databases postgresql-primary-0 -- \
  psql -U appuser -d appdb -c "SELECT count(*) FROM pg_stat_activity;"
```

---

## Maintenance

### Update Configuration

PostgreSQL uses environment variables for configuration. To update:

1. Edit the StatefulSet:
   ```bash
   kubectl edit statefulset postgresql-primary -n databases
   ```

2. Update environment variables or resource limits

3. Delete the pod to apply changes:
   ```bash
   kubectl delete pod postgresql-primary-0 -n databases
   ```

### Scaling (Not Recommended)

This is a single-instance deployment. For HA/replication:
- Consider deploying a read replica
- Use PostgreSQL streaming replication
- Or use a PostgreSQL operator (e.g., CloudNativePG, Zalando Postgres Operator)

### Upgrade PostgreSQL

To upgrade to a newer version:

1. Backup the database first!
2. Update the image tag in the StatefulSet
3. Delete the pod to pull new image
4. Verify version after restart

**Warning**: Major version upgrades may require `pg_upgrade`. Test in non-production first.

---

## Integration Examples

### Airflow Connection

When deploying Airflow, use this connection string:

```python
# In Airflow values.yaml or environment
AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql://appuser:PASSWORD@postgresql-primary.databases.svc.cluster.local:5432/appdb
```

### From Application Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-example
spec:
  containers:
    - name: app
      image: myapp:latest
      env:
        - name: DATABASE_URL
          value: "postgresql://appuser:PASSWORD@postgresql-primary.databases.svc.cluster.local:5432/appdb"
```

---

## Security Considerations

1. **Password Management**:
   - Passwords are stored in Kubernetes secrets (base64 encoded, not encrypted)
   - Consider using Sealed Secrets or External Secrets Operator for production

2. **Network Policies**:
   - Currently no NetworkPolicy restricting access
   - Consider implementing NetworkPolicy to limit access to specific namespaces

3. **Encryption**:
   - Connections are not encrypted (no TLS)
   - For production, enable SSL/TLS

4. **Backups**:
   - No automated backups configured
   - Phase 2 (Velero) will add backup capability
   - Consider scheduled pg_dump cronjobs

---

## Future Improvements

- [ ] Deploy read replica for HA
- [ ] Configure automated backups (pg_dump cronjob)
- [ ] Enable connection pooling (PgBouncer)
- [ ] Implement NetworkPolicy for access control
- [ ] Enable SSL/TLS connections
- [ ] Set up PostgreSQL monitoring in Grafana
- [ ] Configure pg_exporter for Prometheus metrics
- [ ] Implement proper secret management (Sealed Secrets/Vault)

---

## References

- [Official PostgreSQL Docker Image](https://hub.docker.com/_/postgres)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/16/)
- [Kubernetes StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- [Longhorn Storage](https://longhorn.io/docs/)

---

**Last Updated**: October 19, 2025
**Maintained By**: Admin
