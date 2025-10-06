# Security Hardening Playbooks

This directory contains Ansible playbooks for implementing security hardening across the infrastructure.

## Overview

These playbooks implement the security remediation plan from [SECURITY-REMEDIATION-GUIDE.md](../../../SECURITY-REMEDIATION-GUIDE.md).

## Playbooks

### 1. firewall-setup.yml
**Purpose**: Configure UFW firewall rules on all nodes

**Implements**:
- Default deny ingress policy
- Allow SSH from LAN only
- K3s API restricted to cluster nodes
- Traefik ingress on master only
- Pi-hole DNS services
- WireGuard VPN

**Usage**:
```bash
# Dry run
ansible-playbook ansible/playbooks/security/firewall-setup.yml --check

# Deploy to Pi-hole servers only
ansible-playbook ansible/playbooks/security/firewall-setup.yml --limit pihole

# Deploy to all systems
ansible-playbook ansible/playbooks/security/firewall-setup.yml
```

**CAUTION**: Ensure console access before running. Misconfigured firewall rules can lock you out.

---

### 2. ssh-harden.yml
**Purpose**: Harden SSH configuration and install fail2ban

**Implements**:
- Disable password authentication
- Require public key authentication
- Disable root login
- Strong ciphers/MACs/KexAlgorithms only
- fail2ban for brute-force protection
- SSH banner
- Verbose logging

**Usage**:
```bash
# Dry run
ansible-playbook ansible/playbooks/security/ssh-harden.yml --check

# Deploy
ansible-playbook ansible/playbooks/security/ssh-harden.yml
```

**PREREQUISITE**: Ensure SSH keys are deployed and working before running!

**Verification**:
```bash
# Test key-based auth (should work)
ssh -i ~/.ssh/pi_cluster admin@192.168.1.240

# Test password auth (should fail)
ssh -o PreferredAuthentications=password admin@192.168.1.240
```

---

### 3. k3s-pod-security.yml
**Purpose**: Implement Pod Security Standards in K3s cluster

**Implements**:
- Pod Security Admission configuration
- Baseline enforcement for user namespaces
- Restricted audit/warn policies
- Privileged policy for system namespaces
- Audit logging
- Kubelet read-only port disabled

**Usage**:
```bash
ansible-playbook ansible/playbooks/security/k3s-pod-security.yml
```

**Pod Security Levels**:
- **privileged**: kube-system, longhorn-system (unrestricted)
- **baseline**: monitoring, logging, dev-tools, databases, cert-manager
- **restricted**: default namespace (recommended for user workloads)

**Verification**:
```bash
# Check namespace labels
kubectl get namespaces --show-labels | grep pod-security

# Try to create privileged pod (should be denied in default namespace)
kubectl run test --image=nginx --privileged
```

---

### 4. network-policies.yml
**Purpose**: Deploy network policies for namespace isolation

**Note**: This is a Kubernetes manifest file, not an Ansible playbook.

**Implements**:
- Default deny-all policies for most namespaces
- Explicit allow rules for required traffic
- Zero-trust networking model
- Ingress/egress isolation

**Usage**:
```bash
# Apply network policies
kubectl apply -f ansible/playbooks/security/network-policies.yml

# Verify
kubectl get networkpolicies -A
```

**Policy Structure**:
- Each namespace gets a default-deny-all policy
- Specific allow policies for:
  - Grafana ← Traefik ingress
  - Prometheus ← Grafana, node exporters
  - Loki ← Promtail, Grafana
  - Code Server ← Traefik ingress

**Testing**:
```bash
# This should timeout (network policy blocking)
kubectl run test-curl --image=curlimages/curl --rm -it -- \
  curl -m 5 http://prometheus.monitoring:9090
```

---

## Security Checklist

### Before Running Any Playbook:
- [ ] Backup current configurations
- [ ] Ensure console/physical access to systems
- [ ] Test in dry-run mode (`--check`)
- [ ] Review changes in dry-run output
- [ ] Have rollback plan ready

### After Running Playbooks:
- [ ] Verify services still work
- [ ] Test SSH access
- [ ] Test HTTPS access to services
- [ ] Check firewall status: `sudo ufw status verbose`
- [ ] Check fail2ban: `sudo fail2ban-client status sshd`
- [ ] Review K3s status: `kubectl get nodes`

---

## Rollback Procedures

### Firewall Lockout:
```bash
# Access via console
sudo ufw disable

# Fix rules
sudo ufw reset
```

### SSH Lockout:
```bash
# Access via console
sudo nano /etc/ssh/sshd_config
# Set: PasswordAuthentication yes
sudo systemctl restart ssh
```

### K3s Pod Security Issues:
```bash
# Remove admission config
sudo mv /etc/rancher/k3s/config.yaml /etc/rancher/k3s/config.yaml.backup
sudo systemctl restart k3s
```

### Network Policy Blocking:
```bash
# Remove all network policies
kubectl delete networkpolicies --all -A

# Or specific namespace
kubectl delete networkpolicies --all -n monitoring
```

---

## Integration with Security Audit

These playbooks implement fixes for:

### Critical Issues (🔴):
- ✅ Firewall rules (No network segmentation)
- ✅ SSH hardening (Password authentication enabled)
- ✅ Pod Security Standards (No PSP/PSS)

### High Issues (🟠):
- ✅ Kubelet read-only port (Exposed)
- ✅ SSH keys (Excessive authorized_keys)

### Medium Issues (🟡):
- ✅ Network policies (Limited isolation)

---

## Additional Security Measures

### Not Included in Playbooks (Manual Steps Required):

1. **Ansible Vault** - See [vault-template.yml](../../vault-template.yml)
2. **Let's Encrypt Certificate** - Configure on Synology or use cert-manager
3. **VNC Disabling** - `systemctl disable vncserver-x11-serviced`
4. **NFS Access Restriction** - Edit `/etc/exports` on Synology DS118
5. **etcd Encryption** - Manual configuration on K3s master
6. **Unknown Device Identification** - Manual network audit

---

## Monitoring & Validation

### Security Monitoring Commands:

```bash
# Check firewall logs
sudo grep UFW /var/log/syslog | tail -50

# Check fail2ban status
sudo fail2ban-client status sshd

# Check SSH auth attempts
sudo grep "Failed password" /var/log/auth.log | tail -20

# Check K3s audit log
sudo tail -f /var/log/k3s-audit.log

# Check pod security violations
kubectl get events -A | grep -i "forbidden.*pod security"

# Check network policy denials
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik | grep -i "denied"
```

### Regular Security Audits:

```bash
# Run security scan
nmap -sV -p- 192.168.1.240 --open

# Check for updates
ansible all -m apt -a "upgrade=safe update_cache=yes" --check

# Audit RBAC
kubectl auth can-i --list --as=system:serviceaccount:default:default

# Check secrets encryption
kubectl get secrets -A -o json | grep -i "data"
```

---

## See Also

- [SECURITY-AUDIT.md](../../../SECURITY-AUDIT.md) - Full security assessment
- [SECURITY-REMEDIATION-GUIDE.md](../../../SECURITY-REMEDIATION-GUIDE.md) - Remediation roadmap
- [vault-template.yml](../../vault-template.yml) - Ansible Vault template

---

**Last Updated**: October 6, 2025
**Maintained By**: Admin
