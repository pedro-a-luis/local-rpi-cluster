#!/bin/bash
# Cluster Startup Script - Initialize and verify the K3s cluster
# Usage: ./cluster-startup.sh [--skip-health-check]
# This script performs an orderly startup and health verification

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
MASTER_STARTUP_WAIT=120  # Wait 2 minutes for master to be ready
WORKER_STARTUP_WAIT=60   # Wait 1 minute for each worker
HEALTH_CHECK_RETRIES=30
HEALTH_CHECK_INTERVAL=10

# Logging
LOG_DIR="/var/log/cluster-startup"
LOG_FILE="$LOG_DIR/startup-$(date +%Y%m%d-%H%M%S).log"
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

check_node_online() {
    local node_ip=$1
    local node_name=$2
    log_step "Checking if $node_name ($node_ip) is online..."

    if ping -c 3 -W 5 "$node_ip" > /dev/null 2>&1; then
        log "$node_name is reachable"
        return 0
    else
        log_error "$node_name is NOT reachable"
        return 1
    fi
}

power_on_node() {
    local node_ip=$1
    local node_name=$2
    log_step "Attempting to power on $node_name..."

    # Note: This requires Wake-on-LAN configuration
    # You may need to use your network's power management or manually power on
    log_warning "Manual power-on may be required for $node_name"
    log "Please ensure $node_name is powered on and press Enter to continue..."
    read -r
}

wait_for_ssh() {
    local node_ip=$1
    local node_name=$2
    local max_attempts=30
    local attempt=1

    log_step "Waiting for SSH on $node_name..."

    while [ $attempt -le $max_attempts ]; do
        if ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o BatchMode=yes "$SSH_USER@$node_ip" 'exit' 2>/dev/null; then
            log "$node_name SSH is ready"
            return 0
        fi
        echo -ne "\rAttempt $attempt/$max_attempts... "
        sleep 10
        ((attempt++))
    done

    echo ""
    log_error "SSH timeout for $node_name"
    return 1
}

start_k3s_server() {
    log_step "Starting K3s server on master node..."
    ssh -i "$SSH_KEY" "$SSH_USER@$MASTER_NODE" 'sudo systemctl start k3s' || {
        log_error "Failed to start K3s server"
        return 1
    }

    log "Waiting $MASTER_STARTUP_WAIT seconds for K3s server to initialize..."
    for i in $(seq $MASTER_STARTUP_WAIT -1 1); do
        echo -ne "\rWaiting: $i seconds... "
        sleep 1
    done
    echo ""
}

wait_for_k3s_ready() {
    local max_attempts=$HEALTH_CHECK_RETRIES
    local attempt=1

    log_step "Waiting for K3s API server to be ready..."

    while [ $attempt -le $max_attempts ]; do
        if ssh -i "$SSH_KEY" "$SSH_USER@$MASTER_NODE" 'kubectl get nodes > /dev/null 2>&1'; then
            log "K3s API server is ready"
            return 0
        fi
        echo -ne "\rAttempt $attempt/$max_attempts... "
        sleep $HEALTH_CHECK_INTERVAL
        ((attempt++))
    done

    echo ""
    log_error "K3s API server failed to become ready"
    return 1
}

start_k3s_agent() {
    local node_ip=$1
    local node_name=$2

    log_step "Starting K3s agent on $node_name..."
    ssh -i "$SSH_KEY" "$SSH_USER@$node_ip" 'sudo systemctl start k3s-agent' || {
        log_error "Failed to start k3s-agent on $node_name"
        return 1
    }

    log "Waiting $WORKER_STARTUP_WAIT seconds for $node_name to join cluster..."
    sleep $WORKER_STARTUP_WAIT
}

uncordon_node() {
    local node_name=$1
    log_step "Uncordoning node: $node_name"

    ssh -i "$SSH_KEY" "$SSH_USER@$MASTER_NODE" "kubectl uncordon $node_name" || {
        log_warning "Failed to uncordon $node_name"
        return 1
    }
}

