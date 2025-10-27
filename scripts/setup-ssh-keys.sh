#!/bin/bash
# SSH Key Setup Script for Pi Cluster Infrastructure
# Configures SSH key authentication for cluster nodes and Pi-hole servers

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# SSH key to use
SSH_KEY="$HOME/.ssh/pi_cluster"
SSH_PUB_KEY="${SSH_KEY}.pub"

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to display usage
usage() {
    cat <<EOF
SSH Key Setup Script

Usage: $0 [OPTIONS]

Options:
    -h, --help              Show this help message
    -a, --all               Configure all hosts (cluster + pi-holes)
    -c, --cluster           Configure cluster nodes only
    -p, --pihole            Configure Pi-hole servers only
    -t, --test              Test SSH connectivity only
    --update-config         Update SSH config file

Hosts:
    Cluster:
        pi-master      (192.168.1.240)
        pi-worker-01   (192.168.1.241)
        pi-worker-02   (192.168.1.242)
        pi-worker-03   (192.168.1.243)
        pi-worker-04   (192.168.1.244)
        pi-worker-05   (192.168.1.245)
        pi-worker-06   (192.168.1.246)
        pi-worker-07   (192.168.1.247)

    Pi-hole:
        rpi-vpn-1      (192.168.1.25) - Primary
        rpi-vpn-2      (192.168.1.26) - Secondary

Key: $SSH_KEY

Examples:
    $0 --all                # Setup SSH for all hosts
    $0 --cluster            # Setup cluster nodes only
    $0 --pihole             # Setup Pi-hole servers only
    $0 --test               # Test connectivity to all hosts

EOF
}

# Check if key exists
check_key() {
    if [ ! -f "$SSH_KEY" ]; then
        print_error "SSH key not found: $SSH_KEY"
        print_info "Generate a new key with: ssh-keygen -t ed25519 -f $SSH_KEY -C 'homelab-pi-cluster'"
        exit 1
    fi

    if [ ! -f "$SSH_PUB_KEY" ]; then
        print_error "SSH public key not found: $SSH_PUB_KEY"
        exit 1
    fi

    print_success "SSH key found: $SSH_KEY"
}

# Function to copy SSH key to host
copy_key() {
    local host=$1
    local name=$2

    print_info "Copying SSH key to $name ($host)..."

    if ssh-copy-id -i "$SSH_PUB_KEY" -o ConnectTimeout=5 admin@$host 2>/dev/null; then
        print_success "✓ SSH key copied to $name"
        return 0
    else
        print_error "✗ Failed to copy SSH key to $name"
        print_warning "  You may need to enter the password manually"
        print_warning "  Try: ssh-copy-id -i $SSH_PUB_KEY admin@$host"
        return 1
    fi
}

# Function to test SSH connectivity
test_ssh() {
    local host=$1
    local name=$2

    if ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@$host "hostname" 2>/dev/null >/dev/null; then
        print_success "✓ $name ($host) - SSH working"
        return 0
    else
        print_error "✗ $name ($host) - SSH failed"
        return 1
    fi
}

# Update SSH config
update_ssh_config() {
    local config_file="$HOME/.ssh/config"
    local backup_file="$HOME/.ssh/config.backup.$(date +%Y%m%d_%H%M%S)"

    print_info "Updating SSH config: $config_file"

    # Backup existing config
    if [ -f "$config_file" ]; then
        cp "$config_file" "$backup_file"
        print_success "Backup created: $backup_file"
    fi

    # Check if pi-cluster config exists
    if grep -q "# Pi Cluster Configuration" "$config_file" 2>/dev/null; then
        print_warning "Pi cluster configuration already exists in SSH config"
        read -p "Overwrite? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Skipping SSH config update"
            return
        fi
        # Remove existing config
        sed -i '/# Pi Cluster Configuration/,/# End Pi Cluster/d' "$config_file"
    fi

    # Add new config
    cat >> "$config_file" <<'EOF'

# Pi Cluster Configuration
Host pi-master
    HostName 192.168.1.240
    User admin
    IdentityFile ~/.ssh/pi_cluster
    IdentitiesOnly yes

Host pi-worker-*
    User admin
    IdentityFile ~/.ssh/pi_cluster
    IdentitiesOnly yes

Host pi-worker-01
    HostName 192.168.1.241

Host pi-worker-02
    HostName 192.168.1.242

Host pi-worker-03
    HostName 192.168.1.243

Host pi-worker-04
    HostName 192.168.1.244

Host pi-worker-05
    HostName 192.168.1.245

Host pi-worker-06
    HostName 192.168.1.246

Host pi-worker-07
    HostName 192.168.1.247

Host rpi-vpn-1 pihole-primary
    HostName 192.168.1.25
    User admin
    IdentityFile ~/.ssh/pi_cluster
    IdentitiesOnly yes

Host rpi-vpn-2 pihole-secondary
    HostName 192.168.1.26
    User admin
    IdentityFile ~/.ssh/pi_cluster
    IdentitiesOnly yes

# Wildcard for all Pi hosts
Host pi-* rpi-*
    User admin
    IdentityFile ~/.ssh/pi_cluster
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
# End Pi Cluster

EOF

    print_success "SSH config updated"
    print_info "You can now use shortcuts like: ssh pi-master"
}

