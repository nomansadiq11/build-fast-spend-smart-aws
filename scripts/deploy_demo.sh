#!/usr/bin/env bash
# Deploys the "Build Fast, Spend Smart" demo stack and applies the healthy
# k8s baseline. Requires: aws cli v2, kubectl, an S3 bucket for packaging.
# Set AWS_PROFILE to use a named CLI profile instead of default credentials.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

STACK_NAME="${STACK_NAME:-build-fast-spend-smart}"
REGION="${AWS_REGION:-us-east-1}"
PROFILE="${AWS_PROFILE:-}"
TEMPLATE_BUCKET="${TEMPLATE_BUCKET:?Set TEMPLATE_BUCKET to an S3 bucket (optionally s3://bucket/prefix) you own for packaging nested templates}"
PARAM_FILE="${PARAM_FILE:-cloudformation/parameters/dev.json}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

if [[ ! "$IMAGE_TAG" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,127}$ ]]; then
  echo "IMAGE_TAG must be a tag such as 'latest', not a full ECR image URI." >&2
  exit 1
fi

# Threaded through every aws cli call below; empty when AWS_PROFILE is unset.
PROFILE_ARGS=()
if [[ -n "$PROFILE" ]]; then
  PROFILE_ARGS=(--profile "$PROFILE")
fi

# Accepts a bare bucket name or a full s3://bucket/prefix/ path.
TEMPLATE_BUCKET="${TEMPLATE_BUCKET#s3://}"
TEMPLATE_BUCKET="${TEMPLATE_BUCKET%/}"
S3_BUCKET_NAME="${TEMPLATE_BUCKET%%/*}"
S3_PREFIX=""
if [[ "$TEMPLATE_BUCKET" == */* ]]; then
  S3_PREFIX="${TEMPLATE_BUCKET#*/}"
fi

if [[ ! -f "$PARAM_FILE" ]]; then
  echo "Missing $PARAM_FILE. Copy cloudformation/parameters/dev.json.example and fill it in." >&2
  exit 1
fi

echo "==> Packaging nested templates to s3://${S3_BUCKET_NAME}/${S3_PREFIX}"
aws cloudformation package \
  --template-file cloudformation/master.yaml \
  --s3-bucket "$S3_BUCKET_NAME" \
  ${S3_PREFIX:+--s3-prefix "$S3_PREFIX"} \
  --output-template-file /tmp/master.packaged.yaml \
  --region "$REGION" \
  "${PROFILE_ARGS[@]}"

PARAM_OVERRIDES=$(python3 -c "
import json, sys
with open('$PARAM_FILE') as f:
    params = json.load(f)
print(' '.join(f'{k}={v}' for k, v in params.items()))
")

# Polls stack events and prints only new ones (chronological), until the
# background deploy PID passed to it exits. Also tails nested stacks, whose
# physical IDs are discovered dynamically since they don't exist until the
# root stack starts creating them.
tail_stack_events() {
  local deploy_pid="$1"
  local seen_file
  seen_file=$(mktemp)
  while kill -0 "$deploy_pid" 2>/dev/null; do
    nested_stacks=$(aws cloudformation describe-stack-resources \
      --stack-name "$STACK_NAME" \
      --region "$REGION" \
      "${PROFILE_ARGS[@]}" \
      --query "StackResources[?ResourceType=='AWS::CloudFormation::Stack'].PhysicalResourceId" \
      --output text 2>/dev/null || true)
    for stack in "$STACK_NAME" $nested_stacks; do
      aws cloudformation describe-stack-events \
        --stack-name "$stack" \
        --region "$REGION" \
        "${PROFILE_ARGS[@]}" \
        --query "reverse(StackEvents[].[Timestamp,LogicalResourceId,ResourceStatus,ResourceStatusReason])" \
        --output text 2>/dev/null | while IFS=$'\t' read -r ts logical status reason; do
          key="${ts}|${logical}|${status}"
          if ! grep -qF "$key" "$seen_file" 2>/dev/null; then
            echo "$key" >>"$seen_file"
            if [[ "$reason" == "None" ]]; then reason=""; fi
            echo "[$ts] ${logical}: ${status} ${reason}"
          fi
        done
    done
    sleep 5
  done
  rm -f "$seen_file"
}

echo "==> Deploying CloudFormation stack: ${STACK_NAME} (streaming events below)"
aws cloudformation deploy \
  --template-file /tmp/master.packaged.yaml \
  --stack-name "$STACK_NAME" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "$REGION" \
  --parameter-overrides $PARAM_OVERRIDES \
  "${PROFILE_ARGS[@]}" &
DEPLOY_PID=$!

tail_stack_events "$DEPLOY_PID"

if ! wait "$DEPLOY_PID"; then
  echo "Stack deployment failed. See the events above (or the CloudFormation console) for the resource that failed." >&2
  exit 1
fi

CLUSTER_NAME=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='ClusterName'].OutputValue" \
  --output text \
  "${PROFILE_ARGS[@]}")

echo "==> Updating kubeconfig for cluster: ${CLUSTER_NAME}"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" "${PROFILE_ARGS[@]}"

APP_REPO_URI=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  "${PROFILE_ARGS[@]}" \
  --query "Stacks[0].Outputs[?OutputKey=='AppRepositoryUri'].OutputValue" \
  --output text)
APP_IMAGE="${APP_REPO_URI}:${IMAGE_TAG}"

if command -v docker >/dev/null 2>&1; then
  echo "==> Building and pushing the custom demo app image"
  IMAGE_TAG="$IMAGE_TAG" ./scripts/build_and_push_app.sh
else
  echo "docker not found -- skipping image build/push." >&2
  echo "Run ./scripts/build_and_push_app.sh manually, then: kubectl apply -f manifests/app-baseline.yaml (after substituting __APP_IMAGE__)." >&2
fi

echo "==> Applying healthy baseline app to the demo namespace"
sed -e "s#__APP_IMAGE__#${APP_IMAGE}#g" manifests/app-baseline.yaml | kubectl apply -f -
kubectl rollout restart deployment/demo-app -n demo

echo "==> Waiting for demo-app rollout"
kubectl rollout status deployment/demo-app -n demo --timeout=180s

echo "==> Demo environment is ready. Stack: ${STACK_NAME}, Cluster: ${CLUSTER_NAME}"