check_node_ready() {
    local node_name=$1
    local max_attempts=30
    local attempt=1

    log_step "Checking if $node_name is Ready in Kubernetes..."

    while [ $attempt -le $max_attempts ]; do
        local status=$(ssh -i "$SSH_KEY" "$SSH_USER@$MASTER_NODE" "kubectl get node $node_name -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'" 2>/dev/null)

        if [[ "$status" == "True" ]]; then
            log "$node_name is Ready"
            return 0
        fi

        echo -ne "\rAttempt $attempt/$max_attempts (Status: $status)... "
        sleep 10
        ((attempt++))
    done

    echo ""
    log_error "$node_name failed to become Ready"
    return 1
}

verify_cluster_health() {
    log ""
    log "═══════════════════════════════════════════════════════════"
    log "CLUSTER HEALTH VERIFICATION"
    log "═══════════════════════════════════════════════════════════"

    # Check nodes
    log_step "Checking node status..."
    ssh -i "$SSH_KEY" "$SSH_USER@$MASTER_NODE" 'kubectl get nodes' | tee -a "$LOG_FILE"

    # Check system pods
    log ""
    log_step "Checking system pods..."
    ssh -i "$SSH_KEY" "$SSH_USER@$MASTER_NODE" 'kubectl get pods -n kube-system' | tee -a "$LOG_FILE"

    # Check critical services
    log ""
    log_step "Checking critical services..."
    local namespaces=("longhorn-system" "monitoring" "logging" "velero" "databases")

    for ns in "${namespaces[@]}"; do
        log "Namespace: $ns"
        ssh -i "$SSH_KEY" "$SSH_USER@$MASTER_NODE" "kubectl get pods -n $ns 2>/dev/null | head -10" | tee -a "$LOG_FILE" || {
            log_warning "Namespace $ns not found or has no pods"
        }
        echo ""
    done

    # Check for pods in error state
    log_step "Checking for failed pods..."
    ssh -i "$SSH_KEY" "$SSH_USER@$MASTER_NODE" 'kubectl get pods -A | grep -E "Error|CrashLoop|ImagePullBackOff" || echo "No failed pods found"' | tee -a "$LOG_FILE"

    # Check Longhorn
    log ""
    log_step "Checking Longhorn storage..."
    ssh -i "$SSH_KEY" "$SSH_USER@$MASTER_NODE" 'kubectl get nodes.longhorn.io -n longhorn-system' | tee -a "$LOG_FILE"

    # Check Velero backup location
    log ""
    log_step "Checking Velero backup location..."
    ssh -i "$SSH_KEY" "$SSH_USER@$MASTER_NODE" 'velero backup-location get' | tee -a "$LOG_FILE"
}

run_smoke_tests() {
    log ""
    log "═══════════════════════════════════════════════════════════"
    log "RUNNING SMOKE TESTS"
    log "═══════════════════════════════════════════════════════════"

    # Test 1: Create test pod
    log_step "Test 1: Creating test pod..."
    ssh -i "$SSH_KEY" "$SSH_USER@$MASTER_NODE" 'kubectl run startup-test --image=busybox:latest --restart=Never --command -- sleep 30' || {
        log_warning "Test pod creation failed"
    }
    sleep 5

    # Test 2: Check if pod is running
    log_step "Test 2: Checking test pod status..."
    ssh -i "$SSH_KEY" "$SSH_USER@$MASTER_NODE" 'kubectl get pod startup-test' | tee -a "$LOG_FILE"

    # Test 3: Cleanup test pod
    log_step "Test 3: Cleaning up test pod..."
    ssh -i "$SSH_KEY" "$SSH_USER@$MASTER_NODE" 'kubectl delete pod startup-test --wait=false' || true

    # Test 4: Check DNS resolution
    log_step "Test 4: Checking cluster DNS..."
    ssh -i "$SSH_KEY" "$SSH_USER@$MASTER_NODE" 'kubectl run dns-test --image=busybox:latest --restart=Never --rm -it --command -- nslookup kubernetes.default.svc.cluster.local' | tee -a "$LOG_FILE" || {
        log_warning "DNS test failed"
    }
}

