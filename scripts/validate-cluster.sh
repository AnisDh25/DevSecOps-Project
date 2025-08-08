#!/bin/bash

# Kubernetes Cluster Validation Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_cluster_health() {
    log_info "Checking cluster health..."
    
    cd "$PROJECT_ROOT"
    
    # Check if inventory exists
    if [ ! -f "inventory.ini" ]; then
        log_error "inventory.ini not found. Please run deployment first."
        exit 1
    fi
    
    # Test connectivity to all nodes
    log_info "Testing connectivity to all nodes..."
    if ansible all -m ping > /dev/null 2>&1; then
        log_info "✓ All nodes are accessible"
    else
        log_error "✗ Some nodes are not accessible"
        return 1
    fi
    
    # Check cluster status
    log_info "Checking Kubernetes cluster status..."
    
    # Get cluster info
    CLUSTER_INFO=$(ansible k8s_control_plane -m shell -a "kubectl cluster-info" -b --become-user=ubuntu 2>/dev/null | grep -A 10 "k8scpnode1 | CHANGED")
    
    if echo "$CLUSTER_INFO" | grep -q "Kubernetes control plane is running"; then
        log_info "✓ Kubernetes control plane is running"
    else
        log_error "✗ Kubernetes control plane is not running"
        return 1
    fi
    
    # Check nodes status
    log_info "Checking nodes status..."
    NODES_STATUS=$(ansible k8s_control_plane -m shell -a "kubectl get nodes --no-headers" -b --become-user=ubuntu 2>/dev/null | grep -A 10 "k8scpnode1 | CHANGED")
    
    READY_NODES=$(echo "$NODES_STATUS" | grep -c "Ready" || true)
    TOTAL_NODES=$(echo "$NODES_STATUS" | grep -c "k8s" || true)
    
    if [ "$READY_NODES" -eq "$TOTAL_NODES" ] && [ "$TOTAL_NODES" -gt 0 ]; then
        log_info "✓ All nodes are Ready ($READY_NODES/$TOTAL_NODES)"
    else
        log_warn "⚠ Some nodes are not Ready ($READY_NODES/$TOTAL_NODES)"
    fi
    
    # Check system pods
    log_info "Checking system pods..."
    PODS_STATUS=$(ansible k8s_control_plane -m shell -a "kubectl get pods -n kube-system --no-headers" -b --become-user=ubuntu 2>/dev/null | grep -A 20 "k8scpnode1 | CHANGED")
    
    RUNNING_PODS=$(echo "$PODS_STATUS" | grep -c "Running" || true)
    TOTAL_PODS=$(echo "$PODS_STATUS" | grep -c "kube-\|coredns\|flannel" || true)
    
    if [ "$RUNNING_PODS" -eq "$TOTAL_PODS" ] && [ "$TOTAL_PODS" -gt 0 ]; then
        log_info "✓ All system pods are Running ($RUNNING_PODS/$TOTAL_PODS)"
    else
        log_warn "⚠ Some system pods are not Running ($RUNNING_PODS/$TOTAL_PODS)"
    fi
    
    # Test pod creation
    log_info "Testing pod creation..."
    ansible k8s_control_plane -m shell -a "kubectl run test-pod --image=nginx --rm -it --restart=Never --timeout=60s -- echo 'Hello Kubernetes'" -b --become-user=ubuntu > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_info "✓ Pod creation test successful"
    else
        log_warn "⚠ Pod creation test failed"
    fi
    
    log_info "Cluster health check completed."
}