# Main execution
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   SSH Key Setup for Pi Cluster             ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""

# Check for key
check_key

# Define hosts
declare -A CLUSTER_HOSTS=(
    ["pi-master"]="192.168.1.240"
    ["pi-worker-01"]="192.168.1.241"
    ["pi-worker-02"]="192.168.1.242"
    ["pi-worker-03"]="192.168.1.243"
    ["pi-worker-04"]="192.168.1.244"
    ["pi-worker-05"]="192.168.1.245"
    ["pi-worker-06"]="192.168.1.246"
    ["pi-worker-07"]="192.168.1.247"
)

declare -A PIHOLE_HOSTS=(
    ["rpi-vpn-1 (Primary)"]="192.168.1.25"
    ["rpi-vpn-2 (Secondary)"]="192.168.1.26"
)

# Parse arguments
MODE="test"
UPDATE_CONFIG=false

if [ $# -eq 0 ]; then
    usage
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -a|--all)
            MODE="all"
            shift
            ;;
        -c|--cluster)
            MODE="cluster"
            shift
            ;;
        -p|--pihole)
            MODE="pihole"
            shift
            ;;
        -t|--test)
            MODE="test"
            shift
            ;;
        --update-config)
            UPDATE_CONFIG=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Update SSH config if requested
if [ "$UPDATE_CONFIG" = true ]; then
    update_ssh_config
    echo ""
fi

# Execute based on mode
case $MODE in
    test)
        print_info "Testing SSH connectivity..."
        echo ""

        echo -e "${BLUE}═══ Cluster Nodes ═══${NC}"
        success=0
        total=0
        for name in "${!CLUSTER_HOSTS[@]}"; do
            total=$((total + 1))
            if test_ssh "${CLUSTER_HOSTS[$name]}" "$name"; then
                success=$((success + 1))
            fi
        done
        echo ""

        echo -e "${BLUE}═══ Pi-hole Servers ═══${NC}"
        for name in "${!PIHOLE_HOSTS[@]}"; do
            total=$((total + 1))
            if test_ssh "${PIHOLE_HOSTS[$name]}" "$name"; then
                success=$((success + 1))
            fi
        done
        echo ""

        print_info "Results: $success/$total hosts accessible"

        if [ $success -eq $total ]; then
            print_success "All hosts accessible!"
        else
            print_warning "Some hosts are not accessible. Run with --all to setup SSH keys."
        fi
        ;;

    cluster)
        print_info "Setting up SSH keys for cluster nodes..."
        echo ""

        failed=0
        for name in "${!CLUSTER_HOSTS[@]}"; do
            if ! copy_key "${CLUSTER_HOSTS[$name]}" "$name"; then
                failed=$((failed + 1))
            fi
        done

        echo ""
        if [ $failed -eq 0 ]; then
            print_success "All cluster nodes configured!"
        else
            print_warning "$failed hosts failed. Try running again or manually."
        fi
        ;;

    pihole)
        print_info "Setting up SSH keys for Pi-hole servers..."
        echo ""

        failed=0
        for name in "${!PIHOLE_HOSTS[@]}"; do
            if ! copy_key "${PIHOLE_HOSTS[$name]}" "$name"; then
                failed=$((failed + 1))
            fi
        done

        echo ""
        if [ $failed -eq 0 ]; then
            print_success "All Pi-hole servers configured!"
        else
            print_warning "$failed hosts failed. Try running again or manually."
        fi
        ;;

    all)
        print_info "Setting up SSH keys for all hosts..."
        echo ""

        echo -e "${BLUE}═══ Cluster Nodes ═══${NC}"
        cluster_failed=0
        for name in "${!CLUSTER_HOSTS[@]}"; do
            if ! copy_key "${CLUSTER_HOSTS[$name]}" "$name"; then
                cluster_failed=$((cluster_failed + 1))
            fi
        done
        echo ""

        echo -e "${BLUE}═══ Pi-hole Servers ═══${NC}"
        pihole_failed=0
        for name in "${!PIHOLE_HOSTS[@]}"; do
            if ! copy_key "${PIHOLE_HOSTS[$name]}" "$name"; then
                pihole_failed=$((pihole_failed + 1))
            fi
        done
        echo ""

        total_failed=$((cluster_failed + pihole_failed))
        if [ $total_failed -eq 0 ]; then
            print_success "All hosts configured successfully!"
        else
            print_warning "$total_failed hosts failed. Try running again or manually."
        fi
        ;;
esac

echo ""
print_info "Next steps:"
echo "  1. Test connectivity: $0 --test"
echo "  2. Update SSH config: $0 --update-config"
echo "  3. Try: ssh pi-master"
echo "  4. Run Ansible playbooks without passwords!"
echo ""
