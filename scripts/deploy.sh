#!/bin/bash
set -e

# CV-Site GitOps Deployment Script
# This script bootstraps the entire infrastructure using Argo CD

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITOPS_DIR="$(dirname "$SCRIPT_DIR")"

echo "================================================"
echo "  CV-Site GitOps Deployment"
echo "================================================"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi

    if ! command -v helm &> /dev/null; then
        log_error "helm not found. Please install helm."
        exit 1
    fi

    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster."
        exit 1
    fi

    log_info "Prerequisites check passed."
}

# Install cert-manager
install_cert_manager() {
    log_info "Installing cert-manager..."

    if kubectl get namespace cert-manager &> /dev/null; then
        log_warn "cert-manager namespace already exists, skipping..."
        return
    fi

    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml

    log_info "Waiting for cert-manager to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n cert-manager
    kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-webhook -n cert-manager
    kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-cainjector -n cert-manager

    log_info "cert-manager installed successfully."
}

# Install Strimzi operator
install_strimzi() {
    log_info "Installing Strimzi Kafka operator..."

    # Create namespace
    kubectl create namespace kafka-prd --dry-run=client -o yaml | kubectl apply -f -

    if kubectl get deployment strimzi-cluster-operator -n kafka-prd &> /dev/null; then
        log_warn "Strimzi operator already installed, skipping..."
        return
    fi

    kubectl apply -f "https://strimzi.io/install/latest?namespace=kafka-prd" -n kafka-prd

    log_info "Waiting for Strimzi operator to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/strimzi-cluster-operator -n kafka-prd

    log_info "Strimzi operator installed successfully."
}

# Install Argo CD
install_argocd() {
    log_info "Installing Argo CD..."

    # Create namespace
    kubectl apply -f "$GITOPS_DIR/bootstrap/argocd-namespace.yaml"

    if kubectl get deployment argocd-server -n argocd &> /dev/null; then
        log_warn "Argo CD already installed, skipping..."
        return
    fi

    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    log_info "Waiting for Argo CD to be ready..."
    kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd
    kubectl wait --for=condition=available --timeout=600s deployment/argocd-repo-server -n argocd
    kubectl wait --for=condition=available --timeout=600s deployment/argocd-applicationset-controller -n argocd

    log_info "Argo CD installed successfully."
}

# Get Argo CD admin password
get_argocd_password() {
    log_info "Retrieving Argo CD admin password..."

    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

    echo ""
    echo "================================================"
    echo "  Argo CD Credentials"
    echo "================================================"
    echo "  Username: admin"
    echo "  Password: $ARGOCD_PASSWORD"
    echo "================================================"
    echo ""
}

# Deploy App of Apps
deploy_app_of_apps() {
    log_info "Deploying App of Apps..."

    kubectl apply -f "$GITOPS_DIR/bootstrap/app-of-apps.yaml"

    log_info "App of Apps deployed. Argo CD will now sync all applications."
}

# Port forward Argo CD
port_forward_argocd() {
    log_info "To access Argo CD UI, run:"
    echo ""
    echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo ""
    echo "Then open: https://localhost:8080"
    echo ""
}

# Main
main() {
    check_prerequisites

    echo ""
    log_info "Starting deployment..."
    echo ""

    install_cert_manager
    install_strimzi
    install_argocd
    get_argocd_password
    deploy_app_of_apps
    port_forward_argocd

    echo ""
    log_info "Deployment complete!"
    echo ""
    echo "================================================"
    echo "  Next Steps"
    echo "================================================"
    echo "  1. Access Argo CD UI at https://localhost:8080"
    echo "  2. Login with credentials shown above"
    echo "  3. Watch applications sync in the UI"
    echo "  4. Configure DNS records for your domain"
    echo "  5. Update secrets in production values"
    echo "================================================"
}

main "$@"
