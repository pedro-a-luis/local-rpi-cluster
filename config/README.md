# Configuration Directory

Centralized configuration files and templates for the cluster.

## Environment Configuration

### .env.example
Template for environment variables. Copy to `.env` in project root and customize:

```bash
cp config/.env.example ../.env
# Edit .env with your specific values
```

**Note**: The actual `.env` file is kept in the project root and is gitignored for security.

## Configuration Guidelines

### Sensitive Data
- **NEVER** commit credentials to version control
- Use Ansible Vault for encrypted secrets: `ansible/vault-template.yml`
- Keep `.env` file in root directory (gitignored)

### Environment Variables
Common variables used across deployments:
- Database credentials (PostgreSQL, MinIO)
- API keys and tokens
- Service endpoints
- Resource limits

## Ansible Configuration

Ansible-specific configuration is located in:
- **Playbooks**: `../ansible/playbooks/`
- **Variables**: `../ansible/vars/main.yml`
- **Inventory**: `../ansible/inventory.yml`
- **Vault Template**: `../ansible/vault-template.yml`

## Kubernetes Configuration

Kubernetes manifests and Helm values files are typically stored alongside their deployment documentation:
- Airflow: See [../docs/deployment/airflow.md](../docs/deployment/airflow.md)
- PostgreSQL: See [../docs/deployment/postgresql.md](../docs/deployment/postgresql.md)
- MinIO: Referenced in [../docs/operations/backup-recovery.md](../docs/operations/backup-recovery.md)

## Security Best Practices

1. **Credential Rotation**: Rotate credentials regularly (see [Security Remediation Guide](../docs/security/remediation.md))
2. **Encryption**: Use Ansible Vault for all sensitive data in playbooks
3. **Access Control**: Limit file permissions on configuration files
4. **Separation**: Keep production and development configs separate

## Related Documentation

- [Ansible Guide](../docs/operations/ansible-guide.md) - Ansible configuration details
- [Security Audit](../docs/security/audit.md) - Configuration security findings
- [Backup Guide](../docs/operations/backup-recovery.md) - Backup configuration
