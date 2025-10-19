# Scripts Directory

Automation scripts for cluster management and deployment.

## Cluster Management Scripts

**Location**: `cluster/`

### Cluster Lifecycle
- **[init.sh](cluster/init.sh)** - Initial cluster setup and configuration
- **[shutdown.sh](cluster/shutdown.sh)** - Graceful cluster shutdown with pre-shutdown backups
- **[startup.sh](cluster/startup.sh)** - Cluster startup with health verification

### Usage Examples

**Cluster Shutdown:**
```bash
# Interactive shutdown with confirmation
./scripts/cluster/shutdown.sh

# Force shutdown without confirmation
./scripts/cluster/shutdown.sh --force
```

**Cluster Startup:**
```bash
# Start cluster with full health checks
./scripts/cluster/startup.sh

# Start with smoke tests
./scripts/cluster/startup.sh --smoke-tests
```

## Deployment Scripts

**Location**: `deployment/`

### Service Deployment
- **[deploy-airflow.sh](deployment/deploy-airflow.sh)** - Apache Airflow deployment automation
- **[monitor.sh](deployment/monitor.sh)** - Monitor deployment status and health

### Usage Examples

**Deploy Airflow:**
```bash
./scripts/deployment/deploy-airflow.sh
```

**Monitor Deployment:**
```bash
./scripts/deployment/monitor.sh
```

## Prerequisites

All scripts require:
- SSH access to cluster nodes (key-based authentication recommended)
- kubectl configured with cluster access
- Appropriate permissions for cluster operations

## Configuration

Scripts use the following default configuration:
- **Master Node**: 192.168.1.240 (pi-master)
- **Worker Nodes**: 192.168.1.241-247 (pi-worker-01 through pi-worker-07)
- **SSH User**: admin
- **SSH Key**: `~/.ssh/pi_cluster`

Modify configuration variables at the top of each script if your setup differs.

## Logs

Cluster management scripts create logs in:
- Shutdown logs: `/var/log/cluster-shutdown/`
- Startup logs: `/var/log/cluster-startup/`

## Related Documentation

- [Cluster Lifecycle Guide](../docs/operations/cluster-lifecycle.md) - Detailed shutdown/startup procedures
- [Ansible Guide](../docs/operations/ansible-guide.md) - Ansible playbook alternatives
