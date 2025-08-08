#!/bin/bash

# Kubernetes Cluster Deployment Script
# This script will:
# 1. Deploy VMs with Terraform
# 2. Generate inventory.ini
# 3. Setup Kubernetes cluster with Ansible

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TF_DIR="$PROJECT_ROOT/tf_libvirt"

echo "================================"
echo "Kubernetes Cluster Deployment"
echo "================================"

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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed. Please install terraform first."
        exit 1
    fi
    
    # Check if ansible is installed
    if ! command -v ansible-playbook &> /dev/null; then
        log_error "Ansible is not installed. Please install ansible first."
        exit 1
    fi
    
    # Check if SSH key exists
    if [ ! -f ~/.ssh/id_rsa ]; then
        log_warn "SSH private key not found at ~/.ssh/id_rsa"
        log_info "Generating SSH key pair..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
    fi
    
    log_info "Prerequisites check completed."
}

# Function to deploy infrastructure
deploy_infrastructure() {
    log_info "Deploying infrastructure with Terraform..."
    
    cd "$TF_DIR"
    
    # Initialize Terraform
    terraform init
    
    # Plan deployment
    terraform plan -out=tfplan
    
    # Apply deployment
    terraform apply tfplan
    
    # Show outputs
    terraform output
    
    cd "$PROJECT_ROOT"
    log_info "Infrastructure deployment completed."
}

# Function to wait for VMs to be ready
wait_for_vms() {
    log_info "Waiting for VMs to be ready..."
    
    if [ ! -f "$PROJECT_ROOT/inventory.ini" ]; then
        log_error "inventory.ini not found. Terraform might not have completed successfully."
        exit 1
    fi
    
    # Extract IP addresses from inventory
    IPS=$(grep ansible_host "$PROJECT_ROOT/inventory.ini" | awk '{print $2}' | cut -d'=' -f2)
    
    for ip in $IPS; do
        log_info "Waiting for $ip to be accessible..."
        while ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@$ip "echo 'VM is ready'" &>/dev/null; do
            sleep 10
        done
        log_info "$ip is accessible"
    done
    
    log_info "All VMs are ready."
}

# Function to setup Kubernetes cluster
setup_kubernetes() {
    log_info "Setting up Kubernetes cluster with Ansible..."
    
    cd "$PROJECT_ROOT"
    
    # Test connectivity
    log_info "Testing Ansible connectivity..."
    ansible all -m ping
    
    # Run the main playbook
    log_info "Running Kubernetes setup playbook..."
    ansible-playbook scripts/site.yml -v
    
    log_info "Kubernetes cluster setup completed!"
}

# Function to display cluster information
display_cluster_info() {
    log_info "Displaying cluster information..."
    
    if [ -f "$PROJECT_ROOT/cluster-setup-summary.txt" ]; then
        cat "$PROJECT_ROOT/cluster-setup-summary.txt"
    else
        log_warn "Cluster summary not found."
    fi
    
    log_info "To access your cluster, SSH to the control plane node and use kubectl commands."
    log_info "Control plane nodes:"
    grep k8scpnode "$PROJECT_ROOT/inventory.ini" | awk '{print $1 " - " $2}' | sed 's/ansible_host=//'
}

# Function to cleanup
cleanup() {
    log_info "Cleaning up temporary files..."
    rm -f /tmp/k8s_join_command.sh
    rm -f "$TF_DIR/tfplan"
}

# Main deployment function
main() {
    case "${1:-deploy}" in
        "deploy")
            check_prerequisites
            deploy_infrastructure
            wait_for_vms
            setup_kubernetes
            display_cluster_info
            cleanup
            ;;
        "destroy")
            log_warn "Destroying infrastructure..."
            cd "$TF_DIR"
            terraform destroy -auto-approve
            cd "$PROJECT_ROOT"
            rm -f inventory.ini cluster-setup-summary.txt
            log_info "Infrastructure destroyed."
            ;;
        "status")
            if [ -f "$PROJECT_ROOT/inventory.ini" ]; then
                log_info "Current cluster status:"
                ansible k8s_control_plane -m shell -a "kubectl get nodes -o wide" -b --become-user=ubuntu
            else
                log_warn "No cluster found. Run '$0 deploy' to create one."
            fi
            ;;
        *)
            echo "Usage: $0 {deploy|destroy|status}"
            echo "  deploy  - Deploy VMs and setup Kubernetes cluster"
            echo "  destroy - Destroy the entire infrastructure"
            echo "  status  - Show current cluster status"
            exit 1
            ;;
    esac
}

# Trap to cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"
