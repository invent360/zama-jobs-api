#!/bin/bash

# Cilium Installation Script

set -e

echo "Installing Cilium CNI with Gateway API support..."

# Add Cilium Helm repo
helm repo add cilium https://helm.cilium.io/
helm repo update

# Check if we're on Minikube or Docker Desktop
CLUSTER_TYPE=""
if kubectl config current-context | grep -q "minikube"; then
    CLUSTER_TYPE="minikube"
elif kubectl config current-context | grep -q "docker-desktop"; then
    CLUSTER_TYPE="docker-desktop"
fi

# Install Cilium
helm upgrade --install cilium cilium/cilium \
    --version 1.18.2 \
    --namespace kube-system \
    --values values.yaml \
    --wait

# Install Cilium CLI if not present
if ! command -v cilium &> /dev/null; then
    echo "Installing Cilium CLI..."
    CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
    CLI_ARCH=amd64

    if [[ "$OSTYPE" == "darwin"* ]]; then
        curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-darwin-${CLI_ARCH}.tar.gz{,.sha256sum}
        shasum -a 256 -c cilium-darwin-${CLI_ARCH}.tar.gz.sha256sum
        sudo tar xzvfC cilium-darwin-${CLI_ARCH}.tar.gz /usr/local/bin
        rm cilium-darwin-${CLI_ARCH}.tar.gz{,.sha256sum}
    else
        curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
        sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
        sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
        rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
    fi
fi

# Wait for Cilium to be ready
echo "Waiting for Cilium to be ready..."
cilium status --wait

# Enable Hubble for observability
echo "Enabling Hubble..."
cilium hubble enable --ui

echo "Cilium installation complete!"
echo "You can check status with: cilium status"