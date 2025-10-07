#!/bin/bash

# Enhanced cleanup script for Zama Jobs API Kubernetes deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "========================================"
echo "Zama Jobs API - Enhanced Cleanup"
echo "========================================"

# Confirm deletion
read -p "Are you sure you want to delete all Zama Jobs API resources? (y/N): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Cleanup cancelled"
    exit 0
fi

# Define namespaces
NAMESPACES=("zama-system" "kong" "iam" "messaging" "monitoring" "storage")

# Kill port forwarding
log_info "Stopping port forwarding..."
pkill -f "kubectl port-forward" || true

# Delete all Helm releases first
log_info "Removing Helm releases..."

# Delete Kong release
kong_release=$(helm list -n kong -q 2>/dev/null | head -1 || echo "")
if [[ -n "$kong_release" ]]; then
    log_info "Deleting Kong release: $kong_release"
    helm uninstall "$kong_release" -n kong 2>/dev/null || true
else
    log_info "No Kong release found"
fi

# Delete NATS release
nats_release=$(helm list -n messaging -q 2>/dev/null | head -1 || echo "")
if [[ -n "$nats_release" ]]; then
    log_info "Deleting NATS release: $nats_release"
    helm uninstall "$nats_release" -n messaging 2>/dev/null || true
else
    log_info "No NATS release found"
fi

# Delete Cilium (optional)
read -p "Delete Cilium CNI? This will affect cluster networking (y/N): " delete_cilium
if [ "$delete_cilium" == "y" ] || [ "$delete_cilium" == "Y" ]; then
    log_warning "Uninstalling Cilium..."
    helm uninstall cilium -n kube-system 2>/dev/null || true

    # Remove Cilium taints from nodes
    log_info "Removing Cilium taints from nodes..."
    nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    if [[ -n "$nodes" ]]; then
        for node in $nodes; do
            kubectl taint node "$node" node.cilium.io/agent-not-ready:NoSchedule- 2>/dev/null && log_success "Removed Cilium taint from $node" || log_info "No Cilium taint on $node"
            kubectl taint node "$node" node.cilium.io/agent-not-ready- 2>/dev/null || true
            kubectl taint node "$node" cilium.io/no-schedule- 2>/dev/null || true
        done
    fi
fi

# Also check for and remove Cilium taints even if Cilium wasn't explicitly deleted
cilium_taints=$(kubectl get nodes -o jsonpath='{.items[*].spec.taints[?(@.key=="node.cilium.io/agent-not-ready")]}' 2>/dev/null || echo "")
if [[ -n "$cilium_taints" ]]; then
    log_warning "Found leftover Cilium taints!"
    read -p "Remove Cilium taints from nodes? (y/N): " remove_taints
    if [ "$remove_taints" == "y" ] || [ "$remove_taints" == "Y" ]; then
        log_info "Removing Cilium taints..."
        nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
        for node in $nodes; do
            kubectl taint node "$node" node.cilium.io/agent-not-ready:NoSchedule- 2>/dev/null && log_success "Removed taint from $node" || log_info "No taint on $node"
        done
    fi
fi

# Delete resources in each namespace
for ns in "${NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &> /dev/null; then
        log_info "Cleaning namespace: $ns"

        # Delete all resources in namespace
        kubectl delete all --all -n "$ns" --timeout=60s 2>/dev/null || true

        # Delete specific resource types that might remain
        kubectl delete configmaps --all -n "$ns" --timeout=30s 2>/dev/null || true
        kubectl delete secrets --all -n "$ns" --timeout=30s 2>/dev/null || true
        kubectl delete networkpolicies --all -n "$ns" --timeout=30s 2>/dev/null || true
        kubectl delete ingress --all -n "$ns" --timeout=30s 2>/dev/null || true
    fi
done

# Delete PVCs (optional)
read -p "Delete Persistent Volume Claims? This will delete all data (y/N): " delete_pvcs
if [ "$delete_pvcs" == "y" ] || [ "$delete_pvcs" == "Y" ]; then
    log_warning "Deleting PVCs..."
    for ns in "${NAMESPACES[@]}"; do
        if kubectl get namespace "$ns" &> /dev/null; then
            kubectl delete pvc --all -n "$ns" --timeout=60s 2>/dev/null || true
        fi
    done
fi

# Wait for resources to be deleted
log_info "Waiting for resources to be deleted..."
sleep 10

