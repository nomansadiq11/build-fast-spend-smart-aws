#!/usr/bin/env bash
# Deletes the CloudFormation stack (and every nested resource) to zero out
# demo costs. Safe to re-run; missing-stack errors are ignored.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

STACK_NAME="${STACK_NAME:-build-fast-spend-smart}"
REGION="${AWS_REGION:-us-east-1}"
PROFILE="${AWS_PROFILE:-}"

PROFILE_ARGS=()
if [[ -n "$PROFILE" ]]; then
  PROFILE_ARGS=(--profile "$PROFILE")
fi

# The demo-app Service is type=LoadBalancer, so it provisions an ELB outside of
# CloudFormation. Delete it first so the ELB is deregistered and removed cleanly
# instead of being orphaned (still billing) or blocking VPC/subnet deletion below.
if kubectl get svc demo-app -n demo >/dev/null 2>&1; then
  echo "==> Deleting demo-app Service to release its LoadBalancer"
  kubectl delete -f manifests/app-baseline.yaml --ignore-not-found --wait=true
fi

# Polls stack events and prints only new ones (chronological) until the
# background delete PID passed to it exits. Tails nested stacks too, while
# they still exist (they disappear from describe-stack-resources once gone,
# so failures there are swallowed with `|| true`).
tail_stack_events() {
  local delete_pid="$1"
  local seen_file
  seen_file=$(mktemp)
  while kill -0 "$delete_pid" 2>/dev/null; do
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

echo "==> Deleting CloudFormation stack: ${STACK_NAME} (region ${REGION}, streaming events below)"
aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION" "${PROFILE_ARGS[@]}"

(
  while true; do
    status=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" "${PROFILE_ARGS[@]}" \
      --query "Stacks[0].StackStatus" --output text 2>/dev/null || echo "STACK_GONE")
    if [[ "$status" == "STACK_GONE" || "$status" == "DELETE_COMPLETE" || "$status" == "DELETE_FAILED" ]]; then
      break
    fi
    sleep 3
  done
) &
DELETE_WATCH_PID=$!

tail_stack_events "$DELETE_WATCH_PID"

aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION" "${PROFILE_ARGS[@]}" || {
  echo "Stack deletion did not complete cleanly. Check the CloudFormation console for retained resources." >&2
  exit 1
}

echo "==> Stack ${STACK_NAME} deleted. All billable demo resources are torn down."
