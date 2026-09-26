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

echo "==> Building image ${REPO_URI}:${IMAGE_TAG}"
docker build -t "${REPO_URI}:${IMAGE_TAG}" app/

echo "==> Pushing image ${REPO_URI}:${IMAGE_TAG}"
docker push "${REPO_URI}:${IMAGE_TAG}"

echo "==> Done. Image available at: ${REPO_URI}:${IMAGE_TAG}"
