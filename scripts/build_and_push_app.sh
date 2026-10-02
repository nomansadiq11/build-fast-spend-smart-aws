#!/usr/bin/env bash
# Builds the custom "AWS Community Day Demo" app image and pushes it to the
# ECR repository created by cloudformation/eks-cluster.yaml. Run this after
# deploy_demo.sh (needs the AppRepositoryUri stack output) and before
# trigger_fault.sh / applying manifests, since the manifests reference this
# image by tag.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

STACK_NAME="${STACK_NAME:-build-fast-spend-smart}"
REGION="${AWS_REGION:-us-east-1}"
PROFILE="${AWS_PROFILE:-}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

if [[ ! "$IMAGE_TAG" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,127}$ ]]; then
  echo "IMAGE_TAG must be a tag such as 'latest', not a full ECR image URI." >&2
  exit 1
fi

PROFILE_ARGS=()
if [[ -n "$PROFILE" ]]; then
  PROFILE_ARGS=(--profile "$PROFILE")
fi

REPO_URI=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  "${PROFILE_ARGS[@]}" \
  --query "Stacks[0].Outputs[?OutputKey=='AppRepositoryUri'].OutputValue" \
  --output text)

if [[ -z "$REPO_URI" || "$REPO_URI" == "None" ]]; then
  echo "Could not find AppRepositoryUri output on stack ${STACK_NAME}. Deploy the stack first." >&2
  exit 1
fi

REGISTRY="${REPO_URI%%/*}"

echo "==> Logging in to ECR registry: ${REGISTRY}"
aws ecr get-login-password --region "$REGION" "${PROFILE_ARGS[@]}" \
  | docker login --username AWS --password-stdin "$REGISTRY"

if ! docker buildx inspect demo-multiarch >/dev/null 2>&1; then
  docker buildx create --name demo-multiarch --driver docker-container
fi

echo "==> Building and pushing AMD64/ARM64 image ${REPO_URI}:${IMAGE_TAG}"
docker buildx build --builder demo-multiarch --platform linux/amd64,linux/arm64 \
  -t "${REPO_URI}:${IMAGE_TAG}" --push app/

echo "==> Done. Image available at: ${REPO_URI}:${IMAGE_TAG}"
