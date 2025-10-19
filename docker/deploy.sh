#!/bin/bash
set -e

# Deployment script for Synology Homelab Docker Stack
# This script deploys the docker-compose stack to your Synology NAS

SYNOLOGY_HOST="192.168.1.20"
SYNOLOGY_USER="synology-ds723"
SYNOLOGY_PASSWORD="Xd9auP\$W@eX3"
REMOTE_DIR="/volume1/docker"
LOCAL_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=========================================="
echo "Synology Homelab Deployment Script"
echo "=========================================="
echo ""
echo "Source: $LOCAL_DIR"
echo "Target: $SYNOLOGY_USER@$SYNOLOGY_HOST:$REMOTE_DIR"
echo ""

# Function to run remote commands
remote_cmd() {
    sshpass -p "$SYNOLOGY_PASSWORD" ssh -o StrictHostKeyChecking=no $SYNOLOGY_USER@$SYNOLOGY_HOST "$1"
}

remote_sudo() {
    sshpass -p "$SYNOLOGY_PASSWORD" ssh -o StrictHostKeyChecking=no $SYNOLOGY_USER@$SYNOLOGY_HOST "echo \"$SYNOLOGY_PASSWORD\" | sudo -S $1"
}

# Check if we can reach Synology
echo "→ Testing connection to Synology NAS..."
if ! remote_cmd "echo 'Connection successful'"; then
    echo "✗ Failed to connect to Synology NAS"
    exit 1
fi
echo "✓ Connection successful"
echo ""

# Run pre-deployment check
echo "→ Running pre-deployment check..."
if [ -f "$LOCAL_DIR/pre-deploy-check.sh" ]; then
    bash "$LOCAL_DIR/pre-deploy-check.sh"
    if [ $? -ne 0 ]; then
        echo "✗ Pre-deployment check failed or cancelled"
        exit 1
    fi
else
    echo "⚠️  Pre-deployment check script not found, skipping..."
fi
echo ""

# Create backup of existing setup
echo "→ Creating backup of existing configuration..."
BACKUP_DIR="$REMOTE_DIR/backup-$(date +%Y%m%d-%H%M%S)"
remote_sudo "mkdir -p $BACKUP_DIR"
remote_sudo "[ -f $REMOTE_DIR/docker-compose.yml ] && cp $REMOTE_DIR/docker-compose.yml $BACKUP_DIR/ || true"
remote_sudo "[ -f $REMOTE_DIR/init-db.sh ] && cp $REMOTE_DIR/init-db.sh $BACKUP_DIR/ || true"
echo "✓ Backup created at $BACKUP_DIR"
echo ""

# Copy .env file to Synology if it doesn't exist
echo "→ Checking .env file..."
if ! remote_sudo "[ -f $REMOTE_DIR/.env ]"; then
    echo "  .env file not found on Synology"
    if [ -f "$LOCAL_DIR/../.env" ]; then
        echo "  Copying .env from local..."
        sshpass -p "$SYNOLOGY_PASSWORD" scp -o StrictHostKeyChecking=no "$LOCAL_DIR/../.env" $SYNOLOGY_USER@$SYNOLOGY_HOST:/tmp/.env
        remote_sudo "mv /tmp/.env $REMOTE_DIR/.env"
        remote_sudo "chmod 600 $REMOTE_DIR/.env"
        echo "✓ .env file copied"
    else
        echo "✗ .env file not found locally either. Please create it."
        exit 1
    fi
else
    echo "✓ .env file exists"
fi
echo ""

# Copy docker-compose.yml
echo "→ Copying docker-compose.yml..."
sshpass -p "$SYNOLOGY_PASSWORD" scp -o StrictHostKeyChecking=no "$LOCAL_DIR/docker-compose.yml" $SYNOLOGY_USER@$SYNOLOGY_HOST:/tmp/
remote_sudo "mv /tmp/docker-compose.yml $REMOTE_DIR/"
echo "✓ docker-compose.yml copied"

# Copy init-db.sh
echo "→ Copying init-db.sh..."
sshpass -p "$SYNOLOGY_PASSWORD" scp -o StrictHostKeyChecking=no "$LOCAL_DIR/init-db.sh" $SYNOLOGY_USER@$SYNOLOGY_HOST:/tmp/
remote_sudo "mv /tmp/init-db.sh $REMOTE_DIR/"
remote_sudo "chmod +x $REMOTE_DIR/init-db.sh"
echo "✓ init-db.sh copied"
echo ""

# Ask if user wants to stop existing containers
echo "=========================================="
read -p "Stop and remove existing containers? (y/n): " -n 1 -r
echo ""
echo "=========================================="
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "→ Stopping existing containers..."
    remote_sudo "cd $REMOTE_DIR && /usr/local/bin/docker compose down || true"
    echo "✓ Containers stopped"
    echo ""
fi

# Ask if user wants to start the stack
echo "=========================================="
read -p "Start the Docker stack now? (y/n): " -n 1 -r
echo ""
echo "=========================================="
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "→ Starting Docker stack..."
    echo "  This may take 5-10 minutes for first-time initialization..."
    remote_sudo "cd $REMOTE_DIR && /usr/local/bin/docker compose up -d"
    echo "✓ Docker stack started"
    echo ""

    echo "→ Waiting 10 seconds for containers to initialize..."
    sleep 10

    echo "→ Checking container status..."
    remote_sudo "cd $REMOTE_DIR && /usr/local/bin/docker compose ps"
    echo ""
fi

echo "=========================================="
echo "Deployment Summary"
echo "=========================================="
echo ""
echo "Files deployed:"
echo "  - docker-compose.yml → $REMOTE_DIR/docker-compose.yml"
echo "  - init-db.sh → $REMOTE_DIR/init-db.sh"
echo "  - .env → $REMOTE_DIR/.env"
echo ""
echo "Backup location: $BACKUP_DIR"
echo ""
echo "Access your applications:"
echo "  - Nextcloud:     http://192.168.1.20:8080"
echo "  - GitLab:        http://192.168.1.20:8081"
echo "  - OpenProject:   http://192.168.1.20:8082"
echo "  - Vaultwarden:   http://192.168.1.20:8083"
echo "  - Portainer:     http://192.168.1.20:9000"
echo "  - Stirling-PDF:  http://192.168.1.20:8086"
echo ""
echo "Useful commands:"
echo "  View logs:       ssh $SYNOLOGY_USER@$SYNOLOGY_HOST 'cd $REMOTE_DIR && sudo docker compose logs -f'"
echo "  Check status:    ssh $SYNOLOGY_USER@$SYNOLOGY_HOST 'cd $REMOTE_DIR && sudo docker compose ps'"
echo "  Restart service: ssh $SYNOLOGY_USER@$SYNOLOGY_HOST 'cd $REMOTE_DIR && sudo docker compose restart <service>'"
echo ""
echo "=========================================="
echo "✓ Deployment complete!"
echo "=========================================="
