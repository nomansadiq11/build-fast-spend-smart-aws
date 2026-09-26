# AWS DevOps Agent — Demo Prompts

Scripted natural-language prompts for the live demo against the `demo` namespace
on the EKS cluster created by `cloudformation/eks-cluster.yaml`. Run
`scripts/trigger_fault.sh oom` or `scripts/trigger_fault.sh bad-image` first,
then ask the agent one of the prompts below.

## 1. Initial triage

> "The `demo-app` deployment in the `demo` namespace on cluster
> `build-fast-spend-smart-demo` looks unhealthy. Can you investigate what's
> wrong and summarize the root cause?"

## 2. OOMKilled scenario (after `trigger_fault.sh oom`)

> "Pods for `demo-app` keep restarting. Check their exit codes and recent
> events, and tell me if this is a memory problem."

> "What memory limit would you recommend for the `demo-app` container based
> on its actual usage, and can you propose the manifest change?"

## 3. ImagePullBackOff scenario (after `trigger_fault.sh bad-image`)

> "Some `demo-app` pods are stuck in `ImagePullBackOff`. Identify the image
> reference causing the failure and suggest the correct tag to roll back to."

## 4. Remediation & verification

> "Roll `demo-app` back to the last known-good configuration and confirm all
> pods reach `Running` with 0 restarts."

> "Summarize the incident timeline: what broke, what fixed it, and what
> guardrail would prevent it from happening again."
