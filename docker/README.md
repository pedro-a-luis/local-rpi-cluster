# Synology Homelab Docker Compose Stack

Complete Docker Compose configuration for your Synology DS723+ homelab infrastructure.

## Architecture

### Shared Services
- **PostgreSQL 15** - Shared database server for all applications
- **homelab network** - Bridge network for inter-container communication

### Applications

#### Productivity & Collaboration
- **Nextcloud** - File sharing and collaboration (port 8080)
- **GitLab** - Git repository and DevOps platform (port 8081, SSH 2222)
- **OpenProject** - Project management (port 8082)

#### Security & Tools
- **Vaultwarden** - Password manager, Bitwarden-compatible (port 8083)
- **Portainer** - Docker management UI (port 9000)
- **Stirling-PDF** - PDF manipulation tools (port 8086)

## Prerequisites

1. **Synology NAS** with Docker installed
2. **.env file** - Already present at `/volume1/docker/.env` with all credentials
3. **SSH access** to Synology NAS
4. **Disk space** - At least 50GB free for application data

## Deployment

### 1. Copy files to Synology

```bash
# From your local machine
scp -r /root/gitlab/local-rpi-cluster/docker/* synology-ds723@192.168.1.20:/volume1/docker/
```

### 2. Set permissions

```bash
# SSH to Synology
ssh synology-ds723@192.168.1.20

# Make init script executable
chmod +x /volume1/docker/init-db.sh

# Set .env permissions
chmod 600 /volume1/docker/.env
```

### 3. Deploy the stack

```bash
# Navigate to docker directory
cd /volume1/docker

# Start all services (database will initialize on first run)
docker compose up -d

# Check status
docker compose ps

# View logs
docker compose logs -f
```

### 4. First-time database initialization

The database initialization happens automatically when PostgreSQL starts for the first time. The `init-db.sh` script creates:

- All application databases
- All application users
- Proper permissions and ownership

**Databases created:**
- `nextcloud_db` (user: `nextcloud_user`)
- `gitlab_db` (user: `gitlab_user`)
- `openproject_db` (user: `openproject_user`)
- `bitwarden_db` (user: `bitwarden_user`)
- `ezbookkeeping_db` (user: `ezbookkeeping_user`)
- `calibre_db` (user: `calibre_user`)
- `reactive_resume_db` (user: `reactive_resume_user`)
- `immich_db` (user: `immich_user`)

### 5. Access applications

All applications should be accessible via:

- **Nextcloud**: http://192.168.1.20:8080
- **GitLab**: http://192.168.1.20:8081
- **OpenProject**: http://192.168.1.20:8082
- **Vaultwarden**: http://192.168.1.20:8083
- **Portainer**: http://192.168.1.20:9000
- **Stirling-PDF**: http://192.168.1.20:8086

### 6. Configure Synology Reverse Proxy

For HTTPS access via subdomains (e.g., nextcloud.stratdata.org):

1. Open Synology **Control Panel** > **Login Portal** > **Advanced** > **Reverse Proxy**
2. Create rules for each application:

| Source (HTTPS) | Destination |
|----------------|-------------|
| nextcloud.stratdata.org:443 | localhost:8080 |
| gitlab.stratdata.org:443 | localhost:8081 |
| openproject.stratdata.org:443 | localhost:8082 |
| bitwarden.stratdata.org:443 | localhost:8083 |
| portainer.stratdata.org:443 | localhost:9000 |

**Important for Portainer**: Enable WebSocket in Custom Headers for the reverse proxy rule.

## Management Commands

### View all containers
```bash
docker compose ps
```

### View logs
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f nextcloud
```

### Restart a service
```bash
docker compose restart nextcloud
```

### Stop all services
```bash
docker compose down
```

### Stop and remove volumes (DANGER: data loss!)
```bash
docker compose down -v
```

### Update images
```bash
# Pull latest images
docker compose pull

# Recreate containers with new images
docker compose up -d
```

### Database backup
```bash
# Backup all databases
docker exec postgres-shared pg_dumpall -U postgres > backup-$(date +%Y%m%d).sql

# Backup specific database
docker exec postgres-shared pg_dump -U postgres nextcloud_db > nextcloud-backup-$(date +%Y%m%d).sql
```

### Database restore
```bash
# Restore all databases
docker exec -i postgres-shared psql -U postgres < backup-20251006.sql

# Restore specific database
docker exec -i postgres-shared psql -U postgres nextcloud_db < nextcloud-backup-20251006.sql
```

## Troubleshooting

### Check container health
```bash
docker compose ps
docker inspect <container_name> | grep -A 10 Health
```

### Database connection issues
```bash
# Check if PostgreSQL is running
docker compose ps postgres-shared

# Test database connection
docker exec postgres-shared psql -U postgres -c '\l'

# Check database users
docker exec postgres-shared psql -U postgres -c '\du'

# Test specific user connection
docker exec postgres-shared psql -U nextcloud_user -d nextcloud_db -c 'SELECT 1;'
```

### Application won't start
```bash
# Check logs for errors
docker compose logs <service_name>

# Restart the service
docker compose restart <service_name>

# Recreate the service
docker compose up -d --force-recreate <service_name>
```

### Network issues
```bash
# Inspect the network
docker network inspect homelab

# Check if containers can communicate
docker exec nextcloud ping postgres-shared
```

### Reset a specific application
```bash
# Stop the service
docker compose stop nextcloud

# Remove the container
docker compose rm -f nextcloud

# Remove the volume (DANGER: data loss!)
docker volume rm docker_nextcloud_data

# Recreate
docker compose up -d nextcloud
```

## Security Recommendations

1. **Change all default passwords** in `.env` file
2. **Enable firewall** rules to restrict access
3. **Use HTTPS** via Synology reverse proxy with Let's Encrypt
4. **Regular backups** of PostgreSQL databases
5. **Update images** regularly for security patches
6. **Disable signups** on public-facing services (Vaultwarden, GitLab)
7. **Use strong admin tokens** for Vaultwarden and GitLab

## Environment Variables

All credentials are stored in `/volume1/docker/.env`. Key variables:

```bash
# Database
POSTGRES_ROOT_PASSWORD=L0g1n@P0stgr3s
POSTGRES_PORT=5433

# Application credentials
DB_PASS_NEXTCLOUD=L0g1n%N3xtcl0ud
DB_PASS_GITLAB=L0g1n%G1tl%b
DB_PASS_BITWARDEN=L0g1nB1twrd3n
# ... etc

# Admin passwords
NEXTCLOUD_ADMIN_PASSWORD=L0g1n@N3xtcl0ud
GITLAB_ROOT_PASSWORD=L0g1n@G1tl@b
OPENPROJECT_ADMIN_PASSWORD=L0g1n@0p3npr0j3ct
```

## Resource Usage

Expected resource consumption on Synology DS723+:

- **PostgreSQL**: 200-500MB RAM
- **Nextcloud**: 200-400MB RAM
- **GitLab**: 2-4GB RAM (largest consumer)
- **OpenProject**: 500MB-1GB RAM
- **Vaultwarden**: 50-100MB RAM
- **Portainer**: 50-100MB RAM

**Total**: ~3.5-6GB RAM usage

## Notes

- GitLab requires significant resources; consider running on dedicated hardware for production
- First startup takes 5-10 minutes for all services to initialize
- Database initialization only runs on first PostgreSQL container creation
- All data persists in Docker volumes
- Backups should be automated via cron or Synology Task Scheduler
