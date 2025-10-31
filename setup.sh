#!/bin/bash

set -e

echo "🚀 Starting SPIFFE + Cerbos Demo Setup"

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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v minikube &> /dev/null; then
        log_error "minikube is not installed. Please install minikube first."
        exit 1
    fi
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi
    
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed. Please install helm first."
        exit 1
    fi
    
    if ! command -v cmctl &> /dev/null; then
        log_warning "cmctl is not installed. Installing..."
        # Install cmctl
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
        ARCH=$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')
        curl -fsSL -o cmctl.tar.gz "https://github.com/cert-manager/cert-manager/releases/latest/download/cmctl-${OS}-${ARCH}.tar.gz"
        tar xzf cmctl.tar.gz
        sudo mv cmctl /usr/local/bin
        rm cmctl.tar.gz
    fi
    
    log_success "Prerequisites check completed"
}

# Start minikube
setup_minikube() {
    log_info "Setting up minikube..."
    
    # Check if minikube is already running
    if minikube -p zero-trust status | grep -q "Running"; then
        log_warning "minikube profile 'zero-trust' is already running"
    else
        log_info "Starting minikube..."
        minikube -p zero-trust start
    fi
    
    # Setup Gateway API support
    log_info "Enabling Gateway API support..."
    kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null || \
    { kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v1.3.0" | kubectl apply -f -; }

    # Enable istio addons
    log_info "Enabling Istio addons..."
    minikube -p zero-trust addons enable istio-provisioner
    minikube -p zero-trust addons enable istio
    
    log_success "Minikube setup completed"
}

# Install cert-manager
install_cert_manager() {
    log_info "Installing cert-manager..."
    
    # Create namespace
    kubectl create ns cert-manager --dry-run=client -o yaml | kubectl apply -f -
    
    # Add helm repo
    helm repo add jetstack https://charts.jetstack.io --force-update
    helm repo update
    
    # Install cert-manager
    log_info "Installing cert-manager core..."
    helm upgrade --install \
        cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --version v1.18.2 \
        --set crds.enabled=true \
        --wait
    
    # Install CSI driver
    log_info "Installing cert-manager CSI driver..."
    helm upgrade --install \
        cert-manager-csi-driver jetstack/cert-manager-csi-driver \
        --namespace cert-manager \
        --wait
    
    # Update cert-manager to disable auto approval
    existing_cert_manager_version=$(helm get metadata -n cert-manager cert-manager | grep '^VERSION' | awk '{ print $2 }')
    helm upgrade cert-manager jetstack/cert-manager \
        --reuse-values \
        --namespace cert-manager \
        --version $existing_cert_manager_version \
        --set disableAutoApproval=true
    
    # Create issuer config
    kubectl create configmap -n cert-manager spiffe-issuer \
        --from-literal=issuer-name=csi-driver-spiffe-ca \
        --from-literal=issuer-kind=ClusterIssuer \
        --from-literal=issuer-group=cert-manager.io \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Install SPIFFE CSI driver
    log_info "Installing SPIFFE CSI driver..."
    helm upgrade --install \
        cert-manager-csi-driver-spiffe jetstack/cert-manager-csi-driver-spiffe \
        --namespace cert-manager \
        --set "app.logLevel=1" \
        --set "app.trustDomain=demo.cerbos.io" \
        --set "app.issuer.name=" \
        --set "app.issuer.kind=" \
        --set "app.issuer.group=" \
        --set "app.runtimeIssuanceConfigMap=spiffe-issuer" \
        --wait
    
    log_success "cert-manager installation completed"
}

# Create cluster issuer
setup_cluster_issuer() {
    log_info "Setting up cluster issuer..."
    
    curl -fsSL https://raw.githubusercontent.com/cert-manager/csi-driver-spiffe/ed646ccf28b1ecdf63f628bf16f1d350a9b850c1/deploy/example/clusterissuer.yaml | kubectl apply -f -
    
    log_success "Cluster issuer setup completed"
}

# Create sandbox namespace
setup_sandbox() {
    log_info "Setting up sandbox namespace..."
    
    kubectl create namespace sandbox --dry-run=client -o yaml | kubectl apply -f -

    log_info "Enabling Istio sidecar injection in sandbox namespace..."
    kubectl label namespace sandbox istio-injection=enabled --overwrite
    
    # Apply RBAC for certificate requests
    log_info "Applying RBAC for certificate requests..."
    kubectl apply -f cluster-rbac.yaml
    
    log_success "Sandbox namespace created"
}

setup_authorization_namespace() {
    log_info "Setting up authorization namespace..."

    kubectl create namespace authorization --dry-run=client -o yaml | kubectl apply -f -

    log_info "Enabling Istio sidecar injection in authorization namespace..."
    kubectl label namespace authorization istio-injection=enabled --overwrite

    log_success "Authorization namespace created"
}

apply_network_policies() {
    log_info "Applying network policies..."
    
    kubectl apply -f network-policies.yaml
    
    log_success "Network policies applied"
}

# Configure Istio gateway
configure_istio_gateway() {
    log_info "Configuring Istio ingress gateway..."
    
    kubectl apply -f istio-gateway.yaml
    
    log_success "Istio ingress gateway configured"
}

configure_external_authorization() {
    log_info "Configuring external authorization provider..."
    
    local cm_tmp updated_tmp
    cm_tmp=$(mktemp)
    updated_tmp=$(mktemp)

    local attempts=0
    until kubectl get configmap istio -n istio-system -o json > "$cm_tmp"; do
        attempts=$((attempts + 1))
        if [ $attempts -ge 6 ]; then
            log_error "Failed to retrieve Istio mesh config after multiple attempts"
            rm -f "$cm_tmp" "$updated_tmp"
            exit 1
        fi
        log_warning "Istio mesh config not ready yet, retrying..."
        sleep 5
    done

    python3 - "$cm_tmp" "$updated_tmp" <<'PY'
import json
import sys

_, config_path, output_path = sys.argv

with open(config_path, "r", encoding="utf-8") as fh:
    cm = json.load(fh)

mesh = cm.get("data", {}).get("mesh", "")
provider_snippet = """
extensionProviders:
- name: external-authz-grpc
  envoyExtAuthzGrpc:
    service: cerbos-adapter-service.authorization.svc.cluster.local
    port: 9090
    timeout: 3s
    failOpen: false
""".lstrip("\n")

if "name: external-authz-grpc" not in mesh:
    if mesh and not mesh.endswith("\n"):
        mesh += "\n"
    mesh += provider_snippet
else:
    updated_mesh = mesh.replace(
        "service: external-authz.sandbox.svc.cluster.local",
        "service: cerbos-adapter-service.authorization.svc.cluster.local",
    ).replace(
        "service: cerbos-adapter-service.backend.svc.cluster.local",
        "service: cerbos-adapter-service.authorization.svc.cluster.local",
    ).replace("port: 9000", "port: 9090").replace("failOpen: true", "failOpen: false")
    mesh = updated_mesh

cm.setdefault("data", {})["mesh"] = mesh

with open(output_path, "w", encoding="utf-8") as fh:
    json.dump(cm, fh)
PY

    kubectl apply -f "$updated_tmp"
    rm -f "$cm_tmp" "$updated_tmp"
    
    kubectl apply -f spiffe-backend-authz-policy.yaml
    
    log_success "External authorization configuration completed"
}

# Deploy Cerbos
deploy_cerbos() {
    log_info "Deploying Cerbos..."
    
    kubectl apply -f cerbos-deployment.yaml
    
    # Wait for Cerbos to be ready
    log_info "Waiting for Cerbos to be ready..."
    kubectl wait --for=condition=ready pod -l app=cerbos -n authorization --timeout=300s
    
    log_success "Cerbos deployment completed"
}

# Build and deploy demo applications
deploy_demo_apps() {
    log_info "Building and deploying demo applications..."
    
    # Set docker environment to use minikube's docker daemon
    eval $(minikube -p zero-trust docker-env)
    
    # Build SPIFFE demo app
    log_info "Building SPIFFE demo app..."
    (cd spiffe-demo-app && docker build -t spiffe-demo-app:latest .)
    
    # Build SPIFFE demo backend
    log_info "Building SPIFFE demo backend..."
    (cd spiffe-demo-backend && docker build -t spiffe-demo-backend:latest .)
    
    # Deploy applications
    log_info "Deploying SPIFFE demo app..."
    kubectl apply -f spiffe-demo-app/k8s-deployment.yaml
    
    log_info "Deploying SPIFFE demo backend..."
    kubectl apply -f spiffe-demo-backend/k8s-deployment.yaml
    
    log_success "Demo applications deployment completed"
}

# Approve certificate requests
approve_certificates() {
    log_info "Approving certificate requests..."
    
    # Wait a bit for certificate requests to be created
    sleep 10
    
    # Approve all certificate requests
    for cr in $(kubectl get cr -n cert-manager -o jsonpath='{.items[*].metadata.name}'); do
        log_info "Approving cert-manager certificate request: $cr"
        cmctl approve -n cert-manager $cr || log_warning "Failed to approve $cr (may already be approved)"
    done
    
    log_success "Certificate approval completed"
}

# Wait for deployments
wait_for_deployments() {
    log_info "Waiting for deployments to be ready..."
    
    kubectl wait --for=condition=available deployment/spiffe-demo-app -n sandbox --timeout=300s
    kubectl wait --for=condition=available deployment/spiffe-demo-backend -n sandbox --timeout=300s
    
    log_success "All deployments are ready"
}

# Setup port forwarding
setup_port_forwarding() {
    log_info "Setting up port forwarding..."
    
    # Kill any existing port-forward processes
    pkill -f "kubectl.*port-forward" || true

    # Port forward for gateway
    kubectl port-forward -n istio-system svc/istio-ingressgateway 8088:80 &
    INGRESS_PF_PID=$!
    
    # Save PIDs to a file for cleanup
    echo "$INGRESS_PF_PID" > .port-forward-pids
    
    log_success "Port forwarding setup completed"
    log_info "Port forwarding for Istio ingress gateway is running (PID: $INGRESS_PF_PID)"
}

# Display final information
display_final_info() {
    echo ""
    log_success "🎉 Setup completed successfully!"
    echo ""
    echo "Useful commands:"
    echo "  kubectl get pods -n sandbox"
    echo "  kubectl logs -n sandbox deployment/spiffe-demo-app"
    echo "  kubectl logs -n sandbox deployment/spiffe-demo-backend"
    echo ""
    echo "To view SPIFFE identity of the sample app:"
    echo '  kubectl exec -n sandbox $(kubectl get pod -n sandbox -l app=spiffe-demo-app -o jsonpath='"'"'{.items[0].metadata.name}'"'"') -- cat /var/run/secrets/spiffe.io/tls.crt | openssl x509 --noout --text | grep "URI:"'
    echo ""
    echo "To stop port forwarding:"
    echo "  ./cleanup.sh"
    echo ""
}

# Main execution
main() {
    check_prerequisites
    setup_minikube
    install_cert_manager
    setup_cluster_issuer
    setup_sandbox
    setup_authorization_namespace
    apply_network_policies
    configure_istio_gateway
    configure_external_authorization
    deploy_cerbos
    deploy_demo_apps
    approve_certificates
    wait_for_deployments
    setup_port_forwarding
    display_final_info
}

# Handle Ctrl+C
trap 'log_info "Setup interrupted. Run ./cleanup.sh to clean up resources."; exit 1' INT

main "$@"
