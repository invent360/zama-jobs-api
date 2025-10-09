#!/bin/bash

# Force cleanup script for stuck namespaces
# Use this only when normal cleanup fails

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
echo "Zama Jobs API - Force Cleanup"
echo "========================================"

log_warning "This script will forcefully delete stuck namespaces!"
log_warning "Use this only if normal cleanup fails."
echo ""

# Confirm deletion
read -p "Are you sure you want to force delete ALL Zama namespaces? (type 'FORCE' to confirm): " confirm
if [ "$confirm" != "FORCE" ]; then
    echo "Force cleanup cancelled"
    exit 0
fi

# Define namespaces
NAMESPACES=("zama-system" "kong" "iam" "messaging" "monitoring" "storage")

# Force delete all helm releases
log_info "Force deleting all Helm releases..."

# Delete standard Kong release
helm uninstall kong -n kong --timeout=30s 2>/dev/null && log_info "Deleted Kong release" || log_info "Kong release not found"

# Delete standard NATS release
helm uninstall nats -n messaging --timeout=30s 2>/dev/null && log_info "Deleted NATS release" || log_info "NATS release not found"

# Also check for any other releases in case there are leftovers
other_releases=$(helm list -A --short | grep -E "(kong|nats)" | grep -v "^kong kong$" | grep -v "^nats messaging$" || echo "")
if [[ -n "$other_releases" ]]; then
    echo "$other_releases" | while read -r release namespace; do
        log_info "Force deleting additional helm release: $release in namespace: $namespace"
        helm uninstall "$release" -n "$namespace" --timeout=30s 2>/dev/null || true
    done
fi

# Remove Cilium taints from nodes
log_info "Removing Cilium taints from nodes..."
nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [[ -n "$nodes" ]]; then
    for node in $nodes; do
        # Remove Cilium agent-not-ready taint
        kubectl taint node "$node" node.cilium.io/agent-not-ready:NoSchedule- 2>/dev/null && log_success "Removed Cilium taint from $node" || log_info "No Cilium taint on $node"

        # Remove other potential Cilium taints
        kubectl taint node "$node" node.cilium.io/agent-not-ready- 2>/dev/null || true
        kubectl taint node "$node" cilium.io/no-schedule- 2>/dev/null || true
    done
else
    log_warning "No nodes found or unable to access nodes"
fi

# Kill all port forwarding
pkill -f "kubectl port-forward" 2>/dev/null || true

# Force delete each namespace
for ns in "${NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &> /dev/null; then
        log_info "Force deleting namespace: $ns"

        # Step 1: Delete all resources in namespace
        kubectl delete all --all -n "$ns" --force --grace-period=0 --timeout=30s 2>/dev/null || true

        # Step 2: Delete all other resource types
        kubectl delete configmaps,secrets,pvc,networkpolicies,ingress --all -n "$ns" --force --grace-period=0 --timeout=30s 2>/dev/null || true

        # Step 3: Get namespace JSON and remove finalizers
        kubectl get namespace "$ns" -o json > "/tmp/${ns}-ns.json" 2>/dev/null && {
            # Remove finalizers from the JSON
            cat "/tmp/${ns}-ns.json" | jq '.spec.finalizers=[]' > "/tmp/${ns}-ns-clean.json" 2>/dev/null || {
                # Fallback if jq is not available
                sed 's/"finalizers": \[[^]]*\]/"finalizers": []/g' "/tmp/${ns}-ns.json" > "/tmp/${ns}-ns-clean.json"
            }

            # Apply the cleaned namespace
            kubectl replace --raw "/api/v1/namespaces/${ns}/finalize" -f "/tmp/${ns}-ns-clean.json" 2>/dev/null || true

            # Clean up temp files
            rm -f "/tmp/${ns}-ns.json" "/tmp/${ns}-ns-clean.json"
        }

        # Step 4: Force delete the namespace
        kubectl delete namespace "$ns" --force --grace-period=0 --timeout=30s 2>/dev/null || true

        # Step 5: Try to patch finalizers directly
        kubectl patch namespace "$ns" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true

        log_info "Attempted force deletion of namespace: $ns"
    else
        log_success "Namespace $ns already deleted"
    fi
done

# Wait a moment
sleep 5

# Force delete any remaining PVs
log_info "Force deleting orphaned persistent volumes..."
orphaned_pvs=$(kubectl get pv --no-headers 2>/dev/null | grep -E "(storage|messaging|kong|iam|zama-system|monitoring)" | awk '{print $1}' || echo "")
if [[ -n "$orphaned_pvs" ]]; then
    echo "$orphaned_pvs" | xargs -I {} kubectl delete pv {} --force --grace-period=0 2>/dev/null || true
fi

# Remove Helm repositories
log_info "Removing Helm repositories..."
helm repo remove nats 2>/dev/null && log_success "Removed NATS helm repository" || log_info "NATS repository not found"
helm repo remove kong 2>/dev/null && log_success "Removed Kong helm repository" || log_info "Kong repository not found"
helm repo remove cilium 2>/dev/null && log_success "Removed Cilium helm repository" || log_info "Cilium repository not found"

# Final check
echo ""
log_info "Final status check..."

remaining_ns=""
for ns in "${NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &> /dev/null; then
        status=$(kubectl get namespace "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        remaining_ns="$remaining_ns $ns($status)"
    fi
done

if [[ -z "$remaining_ns" ]]; then
    log_success "✓ All namespaces successfully deleted!"
else
    log_warning "⚠ Some namespaces still exist:$remaining_ns"
    echo ""
    log_error "If namespaces are still stuck in 'Terminating' state:"
    echo "1. Try restarting Docker Desktop or your Kubernetes cluster"
    echo "2. For Docker Desktop: Docker menu → Restart"
    echo "3. For Minikube: minikube stop && minikube start"
    echo "4. Check for any webhook configurations: kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations"
fi

# Check for remaining helm releases
remaining_releases=$(helm list -A -q 2>/dev/null | grep -E "(kong|nats)" || echo "")
if [[ -n "$remaining_releases" ]]; then
    log_warning "⚠ Some Helm releases still exist: $remaining_releases"
    echo "Consider manually removing them: helm uninstall <release-name> -n <namespace>"
fi

echo ""
echo "========================================"
echo "Force Cleanup Complete!"
echo "========================================"