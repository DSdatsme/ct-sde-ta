# DevOps Engineer Usecase

Written answers for all four sections are in [docs/SOLUTION.md](./docs/SOLUTION.md). This README is just a map.

## The use case

Company XYZ runs a multi-tenant SaaS processing 40B+ events/day across 4B+ devices, where customer campaigns trigger sudden 10–50x traffic spikes. 
The task is to take over and modernize inherited infrastructure, which includes:

- non-standardized multi-region EKS
- partial IaC (40% click-ops)
- noisy alerting
- a $420K/mo bill

Four sections:

- **1 — Infrastructure & IaC:** reusable, hardened Terraform modules (VPC, EKS, Transit Gateway), Terraform state & drift strategy, and an EU data-residency design.
- **2 — Reliability & Observability:** a unified four-pillar stack, SLO burn-rate alerting, an incident runbook, and a plan to cut alert noise.
- **3 — Developer Platform & CI/CD:** a GitOps PR → staging → prod pipeline (canary + runtime secrets) and a self-serve IDP design.
- **4 — Cost Engineering:** a 90-day plan to cut the bill 25–30% without SLA impact, plus a FinOps ownership model.

## Layout

| Path | What |
|---|---|
| [docs/SOLUTION.md](./docs/SOLUTION.md) | The written document — Sections 1–4 |
| [infra/modules/vpc/](./infra/modules/vpc/) | Multi-region VPC module (public/private/intra, flow logs → S3) — §1a |
| [infra/modules/eks-cluster/](./infra/modules/eks-cluster/) | EKS module (private endpoint, IRSA, On-Demand+Spot, add-ons) — §1a |
| [infra/modules/transit-gateway/](./infra/modules/transit-gateway/) | Transit Gateway module (inter-region) — §1a |
| [infra/live/prod/](./infra/live/prod/) | Same VPC module instantiated across `us-east-1` + `ap-south-1` |
| [.github/workflows/](./.github/workflows/) | PR + staging pipelines (GitOps via Argo CD) — §3a |
| [docs/runbooks/](./docs/runbooks/) | `KubePodCrashLooping` runbook — §2b |

## Validate a module

```bash
cd infra/modules/vpc
terraform init -backend=false
terraform validate
terraform test          # vpc + eks-cluster have native terraform tests
```

Terraform `>= 1.9`, AWS provider pinned `6.50.0`; community modules and GitHub Actions pinned to exact versions.