# Force delete namespaces
log_info "Deleting namespaces..."
for ns in "${NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &> /dev/null; then
        log_info "Deleting namespace: $ns"
        kubectl delete namespace "$ns" --timeout=60s 2>/dev/null || {
            log_warning "Normal deletion failed for $ns, attempting force delete..."

            # Try to patch the namespace to remove finalizers
            kubectl patch namespace "$ns" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true

            # Force delete if still exists
            if kubectl get namespace "$ns" &> /dev/null; then
                kubectl delete namespace "$ns" --force --grace-period=0 2>/dev/null || true
            fi
        }
    else
        log_info "Namespace $ns already deleted"
    fi
done

# Wait for namespace deletion
log_info "Waiting for namespaces to be fully deleted..."
for i in {1..30}; do
    remaining_ns=""
    for ns in "${NAMESPACES[@]}"; do
        if kubectl get namespace "$ns" &> /dev/null; then
            remaining_ns="$remaining_ns $ns"
        fi
    done

    if [[ -z "$remaining_ns" ]]; then
        log_success "All namespaces deleted successfully"
        break
    else
        echo "Still waiting for namespaces:$remaining_ns (attempt $i/30)"
        sleep 2
    fi
done

# Final check and forced cleanup if needed
remaining_ns=""
for ns in "${NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &> /dev/null; then
        remaining_ns="$remaining_ns $ns"
    fi
done

if [[ -n "$remaining_ns" ]]; then
    log_warning "Some namespaces are stuck in Terminating state:$remaining_ns"
    log_info "Attempting forced cleanup..."

    for ns in $remaining_ns; do
        # Get the namespace as JSON and remove finalizers
        kubectl get namespace "$ns" -o json > "/tmp/${ns}.json" 2>/dev/null || continue
        sed -i '' 's/"finalizers": \[[^]]*\]/"finalizers": []/g' "/tmp/${ns}.json" 2>/dev/null || continue
        kubectl replace --raw "/api/v1/namespaces/${ns}/finalize" -f "/tmp/${ns}.json" 2>/dev/null || true
        rm -f "/tmp/${ns}.json"
    done
fi

# Clean up any remaining PVs
orphaned_pvs=$(kubectl get pv --no-headers 2>/dev/null | grep -E "(storage|messaging|kong|iam|zama-system|monitoring)" | awk '{print $1}' || echo "")
if [[ -n "$orphaned_pvs" && "$delete_pvcs" == "y" ]]; then
    log_info "Cleaning up orphaned persistent volumes..."
    echo "$orphaned_pvs" | xargs -I {} kubectl delete pv {} 2>/dev/null || true
fi

# Remove Helm repositories (optional)
read -p "Remove Helm repositories (nats, kong, cilium)? (y/N): " remove_repos
if [ "$remove_repos" == "y" ] || [ "$remove_repos" == "Y" ]; then
    log_info "Removing Helm repositories..."
    helm repo remove nats 2>/dev/null && log_success "Removed NATS helm repository" || log_info "NATS repository not found"
    helm repo remove kong 2>/dev/null && log_success "Removed Kong helm repository" || log_info "Kong repository not found"
    helm repo remove cilium 2>/dev/null && log_success "Removed Cilium helm repository" || log_info "Cilium repository not found"
fi

echo ""
echo "========================================"
echo "Enhanced Cleanup Complete!"
echo "========================================"
echo ""

# Final status check
log_info "Final status check:"

# Check for remaining namespaces
remaining_ns=""
for ns in "${NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &> /dev/null; then
        remaining_ns="$remaining_ns $ns"
    fi
done

if [[ -z "$remaining_ns" ]]; then
    log_success "✓ All Zama namespaces deleted"
else
    log_warning "⚠ Some namespaces still exist:$remaining_ns"
    log_info "These may be stuck in 'Terminating' state. Try restarting your cluster if needed."
fi

# Check for remaining Helm releases
remaining_releases=$(helm list -A -q 2>/dev/null | grep -E "(kong|nats)" || echo "")
if [[ -z "$remaining_releases" ]]; then
    log_success "✓ All Helm releases cleaned up"
else
    log_warning "⚠ Some Helm releases remain: $remaining_releases"
fi

# Check for remaining PVs
remaining_pvs=$(kubectl get pv --no-headers 2>/dev/null | grep -E "(storage|messaging|kong|iam|zama-system|monitoring)" || echo "")
if [[ -z "$remaining_pvs" ]]; then
    log_success "✓ All persistent volumes cleaned up"
else
    log_warning "⚠ Some persistent volumes remain"
    echo "$remaining_pvs"
fi

echo ""
log_info "Cleanup summary:"
echo "  - Use 'kubectl get namespaces' to verify namespace deletion"
echo "  - Use 'helm list -A' to check for remaining releases"
echo "  - Use 'kubectl get pv' to check for remaining volumes"
echo "  - If namespaces are stuck, restart your Kubernetes cluster"