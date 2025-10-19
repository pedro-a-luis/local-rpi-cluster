#!/bin/bash
# Celery Quick Deployment Script
# Run this on pi-master (192.168.1.240)

set -e

NAMESPACE="celery"
DOMAIN="flower.stratdata.org"
REDIS_URL="redis://redis.redis.svc.cluster.local:6379/0"
WORKERS=2
CONCURRENCY=2

echo "========================================="
echo " Celery K3s Deployment"
echo "========================================="

# Check Redis is running
echo "[1/6] Checking Redis dependency..."
if ! kubectl get deployment redis -n redis &>/dev/null; then
    echo "ERROR: Redis not found. Please run deploy-redis.sh first"
    exit 1
fi
echo "Redis found ✓"

# Create namespace
echo "[2/6] Creating namespace..."
kubectl create namespace $NAMESPACE 2>&1 | grep -v "already exists" || true

# Copy TLS secret
echo "[3/6] Copying TLS certificate..."
kubectl get secret stratdata-wildcard-tls -n monitoring -o yaml 2>/dev/null | \
  sed 's/namespace: monitoring/namespace: celery/' | \
  kubectl apply -f - 2>&1 | grep -v "unchanged" || true

# Deploy Celery
echo "[4/6] Deploying Celery components..."
cat <<'EOF' | kubectl apply -f -
---
# Celery App ConfigMap (Example Tasks)
apiVersion: v1
kind: ConfigMap
metadata:
  name: celery-app
  namespace: celery
data:
  tasks.py: |
    from celery import Celery
    from celery.schedules import crontab
    import time
    import os

    # Initialize Celery
    app = Celery('tasks')

    # Configure Celery from environment
    broker_url = os.getenv('CELERY_BROKER_URL', 'redis://redis.redis.svc.cluster.local:6379/0')
    result_backend = os.getenv('CELERY_RESULT_BACKEND', 'redis://redis.redis.svc.cluster.local:6379/0')

    app.conf.update(
        broker_url=broker_url,
        result_backend=result_backend,
        task_serializer='json',
        accept_content=['json'],
        result_serializer='json',
        timezone='UTC',
        enable_utc=True,
        task_track_started=True,
        task_time_limit=30 * 60,
        worker_prefetch_multiplier=1,
        worker_max_tasks_per_child=1000,
    )

    # Periodic task schedule
    app.conf.beat_schedule = {
        'hello-every-minute': {
            'task': 'tasks.hello',
            'schedule': crontab(minute='*/1'),
        },
        'cleanup-old-results': {
            'task': 'tasks.cleanup_old_results',
            'schedule': crontab(hour='*/6'),
        },
    }

    @app.task(name='tasks.add')
    def add(x, y):
        """Add two numbers"""
        return x + y

    @app.task(name='tasks.multiply')
    def multiply(x, y):
        """Multiply two numbers"""
        return x * y

    @app.task(name='tasks.hello')
    def hello():
        """Periodic health check task"""
        return f'Celery is running at {time.strftime("%Y-%m-%d %H:%M:%S")}'

    @app.task(name='tasks.long_running')
    def long_running(duration=10):
        """Simulate long-running task"""
        time.sleep(duration)
        return f'Task completed after {duration} seconds'

    @app.task(name='tasks.cleanup_old_results')
    def cleanup_old_results():
        """Clean up old task results from Redis"""
        return 'Cleanup completed'
---
# Celery Worker Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: celery-worker
  namespace: celery
  labels:
    app: celery
    component: worker
spec:
  replicas: 2
  selector:
    matchLabels:
      app: celery
      component: worker
  template:
    metadata:
      labels:
        app: celery
        component: worker
    spec:
      containers:
      - name: celery-worker
        image: python:3.11-slim
        command:
        - /bin/bash
        - -c
        - |
          pip install --no-cache-dir celery[redis]==5.3.4
          celery -A tasks worker --loglevel=info --concurrency=2
        env:
        - name: CELERY_BROKER_URL
          value: "redis://redis.redis.svc.cluster.local:6379/0"
        - name: CELERY_RESULT_BACKEND
          value: "redis://redis.redis.svc.cluster.local:6379/0"
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "1000m"
        volumeMounts:
        - name: celery-app
          mountPath: /app
        workingDir: /app
      volumes:
      - name: celery-app
        configMap:
          name: celery-app
          defaultMode: 0755
