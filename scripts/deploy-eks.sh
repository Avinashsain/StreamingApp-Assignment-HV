#!/usr/bin/env bash
# Deploys/upgrades the Helm release on EKS with the given image tag.
# Usage: IMAGE_TAG=<tag-you-pushed> ./scripts/deploy-eks.sh
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
ECR_PREFIX="${ECR_PREFIX:-streamingapp}"
CLUSTER_NAME="${CLUSTER_NAME:-streamingapp-eks}"
RELEASE_NAME="${RELEASE_NAME:-streamingapp}"
NAMESPACE="${NAMESPACE:-streamingapp}"
CHART_PATH="${CHART_PATH:-helm/streamingapp}"
IMAGE_TAG="${IMAGE_TAG:?Set IMAGE_TAG to the tag you pushed to ECR (see build-and-push-ecr.sh output)}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null

helm upgrade --install "${RELEASE_NAME}" "${CHART_PATH}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --set image.registry="${ECR_REGISTRY}" \
  --set image.tag="${IMAGE_TAG}"

echo ""
kubectl -n "${NAMESPACE}" get pods
echo ""
echo ">> Waiting for LoadBalancer hostnames (may take 2-3 min)..."
kubectl -n "${NAMESPACE}" get svc \
  -o custom-columns='SERVICE:.metadata.name,PORT:.spec.ports[0].port,EXTERNAL-URL:.status.loadBalancer.ingress[0].hostname'
echo ""
echo "Re-run './scripts/get-service-urls.sh' until all EXTERNAL-URLs appear."
