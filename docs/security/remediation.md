# Security Remediation Guide
**Priority Order Implementation Guide**

This guide provides step-by-step instructions to remediate all security findings from the security audit.

---

## 🔴 CRITICAL - Week 1 (Immediate Actions)

### Day 1: Rotate Exposed Credentials

**Issue**: Hardcoded passwords in Git repository

**Steps**:

1. **Change Synology Password**:
   ```bash
   # SSH to Synology
   ssh synology-ds723@192.168.1.20

   # Change password via DSM web interface:
   # https://192.168.1.20:5001
   # Control Panel → User → synology-ds723 → Edit → Change Password

   # New password: Generate strong password (20+ chars)
   # Save to password manager
   ```

2. **Change Pi-hole Passwords** (both servers):
   ```bash
   # SSH to Pi-hole 1
   ssh admin@192.168.1.25
   pihole -a -p
   # Enter new password (20+ chars)

   # Repeat for Pi-hole 2
   ssh admin@192.168.1.26
   pihole -a -p
   ```

3. **Setup Ansible Vault**:
   ```bash
   cd /root/gitlab/local-rpi-cluster

   # Create vault password file
   openssl rand -base64 32 > ~/.ansible-vault-password
   chmod 600 ~/.ansible-vault-password

   # Copy template and fill in NEW passwords
   cp ansible/vault-template.yml ansible/vault.yml
   nano ansible/vault.yml
   # Update all passwords with NEW values

   # Encrypt vault file
   ansible-vault encrypt ansible/vault.yml --vault-password-file ~/.ansible-vault-password

   # Add to .gitignore
   echo ".ansible-vault-password" >> .gitignore
   echo "ansible/vault.yml" >> .gitignore

   # Update ansible.cfg
   echo "[defaults]" >> ansible/ansible.cfg
   echo "vault_password_file = ~/.ansible-vault-password" >> ansible/ansible.cfg
   ```

4. **Update Playbooks to Use Vault**:

   Edit `ansible/playbooks/infrastructure/update-certificates.yml`:
   ```yaml
   vars_files:
     - ../../vault.yml
   vars:
     synology_host: "{{ vault_synology_host }}"
     synology_user: "{{ vault_synology_user }}"
     synology_password: "{{ vault_synology_password }}"
   ```

   Repeat for all 17 playbooks that reference credentials.

5. **Commit Changes** (vault.yml will be encrypted):
   ```bash
   git add .gitignore ansible.cfg ansible/vault.yml
   git commit -m "security: Migrate credentials to Ansible Vault"
   ```

**Verification**:
```bash
# Test vault decryption
ansible-vault view ansible/vault.yml

# Test playbook with vault
ansible-playbook ansible/playbooks/infrastructure/update-certificates.yml --syntax-check
```

---

### Day 2: Disable VNC and Kubelet Read-Only Port

**Issue**: VNC (5900) and Kubelet RO (10255) exposed

**Steps**:

1. **Disable VNC on pi-master**:
   ```bash
   ssh -i ~/.ssh/pi_cluster admin@192.168.1.240

   # Check if VNC is running
   sudo systemctl status vncserver-x11-serviced.service || \
   sudo systemctl status vncserver@.service

   # Disable VNC
   sudo systemctl stop vncserver-x11-serviced.service
   sudo systemctl disable vncserver-x11-serviced.service

   # Or if using different VNC service:
   sudo systemctl stop vncserver@:1.service
   sudo systemctl disable vncserver@:1.service

   # Verify port 5900 is closed
   sudo netstat -tuln | grep 5900  # Should return nothing
   ```

