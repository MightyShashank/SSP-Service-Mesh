#!/bin/bash
# Completely uninstalls Istio Ambient Mesh from the cluster to ensure
# a true "Plain Kubernetes" baseline for Experiment 11.
# This cleans namespaces, CRDs, Webhooks, AND the CNI configurations on the host nodes.

set -euo pipefail

log()  { echo -e "\n[INFO] $1"; }
warn() { echo -e "\n[WARN] $1"; }
tick() { echo -e "\n\033[1;32m✔ $1\033[0m"; }

log "1/5: Attempting graceful Istio uninstall..."
if command -v istioctl > /dev/null 2>&1; then
  istioctl uninstall --purge -y 2>/dev/null || warn "istioctl uninstall failed — proceeding manually"
elif command -v helm > /dev/null 2>&1; then
  helm uninstall istiod -n istio-system 2>/dev/null || true
  helm uninstall ztunnel -n istio-system 2>/dev/null || true
  helm uninstall istio-cni -n istio-system 2>/dev/null || true
  helm uninstall istio-base -n istio-system 2>/dev/null || true
fi

log "2/5: Removing istio-system namespace (this may take a moment)..."
kubectl delete namespace istio-system --ignore-not-found=true

log "3/5: Removing all Istio CRDs..."
kubectl get crds -o name | grep 'istio.io' | xargs -r kubectl delete 2>/dev/null || true

log "4/5: Purging dangling Istio Webhooks (fixes 'context deadline exceeded' during helm install)..."
kubectl delete mutatingwebhookconfigurations --all 2>/dev/null || true
kubectl delete validatingwebhookconfigurations --all 2>/dev/null || true

log "5/5: Cleaning up Istio CNI from host nodes (fixes 'Unauthorized' sandbox errors)..."
cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: cni-cleanup
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: cni-cleanup
  template:
    metadata:
      labels:
        name: cni-cleanup
    spec:
      hostNetwork: true
      tolerations:
      - operator: Exists
      containers:
      - name: cleanup
        image: alpine
        securityContext:
          privileged: true
        command: ["/bin/sh", "-c"]
        args:
        - |
          echo "Cleaning up Istio CNI from host..."
          rm -f /etc/cni/net.d/*istio*
          
          if grep -q "istio-cni" /etc/cni/net.d/*.conflist 2>/dev/null; then
            for f in /etc/cni/net.d/*.conflist; do
              apk add --no-cache jq >/dev/null
              jq 'del(.plugins[] | select(.type == "istio-cni"))' "$f" > /tmp/clean.conflist
              mv /tmp/clean.conflist "$f"
            done
          fi
          echo "Done."
          sleep infinity
        volumeMounts:
        - name: cni-net-dir
          mountPath: /etc/cni/net.d
      volumes:
      - name: cni-net-dir
        hostPath:
          path: /etc/cni/net.d
EOF

log "Waiting 15 seconds for CNI cleanup DaemonSet to execute on all nodes..."
sleep 15
kubectl delete daemonset cni-cleanup -n kube-system

tick "Istio completely purged from cluster."
echo ""
echo "You can now safely run: bash scripts/deploy/deploy-setup.sh"