# Main execution
main() {
    log ""
    log "═══════════════════════════════════════════════════════════"
    log "          KUBERNETES CLUSTER STARTUP INITIATED"
    log "═══════════════════════════════════════════════════════════"
    log ""

    # Step 1: Check master node
    log ""
    log "═══════════════════════════════════════════════════════════"
    log "STEP 1: Checking master node connectivity"
    log "═══════════════════════════════════════════════════════════"

    if ! check_node_online "$MASTER_NODE" "pi-master"; then
        power_on_node "$MASTER_NODE" "pi-master"
    fi

    wait_for_ssh "$MASTER_NODE" "pi-master" || {
        log_error "Cannot connect to master node"
        exit 1
    }

    # Step 2: Start K3s server
    log ""
    log "═══════════════════════════════════════════════════════════"
    log "STEP 2: Starting K3s server on master node"
    log "═══════════════════════════════════════════════════════════"

    start_k3s_server
    wait_for_k3s_ready || {
        log_error "K3s server failed to start properly"
        exit 1
    }

    # Step 3: Start worker nodes
    log ""
    log "═══════════════════════════════════════════════════════════"
    log "STEP 3: Starting worker nodes"
    log "═══════════════════════════════════════════════════════════"

    for i in "${!WORKER_NODES[@]}"; do
        worker_num=$((i + 1))
        worker_name="pi-worker-0$worker_num"
        worker_ip="${WORKER_NODES[$i]}"

        log ""
        log "Processing: $worker_name ($worker_ip)"
        log "─────────────────────────────────────────────────────────"

        # Check if online
        if ! check_node_online "$worker_ip" "$worker_name"; then
            power_on_node "$worker_ip" "$worker_name"
        fi

        # Wait for SSH
        wait_for_ssh "$worker_ip" "$worker_name" || {
            log_error "Cannot connect to $worker_name"
            continue
        }

        # Start K3s agent
        start_k3s_agent "$worker_ip" "$worker_name"

        # Check if node joined
        check_node_ready "$worker_name" || {
            log_warning "$worker_name is not ready yet, continuing..."
        }
    done

    # Step 4: Uncordon all nodes
    log ""
    log "═══════════════════════════════════════════════════════════"
    log "STEP 4: Uncordoning all nodes"
    log "═══════════════════════════════════════════════════════════"

    uncordon_node "pi-master"
    for i in "${!WORKER_NODES[@]}"; do
        worker_num=$((i + 1))
        uncordon_node "pi-worker-0$worker_num"
    done

    # Step 5: Wait for pods to stabilize
    log ""
    log "═══════════════════════════════════════════════════════════"
    log "STEP 5: Waiting for pods to stabilize"
    log "═══════════════════════════════════════════════════════════"

    log "Waiting 60 seconds for pods to start..."
    for i in {60..1}; do
        echo -ne "\rWaiting: $i seconds... "
        sleep 1
    done
    echo ""

    # Step 6: Health verification
    if [[ "$1" != "--skip-health-check" ]]; then
        verify_cluster_health

        # Step 7: Smoke tests
        read -p "Run smoke tests? (y/n): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            run_smoke_tests
        fi
    fi

    # Final status
    log ""
    log "═══════════════════════════════════════════════════════════"
    log "CLUSTER STARTUP COMPLETE"
    log "═══════════════════════════════════════════════════════════"
    log ""
    log "Cluster Status:"
    ssh -i "$SSH_KEY" "$SSH_USER@$MASTER_NODE" 'kubectl get nodes' | tee -a "$LOG_FILE"
    log ""
    log "Log file: $LOG_FILE"
    log ""
    log "Next steps:"
    log "  - Check Grafana: https://grafana.stratdata.org"
    log "  - Check Longhorn: https://longhorn.stratdata.org"
    log "  - Check MinIO: https://minio-console.stratdata.org"
    log "  - Review logs: kubectl get pods -A"
    log "═══════════════════════════════════════════════════════════"
}

# Run main function
main "$@"
