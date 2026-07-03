#!/usr/bin/env bash
# Creates one ECR repository per service (idempotent - safe to run repeatedly).
# Usage: ./scripts/create-ecr-repos.sh
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
ECR_PREFIX="${ECR_PREFIX:-streamingapp}"

services=(frontend auth streaming admin chat)

for service in "${services[@]}"; do
  repo="${ECR_PREFIX}/${service}"
  if aws ecr describe-repositories --repository-names "${repo}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    echo "ECR repository already exists: ${repo}"
  else
    aws ecr create-repository \
      --repository-name "${repo}" \
      --image-scanning-configuration scanOnPush=true \
      --encryption-configuration encryptionType=AES256 \
      --region "${AWS_REGION}" >/dev/null
    echo "Created ECR repository: ${repo}"
  fi
done