run_smoke_tests() {
    log_info "Running smoke tests..."
    
    cd "$PROJECT_ROOT"
    
    # Test 1: Deploy a simple application
    log_info "Test 1: Deploying nginx application..."
    
    cat > /tmp/nginx-test.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-test
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx-test
  template:
    metadata:
      labels:
        app: nginx-test
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-test-service
  namespace: default
spec:
  selector:
    app: nginx-test
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
EOF
    
    # Copy and apply the test manifest
    ansible k8s_control_plane -m copy -a "src=/tmp/nginx-test.yaml dest=/tmp/nginx-test.yaml" > /dev/null 2>&1
    ansible k8s_control_plane -m shell -a "kubectl apply -f /tmp/nginx-test.yaml" -b --become-user=ubuntu > /dev/null 2>&1
    
    # Wait for deployment to be ready
    sleep 30
    
    # Check if pods are running
    NGINX_PODS=$(ansible k8s_control_plane -m shell -a "kubectl get pods -l app=nginx-test --no-headers | grep Running | wc -l" -b --become-user=ubuntu 2>/dev/null | grep -A 1 "k8scpnode1 | CHANGED" | tail -1)
    
    if [ "$NGINX_PODS" -eq 2 ]; then
        log_info "✓ Nginx test deployment successful (2/2 pods running)"
    else
        log_warn "⚠ Nginx test deployment failed ($NGINX_PODS/2 pods running)"
    fi
    
    # Cleanup
    ansible k8s_control_plane -m shell -a "kubectl delete -f /tmp/nginx-test.yaml" -b --become-user=ubuntu > /dev/null 2>&1
    
    # Test 2: DNS resolution
    log_info "Test 2: Testing DNS resolution..."
    
    DNS_TEST=$(ansible k8s_control_plane -m shell -a "kubectl run dns-test --image=busybox --rm -it --restart=Never --timeout=30s -- nslookup kubernetes.default.svc.cluster.local" -b --become-user=ubuntu 2>/dev/null)
    
    if echo "$DNS_TEST" | grep -q "kubernetes.default.svc.cluster.local"; then
        log_info "✓ DNS resolution test successful"
    else
        log_warn "⚠ DNS resolution test failed"
    fi
    
    log_info "Smoke tests completed."
}

generate_report() {
    log_info "Generating cluster report..."
    
    cd "$PROJECT_ROOT"
    
    # Get detailed cluster information
    CLUSTER_INFO=$(ansible k8s_control_plane -m shell -a "kubectl cluster-info" -b --become-user=ubuntu 2>/dev/null)
    NODES_INFO=$(ansible k8s_control_plane -m shell -a "kubectl get nodes -o wide" -b --become-user=ubuntu 2>/dev/null)
    PODS_INFO=$(ansible k8s_control_plane -m shell -a "kubectl get pods -A" -b --become-user=ubuntu 2>/dev/null)
    SERVICES_INFO=$(ansible k8s_control_plane -m shell -a "kubectl get svc -A" -b --become-user=ubuntu 2>/dev/null)
    
    # Create report
    cat > validation-report.txt << EOF
Kubernetes Cluster Validation Report
===================================
Generated: $(date)

CLUSTER INFORMATION:
$(echo "$CLUSTER_INFO" | grep -A 10 "k8scpnode1 | CHANGED" | tail -n +2)

NODES:
$(echo "$NODES_INFO" | grep -A 10 "k8scpnode1 | CHANGED" | tail -n +2)

PODS:
$(echo "$PODS_INFO" | grep -A 20 "k8scpnode1 | CHANGED" | tail -n +2)

SERVICES:
$(echo "$SERVICES_INFO" | grep -A 20 "k8scpnode1 | CHANGED" | tail -n +2)

EOF
    
    log_info "Validation report saved to validation-report.txt"
}

main() {
    case "${1:-check}" in
        "check")
            check_cluster_health
            ;;
        "test")
            check_cluster_health
            run_smoke_tests
            ;;
        "report")
            check_cluster_health
            generate_report
            ;;
        "all")
            check_cluster_health
            run_smoke_tests
            generate_report
            ;;
        *)
            echo "Usage: $0 {check|test|report|all}"
            echo "  check  - Basic cluster health check"
            echo "  test   - Run health check and smoke tests"
            echo "  report - Generate detailed cluster report"
            echo "  all    - Run all validations and generate report"
            exit 1
            ;;
    esac
}

main "$@"
