#!/bin/bash

###############################################################################
# Raspberry Pi K3s Cluster Initialization Script
# Full stack deployment with WireGuard external access
# Domain: stratdata.org
###############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_DOMAIN="stratdata.org"
WIREGUARD_ENDPOINT="10.116.24.1"
ADMIN_EMAIL="admin@stratdata.org"
STORAGE_SIZE="50Gi"

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

wait_for_pods() {
    local namespace=$1
    local label=$2
    local timeout=${3:-300}

    log_info "Waiting for pods with label $label in namespace $namespace..."
    kubectl wait --for=condition=ready pod -l "$label" -n "$namespace" --timeout=${timeout}s || true
}

check_helm() {
    if ! command -v helm &> /dev/null; then
        log_error "Helm not found. Installing..."
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi
}

###############################################################################
# 1. Setup Helm Repositories
###############################################################################
setup_helm_repos() {
    log_info "Setting up Helm repositories..."

    helm repo add traefik https://traefik.github.io/charts
    helm repo add jetstack https://charts.jetstack.io
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo add gitlab https://charts.gitlab.io
    helm repo add longhorn https://charts.longhorn.io
    helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
    helm repo add bitnami https://charts.bitnami.com/bitnami

    helm repo update

    log_info "Helm repositories configured"
}

###############################################################################
# 2. Deploy Longhorn Storage Provisioner
###############################################################################
deploy_longhorn() {
    log_info "Deploying Longhorn distributed storage..."

    kubectl create namespace longhorn-system --dry-run=client -o yaml | kubectl apply -f -

    helm upgrade --install longhorn longhorn/longhorn \
        --namespace longhorn-system \
        --set defaultSettings.defaultDataPath="/var/lib/longhorn" \
        --set defaultSettings.replicaCount=2 \
        --set persistence.defaultClass=true \
        --set persistence.defaultClassReplicaCount=2 \
        --set ingress.enabled=true \
        --set ingress.ingressClassName=traefik \
        --set ingress.host=longhorn.${CLUSTER_DOMAIN} \
        --wait --timeout=10m

    log_info "Longhorn deployed at http://longhorn.${CLUSTER_DOMAIN}"
}

