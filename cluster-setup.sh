#!/bin/bash
# =============================================================================
# TimescaleDB Cluster Setup Script
# =============================================================================
# Deploys TimescaleDB cluster with pgvector and pgvectorscale on Kubernetes
# 
# Steps:
#   1. Create namespace
#   2. Deploy custom image catalog
#   3. Deploy 3-pod TimescaleDB cluster
#   4. Wait for cluster readiness
#   5. Verify deployment
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NAMESPACE="timescaledb"
CLUSTER_NAME="timescaledb-cluster"

# =============================================================================
# Helper Functions
# =============================================================================

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

# =============================================================================
# Main Deployment
# =============================================================================

print_header "TimescaleDB Cluster Deployment"

echo "🚀 Deploying TimescaleDB cluster..."
echo ""

# Step 1: Create namespace
print_info "Creating namespace..."
kubectl apply -f kubernetes/namespace.yaml
print_success "Namespace created"
echo ""

# Step 2: Deploy image catalog
print_info "Deploying custom image catalog..."
kubectl apply -f kubernetes/imagecatalog-timescaledb.yaml
print_success "Image catalog deployed"
echo ""

# Step 3: Deploy cluster
print_info "Deploying TimescaleDB cluster (3 pods)..."
kubectl apply -f kubernetes/cluster-timescaledb.yaml
print_success "Cluster manifest applied"
echo ""

# Step 4: Wait for cluster to be ready
print_info "Waiting for cluster to initialize (this may take 2-3 minutes)..."
echo ""

# Wait for the cluster resource to be created
sleep 5

# Wait for pods to be created
print_info "Waiting for pods to be created..."
for i in {1..60}; do
    POD_COUNT=$(kubectl get pods -n $NAMESPACE -l cnpg.io/cluster=$CLUSTER_NAME --no-headers 2>/dev/null | wc -l)
    if [ "$POD_COUNT" -gt 0 ]; then
        print_success "Pods created ($POD_COUNT found)"
        break
    fi
    if [ $i -eq 60 ]; then
        print_error "Timeout waiting for pods to be created"
        exit 1
    fi
    sleep 2
done

echo ""

# Wait for all 3 pods to be ready
print_info "Waiting for all pods to be ready..."
kubectl wait --for=condition=ready pod \
    -l cnpg.io/cluster=$CLUSTER_NAME \
    -n $NAMESPACE \
    --timeout=400s

echo ""
print_success "All pods are ready!"

# =============================================================================
# Verification
# =============================================================================

print_header "Deployment Verification"

# Show cluster status
echo "Cluster Status:"
kubectl get cluster -n $NAMESPACE

echo ""
echo "Pod Status:"
kubectl get pods -n $NAMESPACE -o wide

echo ""
echo "Services:"
kubectl get svc -n $NAMESPACE


# =============================================================================
# Summary
# =============================================================================

print_header "Deployment Complete!"

echo "Cluster Information:"
echo "  • Namespace: $NAMESPACE"
echo "  • Cluster: $CLUSTER_NAME"
echo "  • Pods: 3 (1 primary + 2 replicas)"
echo ""
echo "Connection Details:"
echo "  • Primary pod: ${CLUSTER_NAME}-1"
echo "  • Database: postgres (default)"
echo "  • User: postgres"
echo ""
echo "Next Steps:"
echo "  1. Run ./initialize-db.sh to set up the sample application"
echo "  2. Run ./run-capability-tests.sh to validate the deployment"
echo ""
echo "Quick Test:"
echo "  kubectl exec -it ${CLUSTER_NAME}-1 -n $NAMESPACE -- psql -U postgres -c '\\dx'"
echo ""