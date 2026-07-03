#!/usr/bin/env bash
# Prints the public ELB URLs of all services and ready-to-paste FE_* exports
# for the Run-2 frontend rebuild.
# Usage: ./scripts/get-service-urls.sh
set -euo pipefail

NAMESPACE="${NAMESPACE:-streamingapp}"

get_lb() { kubectl -n "${NAMESPACE}" get svc "$1" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true; }

AUTH=$(get_lb auth); STREAM=$(get_lb streaming); ADMIN=$(get_lb admin); CHAT=$(get_lb chat); FRONT=$(get_lb frontend)

echo "frontend  : http://${FRONT:-<pending>}"
echo "auth      : http://${AUTH:-<pending>}:3001"
echo "streaming : http://${STREAM:-<pending>}:3002"
echo "admin     : http://${ADMIN:-<pending>}:3003"
echo "chat      : http://${CHAT:-<pending>}:3004"
echo ""
echo "# Paste these before running build-and-push-ecr.sh (Run 2),"
echo "# or copy the values into the Jenkinsfile FE_* variables:"
echo "export FE_AUTH=http://${AUTH}:3001/api"
echo "export FE_STREAM=http://${STREAM}:3002/api"
echo "export FE_STREAM_PUB=http://${STREAM}:3002"
echo "export FE_ADMIN=http://${ADMIN}:3003/api/admin"
echo "export FE_CHAT=http://${CHAT}:3004/api/chat"
echo "export FE_CHAT_SOCK=http://${CHAT}:3004"
echo ""
echo "# Also set CORS in the chart:"
echo "#   helm/streamingapp/values.yaml -> env.clientUrls: \"http://${FRONT}\""