2. **Disable Kubelet Read-Only Port**:

   Run the Pod Security playbook (includes this fix):
   ```bash
   cd /root/gitlab/local-rpi-cluster
   ansible-playbook ansible/playbooks/security/k3s-pod-security.yml
   ```

   Or manual fix:
   ```bash
   ssh -i ~/.ssh/pi_cluster admin@192.168.1.240

   # Edit K3s config
   sudo mkdir -p /etc/rancher/k3s
   sudo nano /etc/rancher/k3s/config.yaml

   # Add:
   kubelet-arg:
   - "read-only-port=0"

   # Restart K3s
   sudo systemctl restart k3s

   # Verify port 10255 is closed
   sudo netstat -tuln | grep 10255  # Should return nothing
   ```

**Verification**:
```bash
# From external system:
nmap -p 5900,10255 192.168.1.240
# Both ports should show "closed" or "filtered"
```

---

### Day 3-4: Implement Firewall Rules

**Issue**: No firewall rules on any system

**Steps**:

1. **CAUTION**: Ensure console access before proceeding!

2. **Deploy Firewall Rules**:
   ```bash
   cd /root/gitlab/local-rpi-cluster

   # DRY RUN first to see what will change
   ansible-playbook ansible/playbooks/security/firewall-setup.yml --check

   # Review output carefully!

   # Deploy to Pi-hole servers first (test)
   ansible-playbook ansible/playbooks/security/firewall-setup.yml --limit pihole

   # Test SSH still works
   ssh admin@192.168.1.25
   exit

   # Deploy to K3s cluster
   ansible-playbook ansible/playbooks/security/firewall-setup.yml
   ```

3. **Verify Firewall Status**:
   ```bash
   # Check all nodes
   ansible all -m shell -a "sudo ufw status verbose" -i ansible/inventory/hosts.yml
   ```

4. **Test Services**:
   ```bash
   # Test DNS
   nslookup grafana.stratdata.org 192.168.1.25

   # Test HTTPS
   curl -I https://grafana.stratdata.org

   # Test K3s
   kubectl get nodes
   ```

**Rollback if needed**:
```bash
# Disable UFW on all nodes
ansible all -m shell -a "sudo ufw disable" -i ansible/inventory/hosts.yml
```

---

### Day 5: Obtain Real Let's Encrypt Certificate

**Issue**: Using self-signed Synology certificate

**Steps**:

1. **Configure Let's Encrypt on Synology DS723+**:
   - Login to DSM: https://192.168.1.20:5001
   - Control Panel → Security → Certificate
   - Click "Add" → "Add a new certificate"
   - Select "Get a certificate from Let's Encrypt"
   - Domain name: `*.stratdata.org`
   - Email: your-email@domain.com
   - Click "Apply"

   **Note**: This requires:
   - Domain ownership verification
   - DNS provider API access or DNS TXT record creation
   - Port 80 forwarded to Synology (temporarily for validation)

2. **Alternative - Use cert-manager in Cluster**:

   If Synology Let's Encrypt doesn't work with wildcards:

   ```bash
   kubectl apply -f - <<EOF
   apiVersion: cert-manager.io/v1
   kind: ClusterIssuer
   metadata:
     name: letsencrypt-prod
   spec:
     acme:
       server: https://acme-v02.api.letsencrypt.org/directory
       email: your-email@domain.com
       privateKeySecretRef:
         name: letsencrypt-prod
       solvers:
       - http01:
           ingress:
             class: traefik
   EOF

   # Update ingresses to use cert-manager
   kubectl annotate ingress -n monitoring grafana \
     cert-manager.io/cluster-issuer=letsencrypt-prod
   ```

3. **Verify Certificate**:
   ```bash
   openssl s_client -connect grafana.stratdata.org:443 < /dev/null 2>/dev/null | \
     openssl x509 -noout -issuer -dates

   # Should show:
   # issuer=C = US, O = Let's Encrypt, CN = E6
   # notAfter=(date 90 days in future)
   ```

---

### Day 6-7: Harden SSH & Setup Fail2ban

**Issue**: Password authentication enabled

**Steps**:

