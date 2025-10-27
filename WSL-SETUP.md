# WSL Ansible & kubectl Setup Guide

This guide documents the setup of Ansible and kubectl on Windows Subsystem for Linux (WSL) for managing the Raspberry Pi K3s cluster.

## Installation Summary

### Date
October 19, 2025

### Tools Installed
- **Ansible**: 2.10.8 (with sshpass for SSH authentication)
- **kubectl**: v1.34.1 (Kubernetes CLI)

## Installation Steps

### 1. Install Ansible

```bash
sudo apt update
sudo apt install -y ansible sshpass
```

**Verification:**
```bash
ansible --version
# Output: ansible 2.10.8
```

### 2. Install kubectl

```bash
# Download kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

# Install to system path
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Clean up
rm kubectl
```

**Verification:**
```bash
kubectl version --client
# Output: Client Version: v1.34.1
```

### 3. Configure kubectl for Cluster Access

```bash
# Create kubectl config directory
mkdir -p ~/.kube

# Copy kubeconfig from pi-master
scp -i ~/.ssh/pi_cluster admin@192.168.1.240:/etc/rancher/k3s/k3s.yaml ~/.kube/config

# Update server address (from localhost to pi-master IP)
sed -i 's/127.0.0.1/192.168.1.240/g' ~/.kube/config

# Set proper permissions
chmod 600 ~/.kube/config
```

**Verification:**
```bash
kubectl get nodes
# Should show all 8 nodes (1 master + 7 workers)
```

## Testing

### kubectl Access

```bash
# Get cluster nodes
kubectl get nodes

# Get all pods
kubectl get pods -A

# Get specific namespace
kubectl get pods -n celery
kubectl get pods -n redis

# Check deployments
kubectl get deployments -n celery
```

**Expected Output:**
```
NAME           STATUS   ROLES                  AGE    VERSION
pi-master      Ready    control-plane,master   149d   v1.32.2+k3s1
pi-worker-01   Ready    <none>                 149d   v1.32.2+k3s1
pi-worker-02   Ready    <none>                 149d   v1.32.2+k3s1
...
```

### Ansible Access

```bash
# Test with a playbook (dry-run)
cd ~/gitlab/local-rpi-cluster
ansible-playbook ansible/playbooks/redis-install.yml --check

# Run actual playbook
ansible-playbook ansible/playbooks/redis-install.yml
```

## Usage

### Deploy Applications from WSL

**Redis:**
```bash
cd ~/gitlab/local-rpi-cluster
ansible-playbook ansible/playbooks/redis-install.yml
```

**Celery:**
```bash
ansible-playbook ansible/playbooks/celery-install.yml
```

**Update Certificates:**
```bash
ansible-playbook ansible/playbooks/infrastructure/update-certificates.yml
```

### kubectl Operations

**Check Status:**
```bash
kubectl get pods -n redis -n celery
kubectl get svc -n redis -n celery
kubectl get ingress -n celery
```

**View Logs:**
```bash
kubectl logs -n celery deployment/celery-worker --tail=50
kubectl logs -n celery deployment/celery-beat --tail=50
kubectl logs -n celery deployment/celery-flower --tail=50
```

**Scale Resources:**
```bash
# Scale Celery workers to 4
kubectl scale deployment celery-worker -n celery --replicas=4

# Verify
kubectl get pods -n celery -l component=worker
```

**Update Deployments:**
```bash
# Edit deployment
kubectl edit deployment celery-worker -n celery

# Or patch specific value
kubectl patch deployment celery-worker -n celery --type='json' \
  -p='[{"op": "replace", "path": "/spec/replicas", "value": 4}]'
```

## Benefits

### Unified Management
- ✅ Single command center for all infrastructure
- ✅ No need to SSH to pi-master for every operation
- ✅ Integrated with VS Code and local development workflow
- ✅ Direct access to git repository

### Development Efficiency
- ✅ Faster iteration when writing/testing playbooks
- ✅ Edit and deploy in one step
- ✅ No file syncing needed
- ✅ Full access to local tools (editors, git, etc.)

### Reliability
- ✅ Independent of cluster state
- ✅ Can manage cluster even if pi-master is down
- ✅ Backup management capability

## Best Practices

### Hybrid Approach

**Use WSL for:**
- Development and testing of playbooks
- Infrastructure deployments (Redis, Celery, etc.)
- DNS/certificate updates
- Documentation and script development
- Quick kubectl operations

**Use pi-master for:**
- Emergency cluster operations (when WSL is unavailable)
- Scheduled/automated tasks (cron jobs)
- Cluster-specific operations that need local access

