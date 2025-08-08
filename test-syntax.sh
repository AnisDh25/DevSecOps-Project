#!/bin/bash

# Test the prepare-nodes.yml playbook syntax
echo "Testing Ansible playbook syntax..."

cd /home/bios/WorkSpace/Devsecops/k8s_cluster

# Check syntax of all playbooks
echo "Checking prepare-nodes.yml syntax..."
ansible-playbook --syntax-check scripts/prepare-nodes.yml

echo "Checking setup-control-plane.yml syntax..."
ansible-playbook --syntax-check scripts/setup-control-plane.yml

echo "Checking setup-workers.yml syntax..."
ansible-playbook --syntax-check scripts/setup-workers.yml

echo "Checking verify-cluster.yml syntax..."
ansible-playbook --syntax-check scripts/verify-cluster.yml

echo "Checking site.yml syntax..."
ansible-playbook --syntax-check scripts/site.yml

echo "All syntax checks completed!"
