# AWS FinOps Agent — Demo Prompts

Scripted natural-language prompts for the live demo against the cost drivers
created by `cloudformation/cost-environment.yaml` (multi-AZ NAT Gateways, an
unattached gp3 EBS volume, and an oversized EC2 instance) plus the persistent
Cost Anomaly Monitor deployed via `scripts/deploy_cost_monitor.sh`
(`cloudformation/cost-anomaly-monitor.yaml`), which should be running at
least ~10 days before the demo so it has a real baseline to compare against.

## 1. Cost overview

> "Give me a cost breakdown for the `build-fast-spend-smart` project over the
> last 7 days, grouped by service."

## 2. Anomaly investigation

> "Are there any active cost anomalies for this account? Explain what's
> driving the largest one."

## 3. NAT Gateway cost driver

> "I have NAT Gateways in two Availability Zones for a single low-traffic
> demo workload. Is this over-provisioned, and what would consolidating to
> one NAT Gateway save per month?"

## 4. Unattached EBS volume

> "Find any EBS volumes that are unattached and estimate how much they're
> costing me. Recommend whether to delete or snapshot-and-delete them."

## 5. Oversized EC2 instance

> "Review EC2 instances tagged `Project=build-fast-spend-smart` for
> right-sizing opportunities based on CPU/memory utilization, and recommend
> a smaller instance type."

## 6. Wrap-up / optimization plan

> "Summarize all the cost optimization opportunities you found for this
> project and estimate the total monthly savings if I apply all of them."
