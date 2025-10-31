#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Stop port forwarding
stop_port_forwarding() {
    log_info "Stopping port forwarding..."
    
    # Kill port-forward processes
    if [ -f .port-forward-pids ]; then
        for pid in $(cat .port-forward-pids); do
            if kill -0 $pid 2>/dev/null; then
                kill $pid
                log_info "Stopped port-forward process $pid"
            fi
        done
        rm .port-forward-pids
    fi
    
    # Kill any remaining kubectl port-forward processes
    pkill -f "kubectl.*port-forward" && log_info "Killed remaining port-forward processes" || true
    
    log_success "Port forwarding stopped"
}

# Clean up applications
cleanup_applications() {
    log_info "Cleaning up applications..."
    
    # Delete demo applications
    kubectl delete -f spiffe-demo-app/k8s-deployment.yaml --ignore-not-found=true
    kubectl delete -f cerbos-deployment.yaml --ignore-not-found=true
    kubectl delete -f istio-gateway.yaml --ignore-not-found=true
    kubectl delete -f network-policies.yaml --ignore-not-found=true
    
    # Delete sample app
    kubectl delete -f https://raw.githubusercontent.com/cert-manager/csi-driver-spiffe/ed646ccf28b1ecdf63f628bf16f1d350a9b850c1/deploy/example/example-app.yaml --ignore-not-found=true
    
    log_success "Applications cleanup completed"
}

# Clean up cert-manager
cleanup_cert_manager() {
    log_info "Cleaning up cert-manager..."
    
    # Uninstall SPIFFE CSI driver
    helm uninstall cert-manager-csi-driver-spiffe -n cert-manager || true
    
    # Uninstall CSI driver
    helm uninstall cert-manager-csi-driver -n cert-manager || true
    
    # Uninstall cert-manager
    helm uninstall cert-manager -n cert-manager || true
    
    # Delete cluster issuer
    kubectl delete -f https://raw.githubusercontent.com/cert-manager/csi-driver-spiffe/ed646ccf28b1ecdf63f628bf16f1d350a9b850c1/deploy/example/clusterissuer.yaml --ignore-not-found=true
    
    # Delete configmap
    kubectl delete configmap spiffe-issuer -n cert-manager --ignore-not-found=true
    
    log_success "cert-manager cleanup completed"
}

# Clean up namespaces
cleanup_namespaces() {
    log_info "Cleaning up namespaces..."
    
    kubectl delete namespace sandbox --ignore-not-found=true
    kubectl delete namespace cert-manager --ignore-not-found=true
    
    log_success "Namespaces cleanup completed"
}

# Stop minikube
cleanup_minikube() {
    if [ "$1" = "--delete-minikube" ]; then
        log_info "Deleting minikube cluster..."
        minikube -p zero-trust delete
        log_success "Minikube cluster deleted"
    else
        log_info "Stopping minikube cluster..."
        minikube -p zero-trust stop
        log_success "Minikube cluster stopped"
        log_warning "To completely delete the cluster, run: $0 --delete-minikube"
    fi
}

# Display cleanup info
display_cleanup_info() {
    echo ""
    log_success "🧹 Cleanup completed!"
    echo ""
    
    if [ "$1" = "--delete-minikube" ]; then
        echo "The minikube cluster has been completely deleted."
    else
        echo "The minikube cluster has been stopped but not deleted."
        echo "To start it again, run: minikube -p zero-trust start"
        echo "To completely delete it, run: $0 --delete-minikube"
    fi
    echo ""
}

# Main cleanup function
main() {
    log_info "🧹 Starting cleanup..."
    
    stop_port_forwarding
    cleanup_applications
    cleanup_cert_manager
    cleanup_namespaces
    cleanup_minikube "$1"
    display_cleanup_info "$1"
}

# Handle script arguments
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [--delete-minikube]"
    echo ""
    echo "Options:"
    echo "  --delete-minikube    Completely delete the minikube cluster"
    echo "  --help, -h          Show this help message"
    echo ""
    echo "By default, this script will stop the minikube cluster but not delete it."
    exit 0
fi

main "$1"
