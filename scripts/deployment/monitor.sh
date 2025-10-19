#!/bin/bash

echo "==================================="
echo "Cluster Deployment Monitor"
echo "==================================="
echo ""

# Check if script is still running
if ssh -i ~/.ssh/pi_cluster admin@192.168.1.240 "pgrep -f cluster-init.sh" > /dev/null 2>&1; then
    echo "✓ Deployment script is RUNNING"
else
    echo "✗ Deployment script has FINISHED or STOPPED"
fi

echo ""
echo "--- Latest Log Output ---"
ssh -i ~/.ssh/pi_cluster admin@192.168.1.240 "tail -20 /tmp/cluster-init.log"

echo ""
echo "--- Namespace Status ---"
ssh -i ~/.ssh/pi_cluster admin@192.168.1.240 "kubectl get namespaces | grep -E 'NAME|longhorn|traefik|cert-manager|monitoring|logging|gitlab|databases|dev-tools|kubernetes-dashboard'"

echo ""
echo "--- Pod Status (all namespaces) ---"
ssh -i ~/.ssh/pi_cluster admin@192.168.1.240 "kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded | head -20"

echo ""
echo "--- Cluster Resources ---"
ssh -i ~/.ssh/pi_cluster admin@192.168.1.240 "kubectl top nodes"

echo ""
echo "==================================="
echo "Run this script again to refresh"
echo "==================================="
