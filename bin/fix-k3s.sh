#!/bin/bash
# fix-k3s.sh - Fix k3s cluster after clock skew issues
# Run with: sudo ./bin/fix-k3s.sh

set -e

echo "=== K3s Cluster Recovery Script ==="
echo "This script will:"
echo "  1. Stop k3s service"
echo "  2. Kill orphan containerd-shim processes"
echo "  3. Enable NTP synchronization"
echo "  4. Delete k3s TLS certs (will regenerate on start)"
echo "  5. Restart k3s service"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run with sudo"
   exit 1
fi

echo "=== Step 1/5: Stopping k3s service ==="
systemctl stop k3s || true
sleep 5

echo "=== Step 2/5: Killing orphan containerd-shim processes ==="
pkill -9 containerd-shim 2>/dev/null || true
sleep 2
# Verify they're gone
remaining=$(pgrep -c containerd-shim 2>/dev/null || echo "0")
echo "Remaining containerd-shim processes: $remaining"

echo "=== Step 3/5: Enabling NTP synchronization ==="
timedatectl set-ntp true
systemctl enable --now systemd-timesyncd || true
sleep 2
echo "Current time: $(date)"
timedatectl status | grep -E "NTP|synchronized"

echo "=== Step 4/5: Deleting k3s TLS certs for regeneration ==="
if [[ -d /var/lib/rancher/k3s/server/tls ]]; then
    rm -rf /var/lib/rancher/k3s/server/tls
    echo "TLS directory removed - will regenerate on start"
else
    echo "TLS directory not found (already removed or different install)"
fi

echo "=== Step 5/5: Starting k3s service ==="
systemctl start k3s

echo ""
echo "=== Waiting for k3s to initialize (60 seconds) ==="
for i in {1..12}; do
    echo -n "."
    sleep 5
done
echo ""

echo "=== Checking k3s service status ==="
systemctl status k3s --no-pager | head -20

echo ""
echo "=== Verifying cluster ==="
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
if kubectl get nodes 2>/dev/null; then
    echo ""
    echo "=== SUCCESS: Cluster is responding ==="
    echo ""
    echo "Next steps:"
    echo "  1. Run: kubectl get pods -A | grep -v Running | grep -v Completed"
    echo "  2. Delete stale pods with: kubectl delete pod <name> -n <namespace> --force"
    echo "  3. Or delete all Error/Unknown pods with:"
    echo "     kubectl get pods -A | grep -E 'Error|Unknown' | awk '{print \$2 \" -n \" \$1}' | xargs -I {} kubectl delete pod {} --force"
else
    echo ""
    echo "=== WARNING: Cluster not yet responding ==="
    echo "Wait a few more minutes and try: kubectl get nodes"
    echo "Check logs with: journalctl -u k3s -f"
fi
