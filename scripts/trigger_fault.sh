#!/usr/bin/env bash
# Swaps the demo-app deployment in-place to trigger a fault (OOMKilled or
# ImagePullBackOff) for the AWS DevOps Agent to diagnose live on stage.
# Usage: scripts/trigger_fault.sh {oom|bad-image|reset}
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

STACK_NAME="${STACK_NAME:-build-fast-spend-smart}"
REGION="${AWS_REGION:-us-east-1}"
PROFILE="${AWS_PROFILE:-}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

PROFILE_ARGS=()
if [[ -n "$PROFILE" ]]; then
  PROFILE_ARGS=(--profile "$PROFILE")
fi

FAULT="${1:-}"

case "$FAULT" in
  oom)
    MANIFEST="manifests/inject-oom-fault.yaml"
    ;;
  bad-image)
    MANIFEST="manifests/inject-bad-image.yaml"
    ;;
  reset)
    MANIFEST="manifests/app-baseline.yaml"
    ;;
  *)
    echo "Usage: $0 {oom|bad-image|reset}" >&2
    exit 1
    ;;
esac

# Manifests reference __APP_IMAGE__/__APP_IMAGE_REPO__ placeholders, resolved
# here from the ECR repository the stack created (see build_and_push_app.sh).
APP_REPO_URI=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  "${PROFILE_ARGS[@]}" \
  --query "Stacks[0].Outputs[?OutputKey=='AppRepositoryUri'].OutputValue" \
  --output text)
APP_IMAGE="${APP_REPO_URI}:${IMAGE_TAG}"

echo "==> Applying $MANIFEST to namespace demo"
sed -e "s#__APP_IMAGE_REPO__#${APP_REPO_URI}#g" -e "s#__APP_IMAGE__#${APP_IMAGE}#g" "$MANIFEST" | kubectl apply -f -

echo "==> Current demo-app pods:"
kubectl get pods -n demo -l app=demo-app -o wide
