#!/bin/bash
# Cluster Shutdown Script - Graceful shutdown of the entire K3s cluster
# Usage: ./cluster-shutdown.sh [--force]
# This script performs an orderly shutdown to prevent data corruption

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MASTER_NODE="192.168.1.240"
WORKER_NODES=("192.168.1.241" "192.168.1.242" "192.168.1.243" "192.168.1.244" "192.168.1.245" "192.168.1.246" "192.168.1.247")
SSH_USER="admin"
SSH_KEY="$HOME/.ssh/pi_cluster"
BACKUP_BEFORE_SHUTDOWN=true
DRAIN_TIMEOUT=300  # 5 minutes

# Logging
LOG_DIR="/var/log/cluster-shutdown"
LOG_FILE="$LOG_DIR/shutdown-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$LOG_DIR"

# Functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

log_step() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] STEP:${NC} $1" | tee -a "$LOG_FILE"
}

confirm_shutdown() {
    if [[ "$1" != "--force" ]]; then
        echo ""
        echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║         CLUSTER SHUTDOWN CONFIRMATION                      ║${NC}"
        echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "This will shut down the entire K3s cluster including:"
        echo "  - Master node: $MASTER_NODE"
        echo "  - Worker nodes: ${WORKER_NODES[@]}"
        echo ""
        echo "All services will be stopped, including:"
        echo "  - Grafana, Prometheus, Loki"
        echo "  - PostgreSQL databases"
        echo "  - MinIO backups"
        echo "  - All application pods"
        echo ""
        read -p "Are you sure you want to proceed? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log "Shutdown cancelled by user"
            exit 0
        fi
    fi
}

create_snapshot() {
    log_step "Creating etcd snapshot before shutdown..."
    ssh -i "$SSH_KEY" "$SSH_USER@$MASTER_NODE" 'sudo k3s etcd-snapshot save --name pre-shutdown-$(date +%Y%m%d-%H%M%S)' || {
        log_warning "etcd snapshot failed, continuing anyway..."
    }
}

create_velero_backup() {
    if [[ "$BACKUP_BEFORE_SHUTDOWN" == "true" ]]; then
        log_step "Creating Velero backup before shutdown..."
        ssh -i "$SSH_KEY" "$SSH_USER@$MASTER_NODE" 'velero backup create pre-shutdown-$(date +%Y%m%d-%H%M%S) --wait --timeout=10m' || {
            log_warning "Velero backup failed, continuing anyway..."
        }
    fi
}

drain_node() {
    local node_name=$1
    log_step "Draining node: $node_name"
    ssh -i "$SSH_KEY" "$SSH_USER@$MASTER_NODE" "kubectl drain $node_name --ignore-daemonsets --delete-emptydir-data --timeout=${DRAIN_TIMEOUT}s --force" || {
        log_warning "Failed to drain $node_name, continuing..."
    }
}

cordon_node() {
    local node_name=$1
    log_step "Cordoning node: $node_name"
    ssh -i "$SSH_KEY" "$SSH_USER@$MASTER_NODE" "kubectl cordon $node_name" || {
        log_warning "Failed to cordon $node_name"
    }
}

stop_k3s_agent() {
    local node_ip=$1
    local node_name=$2
    log_step "Stopping K3s agent on: $node_name ($node_ip)"
    ssh -i "$SSH_KEY" "$SSH_USER@$node_ip" 'sudo systemctl stop k3s-agent' || {
        log_error "Failed to stop k3s-agent on $node_name"
    }
    sleep 2
}

stop_k3s_server() {
    log_step "Stopping K3s server on master node..."
    ssh -i "$SSH_KEY" "$SSH_USER@$MASTER_NODE" 'sudo systemctl stop k3s' || {
        log_error "Failed to stop K3s server"
    }
    sleep 5
}

shutdown_node() {
    local node_ip=$1
    local node_name=$2
    log_step "Shutting down node: $node_name ($node_ip)"
    ssh -i "$SSH_KEY" "$SSH_USER@$node_ip" 'sudo shutdown -h now' || {
        log_warning "Failed to shutdown $node_name"
    }
}