###############################################################################
# 3. Deploy Traefik Ingress Controller
###############################################################################
deploy_traefik() {
    log_info "Deploying Traefik ingress controller..."

    kubectl create namespace traefik --dry-run=client -o yaml | kubectl apply -f -

    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: traefik-config
  namespace: traefik
data:
  traefik.yaml: |
    entryPoints:
      web:
        address: ":80"
        http:
          redirections:
            entryPoint:
              to: websecure
              scheme: https
      websecure:
        address: ":443"
    providers:
      kubernetesIngress: {}
      kubernetesCRD: {}
    api:
      dashboard: true
    log:
      level: INFO
EOF

    helm upgrade --install traefik traefik/traefik \
        --namespace traefik \
        --set ports.web.exposedPort=80 \
        --set ports.websecure.exposedPort=443 \
        --set service.type=LoadBalancer \
        --set ingressRoute.dashboard.enabled=true \
        --set additionalArguments[0]="--api.dashboard=true" \
        --wait --timeout=5m

    # Create Traefik dashboard ingress
    cat <<EOF | kubectl apply -f -
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: dashboard
  namespace: traefik
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(\`traefik.${CLUSTER_DOMAIN}\`)
      kind: Rule
      services:
        - name: api@internal
          kind: TraefikService
EOF

    log_info "Traefik deployed at https://traefik.${CLUSTER_DOMAIN}"
}

###############################################################################
# 4. Deploy Cert-Manager for SSL
###############################################################################
deploy_cert_manager() {
    log_info "Deploying cert-manager..."

    kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -

    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --set crds.enabled=true \
        --set crds.keep=true \
        --wait --timeout=5m

    sleep 10

    # Create self-signed CA for internal services
    cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: stratdata-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: stratdata.org
  secretName: stratdata-ca-secret
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
    group: cert-manager.io
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: stratdata-ca-issuer
spec:
  ca:
    secretName: stratdata-ca-secret
EOF

    log_info "Cert-manager deployed with internal CA"
}

###############################################################################
# 5. Deploy Monitoring Stack (Prometheus + Grafana)
###############################################################################
deploy_monitoring() {
    log_info "Deploying monitoring stack (Prometheus + Grafana)..."

    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

    cat <<EOF > /tmp/prometheus-values.yaml
prometheus:
  prometheusSpec:
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 20Gi
    resources:
      requests:
        cpu: 200m
        memory: 512Mi
      limits:
        cpu: 1000m
        memory: 2Gi

grafana:
  adminPassword: "Grafana123"
  persistence:
    enabled: true
    size: 5Gi
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi
  ingress:
    enabled: true
    ingressClassName: traefik
    hosts:
      - grafana.${CLUSTER_DOMAIN}
    annotations:
      cert-manager.io/cluster-issuer: stratdata-ca-issuer

alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 5Gi

prometheus-node-exporter:
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 128Mi
EOF

    helm upgrade --install kube-prometheus prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --values /tmp/prometheus-values.yaml \
        --wait --timeout=10m

    log_info "Monitoring stack deployed at https://grafana.${CLUSTER_DOMAIN} (admin/Grafana123)"
}

###############################################################################
# 6. Deploy Logging Stack (Loki + Promtail)
###############################################################################
deploy_logging() {
    log_info "Deploying logging stack (Loki + Promtail)..."

    kubectl create namespace logging --dry-run=client -o yaml | kubectl apply -f -

    cat <<EOF > /tmp/loki-values.yaml
loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 1
  storage:
    type: filesystem

singleBinary:
  replicas: 1
  persistence:
    enabled: true
    size: 30Gi
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 1Gi

monitoring:
  selfMonitoring:
    enabled: false
  serviceMonitor:
    enabled: true

gateway:
  enabled: true
  ingress:
    enabled: true
    ingressClassName: traefik
    hosts:
      - host: loki.${CLUSTER_DOMAIN}
        paths:
          - path: /
            pathType: Prefix
    annotations:
      cert-manager.io/cluster-issuer: stratdata-ca-issuer
EOF

    helm upgrade --install loki grafana/loki \
        --namespace logging \
        --values /tmp/loki-values.yaml \
        --wait --timeout=10m

    # Deploy Promtail
    cat <<EOF > /tmp/promtail-values.yaml
config:
  clients:
    - url: http://loki-gateway.logging.svc.cluster.local/loki/api/v1/push

resources:
  requests:
    cpu: 50m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi
EOF

    helm upgrade --install promtail grafana/promtail \
        --namespace logging \
        --values /tmp/promtail-values.yaml \
        --wait --timeout=5m

    log_info "Logging stack deployed at https://loki.${CLUSTER_DOMAIN}"
}

###############################################################################
# 7. Deploy Kubernetes Dashboard
###############################################################################
deploy_dashboard() {
    log_info "Deploying Kubernetes Dashboard..."

    kubectl create namespace kubernetes-dashboard --dry-run=client -o yaml | kubectl apply -f -

    helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
        --namespace kubernetes-dashboard \
        --set kong.enabled=false \
        --set app.ingress.enabled=true \
        --set app.ingress.ingressClassName=traefik \
        --set "app.ingress.hosts[0]=dashboard.${CLUSTER_DOMAIN}" \
        --set app.ingress.issuer.name=stratdata-ca-issuer \
        --set app.ingress.issuer.scope=cluster \
        --wait --timeout=5m

    # Create admin user
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: v1
kind: Secret
metadata:
  name: admin-user-token
  namespace: kubernetes-dashboard
  annotations:
    kubernetes.io/service-account.name: admin-user
type: kubernetes.io/service-account-token
EOF

    log_info "Kubernetes Dashboard deployed at https://dashboard.${CLUSTER_DOMAIN}"
}

###############################################################################
# 8. Deploy GitLab (Git Repos + Container Registry + CI/CD)
###############################################################################
deploy_gitlab() {
    log_info "Deploying GitLab with Git repos, Container Registry, and CI/CD..."

    kubectl create namespace gitlab --dry-run=client -o yaml | kubectl apply -f -

    cat <<EOF > /tmp/gitlab-values.yaml
global:
  hosts:
    domain: ${CLUSTER_DOMAIN}
    https: true
    gitlab:
      name: gitlab.${CLUSTER_DOMAIN}
    registry:
      name: registry.${CLUSTER_DOMAIN}
    minio:
      name: minio.${CLUSTER_DOMAIN}

  ingress:
    configureCertmanager: false
    class: traefik
    annotations:
      cert-manager.io/cluster-issuer: stratdata-ca-issuer

  edition: ce

  initialRootPassword:
    secret: gitlab-initial-root-password
    key: password

# GitLab Rails (main app)
gitlab:
  webservice:
    resources:
      requests:
        cpu: 200m
        memory: 1Gi
      limits:
        cpu: 1500m
        memory: 2Gi

  sidekiq:
    resources:
      requests:
        cpu: 100m
        memory: 512Mi
      limits:
        cpu: 1000m
        memory: 1Gi

  gitlab-shell:
    resources:
      requests:
        cpu: 50m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi

# Container Registry
registry:
  enabled: true
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi
  storage:
    secret: gitlab-registry-storage
    key: config
    extraKey: gcs.json

# PostgreSQL
postgresql:
  install: true
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi
  persistence:
    size: 20Gi

# Redis
redis:
  install: true
  master:
    resources:
      requests:
        cpu: 50m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi
  persistence:
    size: 5Gi

# MinIO (object storage)
minio:
  persistence:
    size: 50Gi
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

# GitLab Runner
gitlab-runner:
  install: true
  runners:
    config: |
      [[runners]]
        [runners.kubernetes]
          namespace = "{{.Release.Namespace}}"
          image = "ubuntu:22.04"
          cpu_request = "100m"
          memory_request = "256Mi"
          cpu_limit = "1000m"
          memory_limit = "1Gi"
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi

# Prometheus monitoring
prometheus:
  install: false

# Disable components not needed for small cluster
nginx-ingress:
  enabled: false

certmanager:
  install: false

gitlab-exporter:
  enabled: false
EOF

    # Create initial root password secret
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-initial-root-password
  namespace: gitlab
type: Opaque
stringData:
  password: "GitLab123456"
EOF

    # Create registry storage config
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-registry-storage
  namespace: gitlab
type: Opaque
stringData:
  config: |
    s3:
      bucket: registry
      v4auth: true
      regionendpoint: http://gitlab-minio-svc:9000
      pathstyle: true
      secure: false
      accesskey: AKIAIOSFODNN7EXAMPLE
      secretkey: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
  gcs.json: "{}"
EOF

    log_warn "GitLab is resource-intensive and may take 15-20 minutes to fully deploy..."

    helm upgrade --install gitlab gitlab/gitlab \
        --namespace gitlab \
        --values /tmp/gitlab-values.yaml \
        --timeout=20m || log_warn "GitLab deployment in progress, may need more time"

    log_info "GitLab deployed:"
    log_info "  - GitLab UI:         https://gitlab.${CLUSTER_DOMAIN} (root/GitLab123456)"
    log_info "  - Container Registry: https://registry.${CLUSTER_DOMAIN}"
    log_info "  - MinIO:             https://minio.${CLUSTER_DOMAIN}"
}

###############################################################################
# 9. Deploy PostgreSQL Cluster (separate from GitLab)
###############################################################################
deploy_postgresql() {
    log_info "Deploying standalone PostgreSQL cluster..."

    kubectl create namespace databases --dry-run=client -o yaml | kubectl apply -f -

    cat <<EOF > /tmp/postgresql-values.yaml
architecture: replication
auth:
  enablePostgresUser: true
  postgresPassword: "Postgres123"
  username: appuser
  password: "AppUser123"
  database: appdb

primary:
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 1Gi
  persistence:
    enabled: true
    size: 20Gi

readReplicas:
  replicaCount: 2
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi
  persistence:
    enabled: true
    size: 20Gi

metrics:
  enabled: true
  serviceMonitor:
    enabled: true
    namespace: monitoring
EOF

    helm upgrade --install postgresql bitnami/postgresql \
        --namespace databases \
        --values /tmp/postgresql-values.yaml \
        --wait --timeout=10m

    log_info "PostgreSQL cluster deployed in namespace: databases"
}

###############################################################################
# 10. Deploy Code-server (VS Code in browser)
###############################################################################
deploy_codeserver() {
    log_info "Deploying Code-server (VS Code)..."

    kubectl create namespace dev-tools --dry-run=client -o yaml | kubectl apply -f -

    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: codeserver-data
  namespace: dev-tools
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 30Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: codeserver
  namespace: dev-tools
spec:
  replicas: 1
  selector:
    matchLabels:
      app: codeserver
  template:
    metadata:
      labels:
        app: codeserver
    spec:
      containers:
      - name: codeserver
        image: codercom/code-server:latest
        ports:
        - containerPort: 8080
        env:
        - name: PASSWORD
          value: "CodeServer123"
        - name: SUDO_PASSWORD
          value: "CodeServer123"
        volumeMounts:
        - name: data
          mountPath: /home/coder
        resources:
          requests:
            cpu: 200m
            memory: 512Mi
          limits:
            cpu: 2000m
            memory: 2Gi
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: codeserver-data
---
apiVersion: v1
kind: Service
metadata:
  name: codeserver
  namespace: dev-tools
spec:
  selector:
    app: codeserver
  ports:
  - port: 8080
    targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: codeserver
  namespace: dev-tools
  annotations:
    cert-manager.io/cluster-issuer: stratdata-ca-issuer
spec:
  ingressClassName: traefik
  rules:
  - host: code.${CLUSTER_DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: codeserver
            port:
              number: 8080
  tls:
  - hosts:
    - code.${CLUSTER_DOMAIN}
    secretName: codeserver-tls
EOF

    log_info "Code-server deployed at https://code.${CLUSTER_DOMAIN} (password: CodeServer123)"
}

###############################################################################
# 11. Configure WireGuard Access
###############################################################################
configure_wireguard() {
    log_info "Configuring WireGuard for external access..."

    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: wireguard-config
  namespace: kube-system
data:
  endpoint: "${WIREGUARD_ENDPOINT}:51820"
  instructions: |
    ========================================
    WireGuard External Access Configuration
    ========================================

    WireGuard is running on pi-master (192.168.1.240)
    External clients connect to: ${WIREGUARD_ENDPOINT}:51820

    TO ADD A NEW CLIENT:
    --------------------
    1. SSH to pi-master:
       ssh admin@192.168.1.240

    2. Generate client keys:
       cd /etc/wireguard
       wg genkey | tee client-privatekey | wg pubkey > client-publickey

    3. Add to /etc/wireguard/wg0.conf:
       [Peer]
       PublicKey = <content of client-publickey>
       AllowedIPs = 10.116.24.X/32

    4. Restart WireGuard:
       systemctl restart wg-quick@wg0

    5. Create client config (client.conf):
       [Interface]
       PrivateKey = <content of client-privatekey>
       Address = 10.116.24.X/24
       DNS = 192.168.1.240

       [Peer]
       PublicKey = <server public key>
       Endpoint = <your-public-ip>:51820
       AllowedIPs = 10.116.24.0/24, 192.168.1.0/24, 10.42.0.0/16
       PersistentKeepalive = 25

    SERVICES ACCESSIBLE VIA WIREGUARD:
    -----------------------------------
    After connecting to WireGuard, access services at:
    - https://gitlab.${CLUSTER_DOMAIN}
    - https://grafana.${CLUSTER_DOMAIN}
    - https://code.${CLUSTER_DOMAIN}
    - etc.

    Add to client /etc/hosts or use DNS:
    192.168.1.240  gitlab.${CLUSTER_DOMAIN}
    192.168.1.240  grafana.${CLUSTER_DOMAIN}
    192.168.1.240  dashboard.${CLUSTER_DOMAIN}
    192.168.1.240  code.${CLUSTER_DOMAIN}
    192.168.1.240  registry.${CLUSTER_DOMAIN}
    192.168.1.240  traefik.${CLUSTER_DOMAIN}
    192.168.1.240  longhorn.${CLUSTER_DOMAIN}
    ========================================
EOF

    log_info "WireGuard configuration guide created in configmap: kube-system/wireguard-config"
    log_info "View: kubectl get cm wireguard-config -n kube-system -o yaml"
}

###############################################################################
# 12. Create Summary Dashboard
###############################################################################
create_summary() {
    log_info "Creating deployment summary..."

    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-services
  namespace: kube-system
data:
  services.txt: |
    ================================================================================
    Raspberry Pi K3s Cluster - StratData.org Services
    ================================================================================

    GIT & CI/CD
    -----------
    - GitLab (Git Repos):      https://gitlab.${CLUSTER_DOMAIN}
      Username: root
      Password: GitLab123456
    - Container Registry:      https://registry.${CLUSTER_DOMAIN}
    - GitLab Runner:           Automatic CI/CD in gitlab namespace

    MONITORING & OBSERVABILITY
    --------------------------
    - Grafana:                 https://grafana.${CLUSTER_DOMAIN}
      Username: admin
      Password: Grafana123
    - Prometheus:              Via Grafana datasource
    - Loki (Logs):             https://loki.${CLUSTER_DOMAIN}
    - AlertManager:            Via kube-prometheus stack

    DASHBOARDS & MANAGEMENT
    -----------------------
    - Kubernetes Dashboard:    https://dashboard.${CLUSTER_DOMAIN}
      Token: kubectl -n kubernetes-dashboard create token admin-user
    - Traefik Dashboard:       https://traefik.${CLUSTER_DOMAIN}
    - Longhorn Storage UI:     https://longhorn.${CLUSTER_DOMAIN}

    DEVELOPMENT TOOLS
    -----------------
    - Code-server (VS Code):   https://code.${CLUSTER_DOMAIN}
      Password: CodeServer123

    DATABASES
    ---------
    - PostgreSQL Primary:      postgresql.databases.svc.cluster.local:5432
      Admin: postgres / Postgres123
      App:   appuser / AppUser123
    - GitLab PostgreSQL:       gitlab-postgresql.gitlab.svc.cluster.local:5432

    STORAGE
    -------
    - Longhorn:                Distributed block storage (default StorageClass)
    - Total Capacity:          ~1.9TB NVMe across 8 nodes
    - Replication:             2 replicas per volume

    NETWORK ACCESS
    --------------
    - WireGuard Endpoint:      ${WIREGUARD_ENDPOINT}:51820
    - Internal Network:        192.168.1.0/24
    - Pod Network (CNI):       10.42.0.0/16
    - WireGuard Network:       10.116.24.0/24

    CLUSTER RESOURCES
    -----------------
    - Nodes:                   8x Raspberry Pi 5
    - Total RAM:               64GB (8GB per node)
    - Total CPU:               32 cores (4 cores per node)
    - Total Storage:           ~1.9TB NVMe
    - Kubernetes:              v1.32.2+k3s1

    IMPORTANT NOTES
    ---------------
    1. Add DNS entries or update /etc/hosts to point *.${CLUSTER_DOMAIN} to 192.168.1.240
    2. All services use self-signed certificates from internal CA
    3. External access requires WireGuard VPN connection
    4. GitLab includes: Git repos, Container Registry, CI/CD runners, and issue tracking
    5. Use GitLab registry: docker login registry.${CLUSTER_DOMAIN}

    QUICK COMMANDS
    --------------
    Get K8s Dashboard token:
      kubectl -n kubernetes-dashboard create token admin-user

    View WireGuard setup:
      kubectl get cm wireguard-config -n kube-system -o jsonpath='{.data.instructions}'

    Check cluster health:
      kubectl get nodes
      kubectl top nodes

    View all services:
      kubectl get svc -A

    View GitLab status:
      kubectl get pods -n gitlab

    ================================================================================
EOF

    kubectl get configmap cluster-services -n kube-system -o jsonpath='{.data.services\.txt}'
}

###############################################################################
# Main Execution
###############################################################################
main() {
    log_info "=========================================="
    log_info "Raspberry Pi K3s Cluster Initialization"
    log_info "Domain: ${CLUSTER_DOMAIN}"
    log_info "WireGuard: ${WIREGUARD_ENDPOINT}"
    log_info "=========================================="

    check_helm

    log_info "Step 1/11: Setting up Helm repositories..."
    setup_helm_repos

    log_info "Step 2/11: Deploying Longhorn storage..."
    deploy_longhorn

    log_info "Step 3/11: Deploying Traefik ingress..."
    deploy_traefik

    log_info "Step 4/11: Deploying cert-manager..."
    deploy_cert_manager

    log_info "Step 5/11: Deploying monitoring stack..."
    deploy_monitoring

    log_info "Step 6/11: Deploying logging stack..."
    deploy_logging

    log_info "Step 7/11: Deploying Kubernetes Dashboard..."
    deploy_dashboard

    log_info "Step 8/11: Deploying GitLab (Git + Registry + CI/CD)..."
    deploy_gitlab

    log_info "Step 9/11: Deploying PostgreSQL cluster..."
    deploy_postgresql

    log_info "Step 10/11: Deploying Code-server..."
    deploy_codeserver

    log_info "Step 11/11: Configuring WireGuard access..."
    configure_wireguard

    log_info "Creating summary..."
    create_summary

    echo ""
    log_info "=========================================="
    log_info "✓ Cluster initialization complete!"
    log_info "=========================================="
    echo ""
    log_info "View full summary:"
    log_info "  kubectl get cm cluster-services -n kube-system -o jsonpath='{.data.services\\.txt}'"
    echo ""
    log_info "Key services:"
    log_info "  GitLab:     https://gitlab.${CLUSTER_DOMAIN} (root/GitLab123456)"
    log_info "  Registry:   https://registry.${CLUSTER_DOMAIN}"
    log_info "  Grafana:    https://grafana.${CLUSTER_DOMAIN} (admin/Grafana123)"
    log_info "  Dashboard:  https://dashboard.${CLUSTER_DOMAIN}"
    log_info "  Code:       https://code.${CLUSTER_DOMAIN} (CodeServer123)"
    echo ""
    log_warn "NEXT STEPS:"
    log_warn "1. Add DNS: *.${CLUSTER_DOMAIN} → 192.168.1.240"
    log_warn "2. Setup WireGuard clients for external access"
    log_warn "3. Wait for GitLab to fully initialize (~15-20 min)"
    log_warn "4. Get K8s token: kubectl -n kubernetes-dashboard create token admin-user"
    echo ""
}

# Run main function
main "$@"
