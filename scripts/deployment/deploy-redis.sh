#!/bin/bash
# Redis Quick Deployment Script
# Run this on pi-master (192.168.1.240)

set -e

NAMESPACE="redis"
STORAGE_SIZE="5Gi"

echo "========================================="
echo " Redis K3s Deployment"
echo "========================================="

# Create namespace
echo "[1/3] Creating namespace..."
kubectl create namespace $NAMESPACE 2>&1 | grep -v "already exists" || true

# Deploy Redis
echo "[2/3] Deploying Redis..."
cat <<EOF | kubectl apply -f -
---
# Redis PersistentVolumeClaim
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: redis-pvc
  namespace: $NAMESPACE
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: $STORAGE_SIZE
---
# Redis ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-config
  namespace: $NAMESPACE
data:
  redis.conf: |
    # Redis Configuration for Kubernetes
    bind 0.0.0.0
    protected-mode no
    port 6379

    # Persistence
    appendonly yes
    appendfsync everysec
    save 900 1
    save 300 10
    save 60 10000

    # Memory Management
    maxmemory 256mb
    maxmemory-policy allkeys-lru

    # Logging
    loglevel notice

    # Performance
    tcp-backlog 511
    timeout 0
    tcp-keepalive 300
---
# Redis Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: $NAMESPACE
  labels:
    app: redis
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
          name: redis
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        volumeMounts:
        - name: redis-data
          mountPath: /data
        - name: redis-config
          mountPath: /usr/local/etc/redis
        command:
        - redis-server
        - /usr/local/etc/redis/redis.conf
        livenessProbe:
          tcpSocket:
            port: 6379
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - redis-cli
            - ping
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: redis-data
        persistentVolumeClaim:
          claimName: redis-pvc
      - name: redis-config
        configMap:
          name: redis-config
---
# Redis Service
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: $NAMESPACE
  labels:
    app: redis
spec:
  type: ClusterIP
  ports:
  - port: 6379
    targetPort: 6379
    protocol: TCP
    name: redis
  selector:
    app: redis
EOF

# Wait for Redis
echo "[3/3] Waiting for Redis to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/redis -n $NAMESPACE || true

echo ""
echo "========================================="
echo " Deployment Status"
echo "========================================="
kubectl get pods -n $NAMESPACE
echo ""
kubectl get svc -n $NAMESPACE
echo ""

# Test Redis
echo "Testing Redis connection..."
kubectl run redis-test --rm -i --restart=Never --image=redis:7-alpine -n $NAMESPACE -- \
  redis-cli -h redis.$NAMESPACE.svc.cluster.local ping || true

echo ""
echo "========================================="
echo " Redis Deployed Successfully!"
echo "========================================="
echo " Connection string:"
echo "   redis://redis.$NAMESPACE.svc.cluster.local:6379/0"
echo ""
echo " To test:"
echo "   kubectl run redis-test --rm -i --restart=Never --image=redis:7-alpine -n $NAMESPACE -- \\"
echo "     redis-cli -h redis.$NAMESPACE.svc.cluster.local ping"
echo "========================================="
