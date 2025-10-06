# Raspberry Pi K3s Cluster - Access Guide

## Network Setup

**Synology DS723+**: `192.168.1.20`
- DNS Server (BIND 9.16.34)
- NFS Storage (2TB NVMe)
- Let's Encrypt Certificate Authority

**Pi K3s Cluster**: `192.168.1.240` (master)
- Workers: 192.168.1.241-247
- Cluster domain: `*.stratdata.org`

## DNS Configuration

**DNS Server**: Synology DS723+ at 192.168.1.20

All `*.stratdata.org` subdomains resolve to cluster master (192.168.1.240).

**Client Configuration Options**:

1. **Network-wide** (recommended): Set router DNS to 192.168.1.20
2. **Per-machine**: Add to hosts file:
   - Windows: `C:\Windows\System32\drivers\etc\hosts`
   - Linux/Mac: `/etc/hosts`

```
192.168.1.240  grafana.stratdata.org
192.168.1.240  longhorn.stratdata.org
192.168.1.240  code.stratdata.org
```

See [dns-setup-guide.md](dns-setup-guide.md) for detailed instructions.

## Active Services

✅ **Grafana** - https://grafana.stratdata.org
- Username: `admin`
- Password: `Grafana123`
- Monitoring dashboards and metrics

✅ **Longhorn** - https://longhorn.stratdata.org
- Distributed storage management
- Volume management and backups

✅ **Code Server** - https://code.stratdata.org
- Web-based VS Code IDE

## SSL Certificates

**Status**: ✅ Trusted Let's Encrypt wildcard certificate

All services use a **Let's Encrypt wildcard certificate** (`*.stratdata.org`):
- Issuer: Let's Encrypt (E6)
- Valid until: Oct 18, 2025
- **No browser warnings** - fully trusted certificate

The certificate is automatically renewed by Synology DSM and exported to the cluster.

## WireGuard External Access

**Server**: `10.116.24.1:51820` (on pi-master)

After connecting via WireGuard, access services at `*.stratdata.org`

## Quick Commands

**SSH to cluster master:**
```bash
ssh -i ~/.ssh/pi_cluster admin@192.168.1.240
```

**Check cluster status:**
```bash
kubectl get nodes
kubectl top nodes
kubectl get pods -A
```

**View services and ingress:**
```bash
kubectl get svc -A
kubectl get ingress -A
```

**View certificates:**
```bash
kubectl get certificate -A
kubectl get secret -A | grep tls
```

**Check Traefik ingress:**
```bash
kubectl logs -n traefik -l app.kubernetes.io/name=traefik --tail=50
```

## Storage

**NFS Storage** (Synology DS118 - 192.168.1.10):
- 7.3TB available
- Mounted via NFS provisioner

**Longhorn Distributed Storage**:
- 1.7TB total (distributed across nodes)
- Access UI: https://longhorn.stratdata.org
- Automatic backups and replication

## Credentials Summary

**Grafana**:
- URL: https://grafana.stratdata.org
- Username: `admin`
- Password: `Grafana123`

**Synology DS723+**:
- URL: https://192.168.1.20:5001
- Username: `synology-ds723`
- SSH Access: `ssh synology-ds723@192.168.1.20`

**Pi Cluster SSH**:
- User: `admin`
- Key: `~/.ssh/pi_cluster`
- Master: `ssh -i ~/.ssh/pi_cluster admin@192.168.1.240`
