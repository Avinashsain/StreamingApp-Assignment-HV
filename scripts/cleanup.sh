#!/usr/bin/env bash
# Tears down billable resources. Order matters: helm uninstall FIRST (deletes
# the ELBs and mongo EBS volume), then the cluster, then leftovers.
# Prompts before each step. Steps 3-5 are optional (near-zero cost resources).
# Usage: ./scripts/cleanup.sh
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-streamingapp-eks}"
RELEASE_NAME="${RELEASE_NAME:-streamingapp}"
NAMESPACE="${NAMESPACE:-streamingapp}"
ECR_PREFIX="${ECR_PREFIX:-streamingapp}"
SNS_TOPIC_NAME="${SNS_TOPIC_NAME:-streamingapp-alerts}"
ALARM_NAME="${ALARM_NAME:-streamingapp-high-cpu}"

echo "Region: ${AWS_REGION} | Cluster: ${CLUSTER_NAME} | Release: ${RELEASE_NAME}"
echo "(Override with env vars if these are wrong — a stray CLUSTER_NAME in your"
echo " shell profile once pointed this script at the wrong cluster!)"
echo ""

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

read -rp "3) Delete CloudWatch log groups for '${CLUSTER_NAME}' (Container Insights)? [y/N] " a
if [[ "${a}" =~ ^[Yy]$ ]]; then
  for lg in $(aws logs describe-log-groups --region "${AWS_REGION}" \
      --log-group-name-prefix "/aws/containerinsights/${CLUSTER_NAME}" \
      --query 'logGroups[].logGroupName' --output text); do
    echo "  Deleting log group: ${lg}"
    aws logs delete-log-group --log-group-name "${lg}" --region "${AWS_REGION}"
  done
fi

read -rp "4) Delete CloudWatch alarm '${ALARM_NAME}' + SNS topic '${SNS_TOPIC_NAME}'? [y/N] " a
if [[ "${a}" =~ ^[Yy]$ ]]; then
  aws cloudwatch delete-alarms --alarm-names "${ALARM_NAME}" --region "${AWS_REGION}" || true
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  aws sns delete-topic \
    --topic-arn "arn:aws:sns:${AWS_REGION}:${ACCOUNT_ID}:${SNS_TOPIC_NAME}" \
    --region "${AWS_REGION}" || true
fi

read -rp "5) Delete all 5 ECR repositories (streamingapp/*) INCLUDING images? [y/N] " a
if [[ "${a}" =~ ^[Yy]$ ]]; then
  for repo in frontend auth streaming admin chat; do
    echo "  Deleting ECR repo: ${ECR_PREFIX}/${repo}"
    aws ecr delete-repository --repository-name "${ECR_PREFIX}/${repo}" \
      --force --region "${AWS_REGION}" || true
  done
fi

echo ""
echo "=== Final verification (all should be empty) ==="
echo "-> EKS clusters:"
aws eks list-clusters --region "${AWS_REGION}" --query 'clusters' --output text || true
echo "-> Load balancers:"
aws elb describe-load-balancers --region "${AWS_REGION}" \
  --query 'LoadBalancerDescriptions[].LoadBalancerName' --output text || true
echo "-> Unattached EBS volumes:"
aws ec2 describe-volumes --region "${AWS_REGION}" \
  --filters Name=status,Values=available --query 'Volumes[].VolumeId' --output text || true
echo "-> Running EC2 instances:"
aws ec2 describe-instances --region "${AWS_REGION}" \
  --filters Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].InstanceId' --output text || true
echo "-> Container Insights log groups:"
aws logs describe-log-groups --region "${AWS_REGION}" \
  --log-group-name-prefix "/aws/containerinsights" \
  --query 'logGroups[].logGroupName' --output text || true
echo ""
echo "If every line above is blank, nothing is billing. Done."
echo "(Not touched: S3 bucket — delete manually if no longer needed:"
echo "  aws s3 rb s3://<bucket-name> --force --region <bucket-region>)"