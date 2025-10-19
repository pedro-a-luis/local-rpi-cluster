# Apache Airflow Deployment Guide

This guide explains how to deploy Apache Airflow to your K3s cluster.

## Overview

Apache Airflow will be deployed with the following configuration:
- **Executor**: KubernetesExecutor (runs tasks as Kubernetes pods)
- **Database**: PostgreSQL (deployed in the cluster)
- **Storage**: Longhorn for DAGs and logs
- **Access**: https://airflow.stratdata.org
- **Namespace**: airflow

## Prerequisites

- K3s cluster running
- Longhorn storage class available
- Helm 3 installed on the master node
- Nginx Ingress Controller installed
- TLS wildcard certificate available

## Deployment Steps

### Option 1: Using Ansible Playbook (Recommended)

From the master node (pi-master):

```bash
# Navigate to the repository
cd /path/to/local-rpi-cluster

# Run the Airflow installation playbook
ansible-playbook ansible/playbooks/airflow-install.yml
```

### Option 2: Manual Deployment

If Ansible is not available, follow these steps from the master node:

```bash
# 1. Add Apache Airflow Helm repository
helm repo add apache-airflow https://airflow.apache.org
helm repo update

# 2. Create namespace
kubectl create namespace airflow

# 3. Copy TLS certificate (if available)
kubectl get secret stratdata-wildcard-tls -n monitoring -o yaml | \
  sed 's/namespace: monitoring/namespace: airflow/' | \
  kubectl apply -f -

# 4. Install Airflow
helm upgrade --install airflow apache-airflow/airflow \
  --namespace airflow \
  --set executor=KubernetesExecutor \
  --set postgresql.enabled=true \
  --set postgresql.auth.password=airflow123 \
  --set webserver.service.type=ClusterIP \
  --set dags.persistence.enabled=true \
  --set dags.persistence.size=5Gi \
  --set dags.persistence.storageClassName=longhorn \
  --set logs.persistence.enabled=true \
  --set logs.persistence.size=10Gi \
  --set logs.persistence.storageClassName=longhorn \
  --set webserver.defaultUser.enabled=true \
  --set webserver.defaultUser.username=admin \
  --set webserver.defaultUser.password=admin123 \
  --timeout 15m \
  --wait

# 5. Create Ingress
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: airflow-webserver
  namespace: airflow
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - airflow.stratdata.org
    secretName: stratdata-wildcard-tls
  rules:
  - host: airflow.stratdata.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: airflow-webserver
            port:
              number: 8080
EOF

# 6. Update DNS (run from where you have Pi-hole access)
ansible-playbook ansible/playbooks/infrastructure/update-pihole-dns.yml
```

## Post-Deployment

### 1. Verify Deployment

```bash
# Check pods
kubectl get pods -n airflow

# Check services
kubectl get svc -n airflow

# Check ingress
kubectl get ingress -n airflow

# Check persistent volumes
kubectl get pvc -n airflow
```

Expected pods:
- airflow-webserver
- airflow-scheduler
- airflow-postgresql
- airflow-triggerer (optional)

### 2. Access Airflow Web UI

1. Ensure DNS is updated: `airflow.stratdata.org` → `192.168.1.240`
2. Open browser: https://airflow.stratdata.org
3. Login with:
   - **Username**: admin
   - **Password**: admin123

### 3. Upload DAGs

You can upload DAGs in several ways:

#### Option A: Using kubectl cp

```bash
# Copy a DAG file to the webserver pod
kubectl cp your_dag.py airflow/airflow-webserver-xxxx:/opt/airflow/dags/

# Or copy entire directory
kubectl cp ./dags airflow/airflow-webserver-xxxx:/opt/airflow/
```

#### Option B: Using Git-Sync (Recommended for production)

Update the Helm values to enable git-sync:

```bash
helm upgrade airflow apache-airflow/airflow \
  --namespace airflow \
  --reuse-values \
  --set dags.gitSync.enabled=true \
  --set dags.gitSync.repo=https://github.com/your-org/airflow-dags.git \
  --set dags.gitSync.branch=main \
  --set dags.gitSync.subPath=dags
```

#### Option C: Using PVC directly

```bash
# Access the DAGs PVC
kubectl exec -it -n airflow airflow-webserver-xxxx -- /bin/bash

# Inside the pod
cd /opt/airflow/dags
# Create or edit your DAG files here
```

## Configuration

### Default Configuration

The deployment uses these defaults (configured in `ansible/vars/main.yml`):

- **Executor**: KubernetesExecutor
- **PostgreSQL**: Enabled (in-cluster)
- **DAGs Storage**: 5Gi (Longhorn)
- **Logs Storage**: 10Gi (Longhorn)
- **Admin User**: admin / admin123

### Customizing Configuration