# Main execution
main() {
    log ""
    log "═══════════════════════════════════════════════════════════"
    log "          KUBERNETES CLUSTER SHUTDOWN INITIATED"
    log "═══════════════════════════════════════════════════════════"
    log ""

    # Confirm shutdown
    confirm_shutdown "$1"

    # Step 1: Create backups
    log ""
    log "═══════════════════════════════════════════════════════════"
    log "STEP 1: Creating pre-shutdown backups"
    log "═══════════════════════════════════════════════════════════"
    create_snapshot
    create_velero_backup

    # Step 2: Get node list and status
    log ""
    log "═══════════════════════════════════════════════════════════"
    log "STEP 2: Checking cluster status"
    log "═══════════════════════════════════════════════════════════"
    log "Current cluster nodes:"
    ssh -i "$SSH_KEY" "$SSH_USER@$MASTER_NODE" 'kubectl get nodes' | tee -a "$LOG_FILE"

    # Step 3: Cordon all nodes (prevent new pods)
    log ""
    log "═══════════════════════════════════════════════════════════"
    log "STEP 3: Cordoning all nodes"
    log "═══════════════════════════════════════════════════════════"

    # Cordon workers first
    for i in "${!WORKER_NODES[@]}"; do
        worker_num=$((i + 1))
        cordon_node "pi-worker-0$worker_num"
    done

    # Cordon master last
    cordon_node "pi-master"

    # Step 4: Drain worker nodes
    log ""
    log "═══════════════════════════════════════════════════════════"
    log "STEP 4: Draining worker nodes (evicting pods gracefully)"
    log "═══════════════════════════════════════════════════════════"

    for i in "${!WORKER_NODES[@]}"; do
        worker_num=$((i + 1))
        drain_node "pi-worker-0$worker_num"
    done

    # Wait for pods to migrate
    log_step "Waiting 30 seconds for pods to stabilize..."
    sleep 30

    # Step 5: Stop K3s agents on worker nodes
    log ""
    log "═══════════════════════════════════════════════════════════"
    log "STEP 5: Stopping K3s agents on worker nodes"
    log "═══════════════════════════════════════════════════════════"

    for i in "${!WORKER_NODES[@]}"; do
        worker_num=$((i + 1))
        stop_k3s_agent "${WORKER_NODES[$i]}" "pi-worker-0$worker_num"
    done

    # Step 6: Stop K3s server on master
    log ""
    log "═══════════════════════════════════════════════════════════"
    log "STEP 6: Stopping K3s server on master node"
    log "═══════════════════════════════════════════════════════════"
    stop_k3s_server

    # Step 7: Shutdown worker nodes
    log ""
    log "═══════════════════════════════════════════════════════════"
    log "STEP 7: Shutting down worker nodes"
    log "═══════════════════════════════════════════════════════════"

    for i in "${!WORKER_NODES[@]}"; do
        worker_num=$((i + 1))
        shutdown_node "${WORKER_NODES[$i]}" "pi-worker-0$worker_num"
        sleep 2
    done

    # Step 8: Shutdown master node
    log ""
    log "═══════════════════════════════════════════════════════════"
    log "STEP 8: Shutting down master node"
    log "═══════════════════════════════════════════════════════════"
    log_warning "Master node will shutdown in 30 seconds..."
    log "You have 30 seconds to cancel with Ctrl+C"

    for i in {30..1}; do
        echo -ne "\rShutdown in: $i seconds... "
        sleep 1
    done
    echo ""

    shutdown_node "$MASTER_NODE" "pi-master"

    log ""
    log "═══════════════════════════════════════════════════════════"
    log "CLUSTER SHUTDOWN COMPLETE"
    log "═══════════════════════════════════════════════════════════"
    log "All nodes have been shut down gracefully."
    log "Log file: $LOG_FILE"
    log ""
    log "To restart the cluster, use: ./cluster-startup.sh"
    log "═══════════════════════════════════════════════════════════"
}

# Run main function
main "$@"
