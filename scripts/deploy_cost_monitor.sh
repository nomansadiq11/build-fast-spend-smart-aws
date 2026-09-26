#!/usr/bin/env bash
# Deploys the persistent AWS Cost Anomaly Detection monitor. Run this ONCE,
# well ahead of the demo (ideally ~10 days prior) -- unlike the ephemeral
# stack from deploy_demo.sh, do NOT tear this down between test iterations,
# or the anomaly-detection learning period resets. This stack costs nothing
# on its own to keep running.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

STACK_NAME="${MONITOR_STACK_NAME:-build-fast-spend-smart-cost-monitor}"
REGION="${AWS_REGION:-us-east-1}"
PROFILE="${AWS_PROFILE:-}"
PROJECT_TAG="${PROJECT_TAG:-build-fast-spend-smart}"
ANOMALY_ALERT_EMAIL="${ANOMALY_ALERT_EMAIL:-}"

PROFILE_ARGS=()
if [[ -n "$PROFILE" ]]; then
  PROFILE_ARGS=(--profile "$PROFILE")
fi

echo "==> Deploying persistent Cost Anomaly Monitor stack: ${STACK_NAME}"
aws cloudformation deploy \
  --template-file cloudformation/cost-anomaly-monitor.yaml \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --parameter-overrides ProjectTag="$PROJECT_TAG" AnomalyAlertEmail="$ANOMALY_ALERT_EMAIL" \
  "${PROFILE_ARGS[@]}"

echo "==> Done. Leave this stack running until after the demo -- do not include it in teardown.sh."
