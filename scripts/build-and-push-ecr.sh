#!/usr/bin/env bash
# Builds all 5 images and pushes them to ECR, tagged with the git commit SHA.
# Same logic as the Jenkinsfile - lets you build/push by hand without Jenkins.
#
# NOTE: images are built for linux/amd64 because the EKS worker nodes are x86_64.
# Building on Apple Silicon without this flag produces arm64 images that fail
# on the nodes with "no match for platform in manifest".
#
# Usage:
#   ./scripts/build-and-push-ecr.sh                    # backends + placeholder frontend
#   FE_AUTH=http://... FE_STREAM=http://... FE_STREAM_PUB=http://... \
#   FE_ADMIN=http://... FE_CHAT=http://... FE_CHAT_SOCK=http://... \
#   ./scripts/build-and-push-ecr.sh                    # frontend with real backend URLs
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
ECR_PREFIX="${ECR_PREFIX:-streamingapp}"
PLATFORM="${PLATFORM:-linux/amd64}"
IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short=12 HEAD 2>/dev/null || date +%Y%m%d%H%M%S)}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Frontend runtime URLs (React bakes these in at BUILD time).
# Defaults are placeholders for the first deploy (Run 1); pass real ELB URLs for Run 2.
FE_AUTH="${FE_AUTH:-http://placeholder:3001/api}"
FE_STREAM="${FE_STREAM:-http://placeholder:3002/api}"
FE_STREAM_PUB="${FE_STREAM_PUB:-http://placeholder:3002}"
FE_ADMIN="${FE_ADMIN:-http://placeholder:3003/api/admin}"
FE_CHAT="${FE_CHAT:-http://placeholder:3004/api/chat}"
FE_CHAT_SOCK="${FE_CHAT_SOCK:-http://placeholder:3004}"

echo ">> Logging in to ${ECR_REGISTRY}"
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${ECR_REGISTRY}"

"$(dirname "$0")/create-ecr-repos.sh"

# name : build-context : dockerfile-path-relative-to-context
services=(auth streaming admin chat)
contexts=(backend/authService backend backend backend)
dockerfiles=(Dockerfile streamingService/Dockerfile adminService/Dockerfile chatService/Dockerfile)

for i in "${!services[@]}"; do
  image="${ECR_REGISTRY}/${ECR_PREFIX}/${services[$i]}:${IMAGE_TAG}"
  echo ">> Building ${image} (${PLATFORM})"
  docker build --platform "${PLATFORM}" -t "${image}" -f "${contexts[$i]}/${dockerfiles[$i]}" "${contexts[$i]}"
  docker push "${image}"
done

fe_image="${ECR_REGISTRY}/${ECR_PREFIX}/frontend:${IMAGE_TAG}"
echo ">> Building ${fe_image} (${PLATFORM})"
docker build --platform "${PLATFORM}" -t "${fe_image}" \
  --build-arg REACT_APP_AUTH_API_URL="${FE_AUTH}" \
  --build-arg REACT_APP_STREAMING_API_URL="${FE_STREAM}" \
  --build-arg REACT_APP_STREAMING_PUBLIC_URL="${FE_STREAM_PUB}" \
  --build-arg REACT_APP_ADMIN_API_URL="${FE_ADMIN}" \
  --build-arg REACT_APP_CHAT_API_URL="${FE_CHAT}" \
  --build-arg REACT_APP_CHAT_SOCKET_URL="${FE_CHAT_SOCK}" \
  ./frontend
docker push "${fe_image}"

echo ""
echo "All images pushed. IMAGE_TAG=${IMAGE_TAG}"
echo "Deploy with: IMAGE_TAG=${IMAGE_TAG} ./scripts/deploy-eks.sh"