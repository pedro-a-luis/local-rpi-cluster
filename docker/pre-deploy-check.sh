#!/bin/bash
set -e

# Pre-deployment check script
# Checks for existing containers and their status before deploying

SYNOLOGY_HOST="192.168.1.20"
SYNOLOGY_USER="synology-ds723"
SYNOLOGY_PASSWORD="Xd9auP\$W@eX3"

echo "=========================================="
echo "Pre-Deployment Check"
echo "=========================================="
echo ""

# Function to run remote commands
remote_sudo() {
    sshpass -p "$SYNOLOGY_PASSWORD" ssh -o StrictHostKeyChecking=no $SYNOLOGY_USER@$SYNOLOGY_HOST "echo \"$SYNOLOGY_PASSWORD\" | sudo -S $1"
}

# List of containers in docker-compose
CONTAINERS=(
    "postgres-shared"
    "nextcloud-redis"
    "nextcloud"
    "nextcloud-cron"
    "vaultwarden"
    "portainer"
    "gitlab"
    "openproject"
    "stirling-pdf"
)

echo "→ Checking for existing containers on Synology..."
echo ""

EXISTING_CONTAINERS=()
NEW_CONTAINERS=()

for container in "${CONTAINERS[@]}"; do
    if remote_sudo "/usr/local/bin/docker ps -a --format '{{.Names}}' | grep -q '^${container}\$'"; then
        STATUS=$(remote_sudo "/usr/local/bin/docker ps -a --filter name=^${container}\$ --format '{{.Status}}'")
        EXISTING_CONTAINERS+=("$container")
        echo "  ✓ $container - EXISTS ($STATUS)"
    else
        NEW_CONTAINERS+=("$container")
        echo "  ○ $container - NEW"
    fi
done

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "Existing containers: ${#EXISTING_CONTAINERS[@]}"
echo "New containers: ${#NEW_CONTAINERS[@]}"
echo ""

if [ ${#EXISTING_CONTAINERS[@]} -gt 0 ]; then
    echo "Existing containers found:"
    for container in "${EXISTING_CONTAINERS[@]}"; do
        echo "  - $container"
    done
    echo ""
    echo "⚠️  WARNING: Existing containers will be recreated!"
    echo ""
    echo "Options:"
    echo "  1. Stop and remove existing containers, then deploy fresh"
    echo "  2. Keep existing containers and only deploy new ones"
    echo "  3. Cancel deployment"
    echo ""
    read -p "Choose option (1/2/3): " -n 1 -r
    echo ""
    echo ""

    case $REPLY in
        1)
            echo "→ Stopping and removing existing containers..."
            for container in "${EXISTING_CONTAINERS[@]}"; do
                echo "  Removing $container..."
                remote_sudo "/usr/local/bin/docker stop $container 2>/dev/null || true"
                remote_sudo "/usr/local/bin/docker rm $container 2>/dev/null || true"
            done
            echo "✓ Existing containers removed"
            echo ""
            echo "✓ Ready to deploy all containers"
            ;;
        2)
            echo "→ Keeping existing containers"
            echo ""
            echo "✓ Ready to deploy only new containers"
            echo ""
            echo "Note: To deploy new containers only, use:"
            echo "  docker compose up -d <service_name>"
            ;;
        3)
            echo "✗ Deployment cancelled"
            exit 0
            ;;
        *)
            echo "✗ Invalid option. Deployment cancelled"
            exit 1
            ;;
    esac
else
    echo "✓ No existing containers found. Ready for fresh deployment."
fi

echo ""
echo "→ Checking existing volumes..."
echo ""

VOLUMES=$(remote_sudo "/usr/local/bin/docker volume ls --format '{{.Name}}' | grep -E 'postgres_data|nextcloud|vaultwarden|portainer|gitlab|openproject' || true")

if [ -n "$VOLUMES" ]; then
    echo "Existing volumes found:"
    echo "$VOLUMES" | while read vol; do
        SIZE=$(remote_sudo "/usr/local/bin/docker volume inspect $vol --format '{{.Mountpoint}}' | xargs du -sh 2>/dev/null | cut -f1 || echo 'N/A'")
        echo "  - $vol ($SIZE)"
    done
    echo ""
    echo "ℹ️  Existing volumes will be reused (data preserved)"
else
    echo "✓ No existing volumes found. Fresh volumes will be created."
fi

echo ""
echo "→ Checking PostgreSQL database status..."
echo ""

if remote_sudo "/usr/local/bin/docker ps --filter name=^postgres-shared\$ --format '{{.Names}}' | grep -q postgres-shared"; then
    echo "✓ PostgreSQL container is running"
    echo ""
    echo "  Checking databases..."
    DATABASES=$(remote_sudo "/usr/local/bin/docker exec postgres-shared psql -U postgres -c '\l' 2>/dev/null | grep -E 'nextcloud_db|gitlab_db|openproject_db|bitwarden_db' || echo 'None'")
    if [ "$DATABASES" != "None" ]; then
        echo "  Existing databases found:"
        echo "$DATABASES" | while IFS= read -r line; do
            echo "    $line"
        done
        echo ""
        echo "  ⚠️  Existing databases will be REUSED"
        echo "     Database initialization script will skip existing databases"
    else
        echo "  ○ No application databases found"
        echo "     Databases will be created during deployment"
    fi
else
    echo "○ PostgreSQL container not running"
    echo "   Fresh PostgreSQL will be deployed"
fi

echo ""
echo "=========================================="
echo "Pre-Deployment Check Complete"
echo "=========================================="
