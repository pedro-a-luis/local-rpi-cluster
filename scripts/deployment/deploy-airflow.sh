#!/bin/bash
# Apache Airflow Quick Deployment Script
# Run this on pi-master (192.168.1.240)

set -e

NAMESPACE="airflow"
DOMAIN="airflow.stratdata.org"

echo "========================================="
echo " Apache Airflow K3s Deployment"
echo "========================================="

# Add Helm repo
echo "[1/5] Adding Apache Airflow Helm repository..."
helm repo add apache-airflow https://airflow.apache.org 2>&1 | grep -v "already exists" || true
helm repo update

# Create namespace
echo "[2/5] Creating namespace..."
kubectl create namespace $NAMESPACE 2>&1 | grep -v "already exists" || true

# Copy TLS secret
echo "[3/5] Copying TLS certificate..."
kubectl get secret stratdata-wildcard-tls -n monitoring -o yaml 2>/dev/null | \
  sed 's/namespace: monitoring/namespace: airflow/' | \
  kubectl apply -f - 2>&1 | grep -v "unchanged" || true

# Install Airflow
echo "[4/5] Installing Apache Airflow (this will take 10-15 minutes)..."
helm upgrade --install airflow apache-airflow/airflow \
  --namespace $NAMESPACE \
  --set executor=KubernetesExecutor \
  --set postgresql.enabled=true \
  --set postgresql.auth.password=airflow123 \
  --set webserver.service.type=ClusterIP \
  --set dags.persistence.enabled=true \
  --set dags.persistence.size=5Gi \
  --set dags.persistence.storageClassName=longhorn \
  --set logs.persistence.enabled=true \
  --set logs.persistence.size=10Gi \
  --set logs.persistence.storageClassName=longhorn \
  --set webserver.defaultUser.enabled=true \
  --set webserver.defaultUser.username=admin \
  --set webserver.defaultUser.password=admin123 \
  --timeout 15m \
  --wait

# Create Ingress
echo "[5/5] Creating Ingress..."
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: airflow-webserver
  namespace: $NAMESPACE
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - $DOMAIN
    secretName: stratdata-wildcard-tls
  rules:
  - host: $DOMAIN
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: airflow-webserver
            port:
              number: 8080
EOF

echo ""
echo "========================================="
echo " Deployment Status"
echo "========================================="
kubectl get pods -n $NAMESPACE
echo ""
kubectl get svc -n $NAMESPACE
echo ""
kubectl get ingress -n $NAMESPACE
echo ""
echo "========================================="
echo " Airflow Deployed Successfully!"
echo "========================================="
echo " Web UI: https://$DOMAIN"
echo " Username: admin"
echo " Password: admin123"
echo ""
echo " Next: Update DNS to point $DOMAIN to this node"
echo "========================================="
