#!/usr/bin/env bash
# Tears down billable resources. Order matters: helm uninstall FIRST (deletes
# the ELBs and mongo EBS volume), then the cluster. Prompts before each step.
# Usage: ./scripts/cleanup.sh
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-streamingapp-eks}"
RELEASE_NAME="${RELEASE_NAME:-streamingapp}"
NAMESPACE="${NAMESPACE:-streamingapp}"

read -rp "1) helm uninstall '${RELEASE_NAME}' (deletes app + all ELBs)? [y/N] " a
if [[ "${a}" =~ ^[Yy]$ ]]; then
  helm uninstall "${RELEASE_NAME}" -n "${NAMESPACE}" || true
  kubectl delete pvc --all -n "${NAMESPACE}" || true   # mongo EBS volume
  echo "Waiting 60s for AWS to remove the ELBs..." && sleep 60
fi

read -rp "2) DELETE the EKS cluster '${CLUSTER_NAME}' (~10 min)? [y/N] " a
if [[ "${a}" =~ ^[Yy]$ ]]; then
  eksctl delete cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}"
fi

echo ""
echo "Verify nothing is left billing:"
echo "  aws elb describe-load-balancers --region ${AWS_REGION} --query 'LoadBalancerDescriptions[].LoadBalancerName'"
echo "  aws ec2 describe-volumes --region ${AWS_REGION} --filters Name=status,Values=available --query 'Volumes[].VolumeId'"