### Workflow Example

**Before (without WSL setup):**
```bash
# 1. Edit files locally
vim scripts/deployment/deploy-celery.sh

# 2. SSH to pi-master
ssh -i ~/.ssh/pi_cluster admin@192.168.1.240

# 3. Pull/sync latest files
git pull

# 4. Run deployment
bash scripts/deployment/deploy-celery.sh
```

**After (with WSL setup):**
```bash
# Edit and deploy in one workflow
vim ansible/playbooks/celery-install.yml
ansible-playbook ansible/playbooks/celery-install.yml
```

**Time saved per deployment:** ~2-3 minutes
**Reduced context switching:** Significant

## Configuration Files

**kubectl config:**
- Location: `~/.kube/config`
- Server: `https://192.168.1.240:6443`
- Certificate: Copied from pi-master K3s installation

**Ansible config:**
- Default location: `/etc/ansible/ansible.cfg` (or `./ansible.cfg` in repo)
- No custom configuration needed for basic usage

## Troubleshooting

### kubectl Connection Issues

```bash
# Test connectivity
ping 192.168.1.240

# Check kubeconfig
cat ~/.kube/config | grep server
# Should show: server: https://192.168.1.240:6443

# Test with verbose output
kubectl get nodes -v=6
```

### Ansible Playbook Errors

```bash
# Check Ansible can find playbooks
ls -la ansible/playbooks/

# Run with verbose output
ansible-playbook ansible/playbooks/redis-install.yml -vvv

# Test SSH connectivity
ssh -i ~/.ssh/pi_cluster admin@192.168.1.240
```

### Permission Errors

```bash
# Fix kubeconfig permissions
chmod 600 ~/.kube/config

# Fix SSH key permissions
chmod 600 ~/.ssh/pi_cluster
```

## Maintenance

### Update kubectl

```bash
# Download latest version
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

# Install
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Verify
kubectl version --client
```

### Update Ansible

```bash
sudo apt update
sudo apt upgrade ansible
```

### Refresh kubectl Config

If pi-master's certificate changes:

```bash
scp -i ~/.ssh/pi_cluster admin@192.168.1.240:/etc/rancher/k3s/k3s.yaml ~/.kube/config
sed -i 's/127.0.0.1/192.168.1.240/g' ~/.kube/config
chmod 600 ~/.kube/config
```

## Current Deployment Status

All services successfully deployed and accessible from WSL:

### Redis
```bash
$ kubectl get pods -n redis
NAME                     READY   STATUS    RESTARTS   AGE
redis-66b5b54686-4rr28   1/1     Running   0          3h20m
```

### Celery
```bash
$ kubectl get pods -n celery
NAME                             READY   STATUS    RESTARTS   AGE
celery-beat-9554dc9f8-vl84x      1/1     Running   0          3h12m
celery-flower-6645f77fd5-gh4sn   1/1     Running   1          5m19s
celery-worker-64d8d5dd99-cvzcg   1/1     Running   0          3h19m
celery-worker-64d8d5dd99-gkqrj   1/1     Running   0          3h19m
```

## Next Steps

1. **Test deployments** - Try deploying a new service from WSL
2. **Update documentation** - Add WSL usage to existing guides
3. **Create shortcuts** - Add bash aliases for common operations
4. **Integrate with CI/CD** - Use WSL for automated deployments

## Bash Aliases (Optional)

Add to `~/.bashrc` for convenience:

```bash
# Kubernetes aliases
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgd='kubectl get deployments'
alias kgn='kubectl get nodes'
alias kdp='kubectl describe pod'
alias kl='kubectl logs'
alias kx='kubectl exec -it'

# Cluster-specific
alias kcelery='kubectl get pods -n celery'
alias kredis='kubectl get pods -n redis'
alias klogs-celery='kubectl logs -n celery'

# Ansible
alias ap='ansible-playbook'
alias apc='ansible-playbook --check'

# Navigate to cluster repo
alias cluster='cd ~/gitlab/local-rpi-cluster'
```

Then reload:
```bash
source ~/.bashrc
```

## References

- [kubectl documentation](https://kubernetes.io/docs/reference/kubectl/)
- [Ansible documentation](https://docs.ansible.com/)
- [K3s documentation](https://docs.k3s.io/)
- [Cluster README](README.md)
- [Deployment Documentation](docs/README.md)

---

**Setup Date:** October 19, 2025
**WSL Version:** Ubuntu 22.04 on Windows
**Cluster:** 8-node Raspberry Pi 5 K3s cluster
**Status:** ✅ Fully operational