1. **Ensure SSH Keys Are Deployed**:
   ```bash
   # Verify you can SSH with keys to all nodes
   ssh -i ~/.ssh/pi_cluster admin@192.168.1.240
   exit

   # Test all nodes
   ansible all -m ping -i ansible/inventory/hosts.yml
   ```

2. **Deploy SSH Hardening**:
   ```bash
   cd /root/gitlab/local-rpi-cluster

   # DRY RUN
   ansible-playbook ansible/playbooks/security/ssh-harden.yml --check

   # Deploy
   ansible-playbook ansible/playbooks/security/ssh-harden.yml
   ```

3. **Review SSH Keys** (manual step):
   ```bash
   ssh -i ~/.ssh/pi_cluster admin@192.168.1.240
   cat ~/.ssh/authorized_keys

   # Identify each key (check comments)
   # Remove unknown keys:
   nano ~/.ssh/authorized_keys
   # Delete lines for unknown keys
   ```

4. **Test SSH Access**:
   ```bash
   # Should work (key auth)
   ssh -i ~/.ssh/pi_cluster admin@192.168.1.240

   # Should fail (password auth disabled)
   ssh -o PreferredAuthentications=password admin@192.168.1.240
   ```

5. **Monitor Fail2ban**:
   ```bash
   ansible all -m shell -a "sudo fail2ban-client status sshd" \
     -i ansible/inventory/hosts.yml
   ```

---

## 🟠 HIGH Priority - Weeks 2-4

### Week 2: Implement Pod Security Standards

**Issue**: No pod security enforcement

**Steps**:

```bash
cd /root/gitlab/local-rpi-cluster

# Deploy Pod Security Admission
ansible-playbook ansible/playbooks/security/k3s-pod-security.yml

# Verify configuration
kubectl get namespaces --show-labels | grep pod-security

# Test enforcement
kubectl run test-privileged --image=busybox \
  --restart=Never --rm -it --privileged=true -- echo "test"
# Should be denied in 'default' namespace
```

---

### Week 3: Deploy Network Policies

**Issue**: No network isolation between pods

**Steps**:

```bash
cd /root/gitlab/local-rpi-cluster

# Apply network policies
kubectl apply -f ansible/playbooks/security/network-policies.yml

# Verify policies
kubectl get networkpolicies -A

# Test isolation (should fail)
kubectl run test-curl --image=curlimages/curl --rm -it -- \
  curl http://grafana.monitoring:3000
```

---

### Week 4: Audit & Cleanup

1. **Audit All SSH Keys** (manual)
2. **Review RBAC** - Remove cluster-admin from longhorn-support-bundle
3. **Document Changes** - Update security documentation

---

## 🟡 MEDIUM Priority - Month 2

### Restrict NFS Access

**Steps**:

```bash
# SSH to DS118
ssh admin@192.168.1.10

# Edit NFS exports
sudo nano /etc/exports

# Restrict to cluster IPs only:
/volume1/nfs 192.168.1.240(rw,sync,no_subtree_check) 192.168.1.241(rw,sync,no_subtree_check) ...

# Reload exports
sudo exportfs -ra
```

---

### Enable etcd Encryption at Rest

**Steps**:

```bash
# On K3s master
ssh -i ~/.ssh/pi_cluster admin@192.168.1.240

# Create encryption config
sudo mkdir -p /var/lib/rancher/k3s/server
sudo cat > /tmp/encryption-config.yaml <<EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
    - secrets
    providers:
    - aescbc:
        keys:
        - name: key1
          secret: $(head -c 32 /dev/urandom | base64)
    - identity: {}
EOF

sudo mv /tmp/encryption-config.yaml /var/lib/rancher/k3s/server/encryption-config.yaml

# Update K3s config
sudo nano /etc/rancher/k3s/config.yaml
# Add:
kube-apiserver-arg:
- "encryption-provider-config=/var/lib/rancher/k3s/server/encryption-config.yaml"

# Restart K3s
sudo systemctl restart k3s

# Rotate all secrets
kubectl get secrets --all-namespaces -o json | \
  kubectl replace -f -
```