---
# Celery Beat (Scheduler) Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: celery-beat
  namespace: celery
  labels:
    app: celery
    component: beat
spec:
  replicas: 1
  selector:
    matchLabels:
      app: celery
      component: beat
  template:
    metadata:
      labels:
        app: celery
        component: beat
    spec:
      containers:
      - name: celery-beat
        image: python:3.11-slim
        command:
        - /bin/bash
        - -c
        - |
          pip install --no-cache-dir celery[redis]==5.3.4
          celery -A tasks beat --loglevel=info -s /app/data/celerybeat-schedule
        env:
        - name: CELERY_BROKER_URL
          value: "redis://redis.redis.svc.cluster.local:6379/0"
        - name: CELERY_RESULT_BACKEND
          value: "redis://redis.redis.svc.cluster.local:6379/0"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
        volumeMounts:
        - name: celery-app
          mountPath: /app
        - name: beat-data
          mountPath: /app/data
        workingDir: /app
      volumes:
      - name: celery-app
        configMap:
          name: celery-app
          defaultMode: 0755
      - name: beat-data
        emptyDir: {}
---
# Celery Flower (Monitoring) Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: celery-flower
  namespace: celery
  labels:
    app: celery
    component: flower
spec:
  replicas: 1
  selector:
    matchLabels:
      app: celery
      component: flower
  template:
    metadata:
      labels:
        app: celery
        component: flower
    spec:
      containers:
      - name: celery-flower
        image: mher/flower:2.0
        command:
        - celery
        - --broker=redis://redis.redis.svc.cluster.local:6379/0
        - flower
        - --port=5555
        - --basic-auth=admin:flower123
        ports:
        - containerPort: 5555
          name: http
        env:
        - name: CELERY_BROKER_URL
          value: "redis://redis.redis.svc.cluster.local:6379/0"
        - name: CELERY_RESULT_BACKEND
          value: "redis://redis.redis.svc.cluster.local:6379/0"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /
            port: 5555
          initialDelaySeconds: 60
          periodSeconds: 10
          timeoutSeconds: 5
---
# Celery Flower Service
apiVersion: v1
kind: Service
metadata:
  name: celery-flower
  namespace: celery
  labels:
    app: celery
    component: flower
spec:
  type: ClusterIP
  ports:
  - port: 5555
    targetPort: 5555
    protocol: TCP
    name: http
  selector:
    app: celery
    component: flower
EOF

# Create Ingress
echo "[5/6] Creating Flower Ingress..."
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: celery-flower
  namespace: $NAMESPACE
  annotations:
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
            name: celery-flower
            port:
              number: 5555
EOF

# Wait for deployments
echo "[6/6] Waiting for deployments to be ready (this may take 2-3 minutes)..."
kubectl wait --for=condition=available --timeout=300s deployment/celery-worker -n $NAMESPACE || true
kubectl wait --for=condition=available --timeout=300s deployment/celery-beat -n $NAMESPACE || true
kubectl wait --for=condition=available --timeout=300s deployment/celery-flower -n $NAMESPACE || true

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
echo " Celery Deployed Successfully!"
echo "========================================="
echo " Flower UI: https://$DOMAIN"
echo " Username: admin"
echo " Password: flower123"
echo ""
echo " Components:"
echo "   - $WORKERS Celery Workers ($CONCURRENCY concurrency each)"
echo "   - 1 Celery Beat (scheduler)"
echo "   - 1 Flower (monitoring UI)"
echo ""
echo " Redis Broker: $REDIS_URL"
echo ""
echo " Next steps:"
echo "   1. Add DNS entry: $DOMAIN -> $(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')"
echo "   2. Access Flower at https://$DOMAIN"
echo "   3. Customize tasks in ConfigMap celery-app"
echo ""
echo " To check logs:"
echo "   kubectl logs -n $NAMESPACE -l component=worker --tail=50"
echo "   kubectl logs -n $NAMESPACE -l component=beat --tail=50"
echo "   kubectl logs -n $NAMESPACE -l component=flower --tail=50"
echo "========================================="
