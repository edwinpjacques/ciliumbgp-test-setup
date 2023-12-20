#!/bin/bash

: ${FRR_VERSION:="9.0.2"}
: ${CILIUM_VERSION:="1.14.4"}

set -x
set -o pipefail

function die() {
    echo "FAIL: $*"
    exit 1
}

function info() {
    echo "INFO: $*"
}

config_dir=$(readlink -f $(dirname "$0"))
test -d "$config_dir" || die "directory does not exist: $config_dir"

# Create frr container on the host network
# Mount configuration from the host.
torr_frr_container=$(docker ps -q -f name=tor_frr)
if [[ -z "$torr_frr_container" ]]; then
    docker run --rm -d --privileged --name tor_frr --network host \
        --volume "$config_dir/frr/daemons:/etc/frr/daemons" \
        --volume "$config_dir/frr/frr.conf:/etc/frr/frr.conf" \
        quay.io/frrouting/frr:$FRR_VERSION
else
    info "torr_frr container already running ($torr_frr_container)"
fi

# Create kindbgp network
kindbgp_network=$(docker network ls -f name=kindbgp -q)
if [[ -z "$kindbgp_network" ]]; then
    docker network create \
        --driver bridge \
        --subnet "172.28.0.0/16" \
        --gateway "172.28.0.1" \
        --ip-range "172.28.0.0/16" \
        -o "com.docker.network.bridge.enable_ip_masquerade=true" \
        --attachable \
        kindbgp
fi

# Create the kind cluster with the kindbgp network
cluster=$(kind get clusters | grep ciliumbgp)
if [[ -z "$cluster" ]]; then
    KIND_EXPERIMENTAL_DOCKER_NETWORK=kindbgp kind create cluster "--config=$config_dir/kindciliumbgp.yaml"
fi

# Make sure cilium is not installed
cilium uninstall --wait

# Install cilium operator and CNI with BGP control plane enabled
cilium --context kind-ciliumbgp install --wait --version "1.14.4" \
    --set "k8sServiceHost=ciliumbgp-control-plane" \
    --set "k8sServicePort=6443" \
    --set "externalIPs.enabled=true" \
    --set "nodePort.enabled=true" \
    --set "hostPort.enabled=true" \
    --set "ipam.mode=kubernetes" \
    --set "tunnel=disabled" \
    --set "ipv4NativeRoutingCIDR=10.12.0.0/16" \
    --set "bgpControlPlane.enabled=true"

# Wait for cilium to operational
cilium --context kind-ciliumbgp status --wait

# Node annotation to specify AS and port:
kubectl --context kind-ciliumbgp annotate node/ciliumbgp-control-plane cilium.io/bgp-virtual-router.65013="local-port=179"
kubectl --context kind-ciliumbgp annotate node/ciliumbgp-worker cilium.io/bgp-virtual-router.65013="local-port=179"
kubectl --context kind-ciliumbgp annotate node/ciliumbgp-worker2 cilium.io/bgp-virtual-router.65013="local-port=179"

# Add labels for cilium nodes
kubectl --context kind-ciliumbgp label ciliumnodes.cilium.io ciliumbgp-control-plane bgp-policy=host
kubectl --context kind-ciliumbgp label ciliumnodes.cilium.io ciliumbgp-worker bgp-policy=host
kubectl --context kind-ciliumbgp label ciliumnodes.cilium.io ciliumbgp-worker2 bgp-policy=host

# Configure the routing policy
kubectl --context kind-ciliumbgp apply -f "$config_dir/ciliumpeerpolicy.yaml"

# Create a pool of load balancer IPs
kubectl --context kind-ciliumbgp apply -f "$config_dir/ciliumlbIPpool.yaml"

# Create nginx deployment
kubectl --context kind-ciliumbgp apply -f "$config_dir/nginxDeployment.yaml"

# Expose the nginx LoadBalancer service
kubectl --context kind-ciliumbgp apply -f "$config_dir/nginxService.yaml"