---

### Identify Unknown Devices

**Steps**:

```bash
# Check DHCP leases on router
# Check MAC addresses
nmap -sP 192.168.1.0/24 | grep -E "192.168.1.(27|65|72|74|75|78|84|130|145)"

# For each device:
# 1. Identify what it is
# 2. Document in inventory
# 3. Move to appropriate VLAN if IoT/guest device
```

---

## Monitoring & Validation

### Security Monitoring Checklist

**Daily**:
- [ ] Check fail2ban logs: `sudo fail2ban-client status sshd`
- [ ] Check audit logs: `sudo tail -f /var/log/k3s-audit.log`

**Weekly**:
- [ ] Review UFW logs: `sudo grep UFW /var/log/syslog`
- [ ] Check for security updates: `apt list --upgradable`
- [ ] Review pod security violations

**Monthly**:
- [ ] Rotate passwords
- [ ] Audit SSH authorized_keys
- [ ] Review network policies
- [ ] Update security report

---

## Validation Tests

### After All Critical Fixes:

```bash
# Run these tests to verify security

# 1. Firewall test
nmap -sV -p- 192.168.1.240 --open
# Should only show: 22 (ssh), 80 (http), 443 (https), NodePort range

# 2. SSH test
ssh -o PreferredAuthentications=password admin@192.168.1.240
# Should fail (password auth disabled)

# 3. Certificate test
curl -vI https://grafana.stratdata.org 2>&1 | grep -i "issuer.*Let's Encrypt"
# Should show Let's Encrypt

# 4. Pod security test
kubectl run test --image=nginx --privileged
# Should be denied

# 5. Network policy test
kubectl run test-curl --image=curlimages/curl --rm -it -- \
  curl -m 5 http://prometheus.monitoring:9090
# Should timeout (network policy blocking)
```

---

## Emergency Rollback Procedures

### If Locked Out of SSH:

1. **Access via console** (physical keyboard/monitor or BMC)
2. Disable UFW: `sudo ufw disable`
3. Re-enable password auth temporarily:
   ```bash
   sudo nano /etc/ssh/sshd_config
   # Set: PasswordAuthentication yes
   sudo systemctl restart ssh
   ```

### If K3s Fails to Start:

1. Remove Pod Security config:
   ```bash
   sudo mv /etc/rancher/k3s/config.yaml /etc/rancher/k3s/config.yaml.backup
   sudo systemctl restart k3s
   ```

### If Network Policies Break Apps:

```bash
# Remove all network policies
kubectl delete networkpolicies --all -A

# Or remove from specific namespace
kubectl delete networkpolicies --all -n monitoring
```

---

## Completion Checklist

### Week 1 (Critical):
- [ ] Credentials rotated and in Ansible Vault
- [ ] VNC disabled
- [ ] Kubelet read-only port disabled
- [ ] Firewall rules deployed
- [ ] Real Let's Encrypt certificate obtained
- [ ] SSH hardened, password auth disabled
- [ ] Fail2ban installed and configured

### Month 1 (High):
- [ ] Pod Security Standards implemented
- [ ] Network policies deployed
- [ ] SSH keys audited and cleaned
- [ ] RBAC reviewed and tightened

### Month 2 (Medium):
- [ ] NFS access restricted
- [ ] etcd encryption enabled
- [ ] Unknown devices identified
- [ ] Monitoring dashboards created

---

## Next Steps

After completing all remediation:

1. **Schedule follow-up audit** (90 days)
2. **Implement automated security scanning** (Trivy, kube-bench)
3. **Create incident response plan**
4. **Document security runbooks**
5. **Setup security monitoring alerts**

---

**Document Version**: 1.0
**Last Updated**: October 6, 2025
**Next Review**: January 6, 2026
