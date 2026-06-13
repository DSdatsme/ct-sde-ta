# VPC module

A thin, opinionated wrapper over [`terraform-aws-modules/vpc`](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/6.6.1) that provisions one region's network for the CleverTap platform: public / private / intra subnet tiers, NAT with a cost toggle, and **VPC Flow Logs shipped to a dedicated, encrypted, lifecycle-tiered S3 bucket**.

## Why a wrapper (build-vs-buy)

We don't reinvent the VPC primitives as the upstream module is battle-tested. This module adds value via a **curated, narrowed interface and secure-by-default behavior**: flow logs forced to S3 (not CloudWatch) with a tiered lifecycle, a locked-down log bucket, EKS subnet-discovery tags, and a cross-variable guardrail on subnet sizing. We own the interface and the defaults; upstream owns the plumbing.

## Usage

```hcl
module "vpc" {
  source = "../../modules/vpc"

  name     = "clevertap-prod-use1"
  vpc_cidr = "10.0.0.0/16"

  # Each AZ maps explicitly to its three CIDRs. Heterogeneous sizing:
  # private large (pod IPs), public/intra small. Map order is irrelevant.
  az_subnets = {
    "us-east-1a" = { public = "10.0.0.0/24", private = "10.0.16.0/20", intra = "10.0.8.0/24" }
    "us-east-1b" = { public = "10.0.1.0/24", private = "10.0.32.0/20", intra = "10.0.9.0/24" }
    "us-east-1c" = { public = "10.0.2.0/24", private = "10.0.48.0/20", intra = "10.0.10.0/24" }
  }

  tags = { Environment = "prod", Team = "platform" }
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | string | — | Name prefix for the VPC and its resources. |
| `vpc_cidr` | string | — | VPC primary CIDR; all subnets must fall within it. |
| `az_subnets` | map(object({public,private,intra})) | — | Per-AZ CIDRs (≥ 2 AZs). Key = AZ; each entry holds that AZ's public/private/intra CIDR. All CIDRs must be unique. Size private generously for pod IPs. |
| `enable_nat_gateway` | bool | `true` | Provision NAT for private egress. |
| `one_nat_gateway_per_az` | bool | `true` | One NAT per AZ (HA). Ignored if `single_nat_gateway`. |
| `single_nat_gateway` | bool | `false` | Single shared NAT (cost saving, non-prod). |
| `flow_log_retention_days` | number | `90` | Flow-log S3 object expiry. |
| `flow_log_transition_ia_days` | number | `30` | Days → STANDARD_IA. |
| `flow_log_transition_glacier_days` | number | `60` | Days → GLACIER. |
| `kms_key_arn` | string | `null` | KMS key for bucket SSE (null ⇒ SSE-S3). |
| `flow_log_bucket_force_destroy` | bool | `false` | Allow deleting a non-empty bucket. |
| `tags` | map(string) | `{}` | Tags applied to all resources. |

## Outputs

| Name | Description |
|---|---|
| `vpc_id` | VPC ID. |
| `vpc_cidr_block` | VPC primary CIDR. |
| `availability_zones` | AZs the VPC spans (sorted). |
| `private_subnet_ids` | Private subnet IDs (workload nodes). |
| `public_subnet_ids` | Public subnet IDs (internet-facing LBs). |
| `intra_subnet_ids` | Intra subnet IDs (DBs + control plane). |
| `public_subnet_cidrs` / `private_subnet_cidrs` / `intra_subnet_cidrs` | Derived CIDRs per tier (ordered by AZ). |
| `flow_log_bucket_arn` | ARN of the flow-log S3 bucket. |

## Testing

```bash
terraform -chdir=infra/modules/vpc init -backend=false
terraform -chdir=infra/modules/vpc test
```