To customize the deployment, edit the helm_options in `ansible/vars/main.yml`:

```yaml
airflow:
  helm_options: "--set executor=CeleryExecutor ..."
```

Or use a values file:

```bash
# Create custom values file
cat > airflow-values.yaml <<EOF
executor: KubernetesExecutor
postgresql:
  enabled: true
  auth:
    password: your-secure-password
webserver:
  defaultUser:
    username: your-admin
    password: your-secure-password
dags:
  persistence:
    size: 10Gi
EOF

# Deploy with custom values
helm upgrade --install airflow apache-airflow/airflow \
  --namespace airflow \
  -f airflow-values.yaml
```

## Monitoring

### View Logs

```bash
# Webserver logs
kubectl logs -n airflow -l component=webserver -f

# Scheduler logs
kubectl logs -n airflow -l component=scheduler -f

# PostgreSQL logs
kubectl logs -n airflow -l app.kubernetes.io/name=postgresql -f

# Specific pod logs
kubectl logs -n airflow <pod-name> -f
```

### Check Resource Usage

```bash
# Pod resource usage
kubectl top pods -n airflow

# Node resource usage
kubectl top nodes
```

### Airflow Web UI Monitoring

Access https://airflow.stratdata.org and check:
- **Home**: View all DAGs and their status
- **Browse → Task Instances**: See running/failed tasks
- **Admin → Pools**: Configure resource pools
- **Admin → Variables**: Manage Airflow variables
- **Admin → Connections**: Configure external connections

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl describe pod -n airflow <pod-name>

# Check events
kubectl get events -n airflow --sort-by='.lastTimestamp'

# Check PVC status
kubectl get pvc -n airflow
```

### Cannot Access Web UI

1. Check ingress:
   ```bash
   kubectl get ingress -n airflow
   kubectl describe ingress airflow-webserver -n airflow
   ```

2. Check service:
   ```bash
   kubectl get svc -n airflow airflow-webserver
   ```

3. Test connectivity from master:
   ```bash
   curl http://airflow-webserver.airflow.svc.cluster.local:8080
   ```

4. Check DNS:
   ```bash
   nslookup airflow.stratdata.org
   ```

### Database Connection Issues

```bash
# Check PostgreSQL pod
kubectl get pods -n airflow -l app.kubernetes.io/name=postgresql

# Check PostgreSQL logs
kubectl logs -n airflow -l app.kubernetes.io/name=postgresql

# Connect to PostgreSQL
kubectl exec -it -n airflow airflow-postgresql-0 -- psql -U postgres
```

### DAGs Not Showing Up

```bash
# Check DAGs folder in webserver
kubectl exec -it -n airflow airflow-webserver-xxxx -- ls -la /opt/airflow/dags/

# Check scheduler logs for parsing errors
kubectl logs -n airflow -l component=scheduler | grep -i error

# Force DAG rescan from Airflow UI
# Admin → Configuration → dag_dir_list_interval
```

## Upgrading Airflow

```bash
# Update Helm repo
helm repo update

# Check available versions
helm search repo apache-airflow/airflow --versions

# Upgrade to latest version
helm upgrade airflow apache-airflow/airflow \
  --namespace airflow \
  --reuse-values

# Or upgrade to specific version
helm upgrade airflow apache-airflow/airflow \
  --namespace airflow \
  --version 1.11.0 \
  --reuse-values
```

## Uninstalling Airflow

**WARNING**: This will delete all DAGs, logs, and database data!

```bash
# Using Ansible (recommended)
# Edit ansible/vars/main.yml and set airflow.install: false
ansible-playbook ansible/playbooks/k3s-remove-apps.yml --tags airflow

# Or manually
helm uninstall airflow -n airflow
kubectl delete namespace airflow
```

## Security Recommendations

1. **Change Default Password**: Update the admin password after first login
2. **Use Secrets**: Store sensitive data in Kubernetes secrets
3. **Enable RBAC**: Configure Airflow RBAC for multiple users
4. **Secure Connections**: Use encrypted connections for external services
5. **Regular Backups**: Backup the PostgreSQL database regularly

## Useful Resources

- [Official Airflow Helm Chart Documentation](https://airflow.apache.org/docs/helm-chart/)
- [Airflow Documentation](https://airflow.apache.org/docs/)
- [KubernetesExecutor Guide](https://airflow.apache.org/docs/apache-airflow/stable/executor/kubernetes.html)
- [Writing DAGs](https://airflow.apache.org/docs/apache-airflow/stable/tutorial.html)

## Support

For issues specific to this deployment:
1. Check the logs: `kubectl logs -n airflow -l component=scheduler`
2. Review the Ansible playbook: `ansible/playbooks/airflow-install.yml`
3. Check Airflow configuration in: `ansible/vars/main.yml`
