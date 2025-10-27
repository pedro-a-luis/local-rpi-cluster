#!/bin/bash
# Pi-hole Update Script
# Convenient wrapper for the update-pihole.yml Ansible playbook

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PLAYBOOK="$PROJECT_ROOT/ansible/playbooks/infrastructure/update-pihole.yml"

# Function to print colored messages
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
Pi-hole Update Script

Usage: $0 [OPTIONS]

Options:
    -h, --help              Show this help message
    -a, --all               Update both Pi-hole servers (default)
    -p, --primary           Update primary only (rpi-vpn-1)
    -s, --secondary         Update secondary only (rpi-vpn-2)
    -c, --check             Check for updates without applying (dry run)
    -v, --verbose           Verbose output
    -d, --dns-only          Update gravity database only (no OS updates)
    --status                Check Pi-hole status on both servers

Examples:
    $0                      # Update both servers (one at a time)
    $0 --secondary          # Update secondary first (safer)
    $0 --primary            # Update primary only
    $0 --check              # See what would be updated
    $0 --status             # Check current status

Servers:
    Primary:   rpi-vpn-1 (192.168.1.25)
    Secondary: rpi-vpn-2 (192.168.1.26)

EOF
}

# Function to check SSH connectivity
check_ssh() {
    local host=$1
    print_info "Checking SSH connectivity to $host..."

    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@$host "exit" 2>/dev/null; then
        print_success "SSH connection to $host successful"
        return 0
    else
        print_error "Cannot connect to $host via SSH"
        print_warning "Make sure SSH keys are configured: ssh-copy-id admin@$host"
        return 1
    fi
}

# Function to check Pi-hole status
check_status() {
    print_info "Checking Pi-hole status..."
    echo ""

    for server in "192.168.1.25" "192.168.1.26"; do
        echo -e "${BLUE}═══════════════════════════════════════════${NC}"
        if [ "$server" == "192.168.1.25" ]; then
            echo -e "${BLUE}Pi-hole Primary (rpi-vpn-1) - $server${NC}"
        else
            echo -e "${BLUE}Pi-hole Secondary (rpi-vpn-2) - $server${NC}"
        fi
        echo -e "${BLUE}═══════════════════════════════════════════${NC}"

        if check_ssh $server; then
            echo ""
            echo "Version:"
            ssh admin@$server "pihole -v 2>/dev/null | grep -E 'Pi-hole|AdminLTE|FTL'" || echo "  Unable to get version"
            echo ""
            echo "Status:"
            ssh admin@$server "pihole status 2>/dev/null" || echo "  Unable to get status"
            echo ""
            echo "Updates Available:"
            ssh admin@$server "sudo apt update >/dev/null 2>&1 && apt list --upgradable 2>/dev/null | grep -v 'WARNING' | wc -l" || echo "  Unable to check"
            echo ""
        fi
    done

    print_info "DNS Resolution Test:"
    nslookup grafana.stratdata.org 192.168.1.25 2>/dev/null | grep -A1 "Name:" || print_error "Primary DNS not responding"
    nslookup grafana.stratdata.org 192.168.1.26 2>/dev/null | grep -A1 "Name:" || print_error "Secondary DNS not responding"
}

# Function to update gravity only
update_gravity() {
    print_info "Updating gravity database (blocklists) only..."
    ansible pihole -m shell -a "pihole -g" -b
}

# Parse arguments
TARGET="all"
DRY_RUN=""
VERBOSE=""
DNS_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -a|--all)
            TARGET="all"
            shift
            ;;
        -p|--primary)
            TARGET="rpi-vpn-1"
            shift
            ;;
        -s|--secondary)
            TARGET="rpi-vpn-2"
            shift
            ;;
        -c|--check)
            DRY_RUN="--check"
            shift
            ;;
        -v|--verbose)
            VERBOSE="-vv"
            shift
            ;;
        -d|--dns-only)
            DNS_ONLY=true
            shift
            ;;
        --status)
            check_status
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Main execution
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Pi-hole Update Script              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""

# Check if DNS only update
if [ "$DNS_ONLY" = true ]; then
    update_gravity
    exit 0
fi

# Check playbook exists
if [ ! -f "$PLAYBOOK" ]; then
    print_error "Playbook not found: $PLAYBOOK"
    exit 1
fi

# Check SSH connectivity
print_info "Pre-flight checks..."

if [ "$TARGET" == "all" ]; then
    check_ssh "192.168.1.25" || exit 1
    check_ssh "192.168.1.26" || exit 1
elif [ "$TARGET" == "rpi-vpn-1" ]; then
    check_ssh "192.168.1.25" || exit 1
elif [ "$TARGET" == "rpi-vpn-2" ]; then
    check_ssh "192.168.1.26" || exit 1
fi

print_success "Pre-flight checks passed"
echo ""

# Display update plan
print_info "Update Plan:"
if [ "$TARGET" == "all" ]; then
    echo "  • Target: Both Pi-hole servers (one at a time)"
    echo "  • Order: rpi-vpn-2 (secondary) → rpi-vpn-1 (primary)"
elif [ "$TARGET" == "rpi-vpn-1" ]; then
    echo "  • Target: Primary Pi-hole only (rpi-vpn-1 / 192.168.1.25)"
else
    echo "  • Target: Secondary Pi-hole only (rpi-vpn-2 / 192.168.1.26)"
fi

if [ -n "$DRY_RUN" ]; then
    echo "  • Mode: DRY RUN (no changes will be made)"
else
    echo "  • Mode: LIVE UPDATE"
fi

echo ""

# Confirmation prompt (skip for dry run)
if [ -z "$DRY_RUN" ]; then
    read -p "$(echo -e ${YELLOW}Continue with update? [y/N]:${NC} )" -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Update cancelled by user"
        exit 0
    fi
    echo ""
fi

# Run the playbook
print_info "Starting Pi-hole update..."
echo ""

ANSIBLE_CMD="ansible-playbook $PLAYBOOK"

if [ "$TARGET" != "all" ]; then
    ANSIBLE_CMD="$ANSIBLE_CMD --limit $TARGET"
fi

if [ -n "$DRY_RUN" ]; then
    ANSIBLE_CMD="$ANSIBLE_CMD $DRY_RUN"
fi

if [ -n "$VERBOSE" ]; then
    ANSIBLE_CMD="$ANSIBLE_CMD $VERBOSE"
fi

# Execute
if eval $ANSIBLE_CMD; then
    echo ""
    print_success "Pi-hole update completed successfully!"
    echo ""
    print_info "Post-update verification:"
    check_status
else
    echo ""
    print_error "Pi-hole update failed. Check the output above for details."
    exit 1
fi

echo ""
print_info "Recommendations:"
echo "  1. Check Pi-hole admin panels:"
echo "     http://192.168.1.25/admin"
echo "     http://192.168.1.26/admin"
echo "  2. Test DNS resolution from your workstation"
echo "  3. Verify ad blocking is working"
echo ""
