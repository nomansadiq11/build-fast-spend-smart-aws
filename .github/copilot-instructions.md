# GitHub Copilot System Instructions

## Project Context & Mission
This repository powers the live demonstration environment and runbook for the AWS Community Day session:
**"Build Fast, Spend Smart: Hands-On with AWS FinOps & DevOps Agents"**

The objective of this project is to provide single-command CloudFormation templates (`aws cloudformation deploy`) that temporarily spin up an AWS environment for live testing, and completely destroy all billable resources (`aws cloudformation delete-stack`) when finished.

The CloudFormation stack creates two operational testing grounds for native AWS AI Agents:
1. **AWS DevOps Agent Scenario:** An Amazon EKS cluster with `AWS::EKS::AccessEntry` configured for the DevOps Agent service role, running a containerized application failing due to `OOMKilled` (Exit Code 137) or `ImagePullBackOff`.
2. **AWS FinOps Agent Scenario:** Configured cost drivers (multi-AZ NAT Gateways, unattached `gp3` EBS volumes, and oversized EC2 instances) paired with AWS Cost Anomaly Monitors to generate live cost insights and optimization recommendations.

---

## Directory Architecture & Blueprint
When generating code in this repository, strictly adhere to the following file layout:

```text
.
├── .github/
│   └── copilot-instructions.md
├── README.md                      # Presentation runbook, architecture diagram & demo script
├── cloudformation/                # Modular AWS CloudFormation Templates
│   ├── master.yaml                # Nested stack orchestration template
│   ├── eks-cluster.yaml           # EKS cluster, NodeGroup, & AWS::EKS::AccessEntry
│   ├── cost-environment.yaml      # Cost anomaly setup (NAT Gateway, EC2, EBS)
│   └── parameters/
│       ├── dev.json               # CloudFormation parameter overrides
│       └── dev.json.example
├── manifests/                     # Kubernetes manifests for fault injection
│   ├── app-baseline.yaml          # Healthy baseline deployment
│   ├── inject-oom-fault.yaml      # Restricted memory limits triggering OOMKilled
│   └── inject-bad-image.yaml      # Invalid container tag triggering ImagePullBackOff
├── prompts/                       # Scripted prompts for presentation demos
│   ├── devops_agent_prompts.md    # Natural language queries for AWS DevOps Agent
│   └── finops_agent_prompts.md    # Natural language queries for AWS FinOps Agent
└── scripts/                       # Shell scripts for stack spin-up and teardown
    ├── deploy_demo.sh             # Deploys CloudFormation stack & applies k8s baseline
    ├── trigger_fault.sh           # Swaps k8s manifests live on stage
    └── teardown.sh                # Deletes CloudFormation stack to zero out costs
```

## Conventions

- All CloudFormation templates use YAML, not JSON.
- Every billable resource must be tagged with `Project: build-fast-spend-smart` and `Ephemeral: true` so it is trivially identifiable and can be torn down without leaving orphaned cost.
- Nested templates (`eks-cluster.yaml`, `cost-environment.yaml`) are uploaded to S3 via `aws cloudformation package` before `master.yaml` is deployed — never hardcode a `TemplateURL`.
- Parameter files under `cloudformation/parameters/` are consumed with `--parameter-overrides file://...` (or `aws cloudformation deploy ... --parameter-overrides $(cat ...)`); `dev.json` is git-ignored, `dev.json.example` is the committed template.
- Shell scripts under `scripts/` must be POSIX-friendly bash, use `set -euo pipefail`, and never assume the caller's working directory — always `cd` to the repo root first.
- Kubernetes manifests under `manifests/` target a single `demo` namespace and are designed to be swapped in-place with `kubectl apply -f` during the live demo (`trigger_fault.sh` handles the swap).
- Keep everything scoped to a single demo session: no persistent state, no data that must survive `teardown.sh`.
