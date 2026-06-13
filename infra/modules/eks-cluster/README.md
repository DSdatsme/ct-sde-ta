# EKS cluster module

A thin, opinionated wrapper over [`terraform-aws-modules/eks`](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/21.23.0) that provisions a hardened, multi-AZ EKS cluster: private API endpoint, KMS-encrypted
secrets, access-entry auth, mixed On-Demand + Spot managed node groups, Terraform-managed add-ons, and
**native IRSA roles** for workload identity.


## Why a wrapper (build-vs-buy)

The upstream module handles the heavy lifting (control plane, node groups, add-ons, OIDC). We add a
**curated, secure-by-default interface**: private endpoint by default, KMS envelope encryption on,
access-entry auth (no `aws-auth` configmap), an opinionated On-Demand+Spot node-group default, and a
first-party **IRSA role factory** so workloads get scoped IAM without hand-writing trust policies.

## Usage

```hcl
module "eks" {
  source = "../../modules/eks-cluster"

  name               = "clevertap-prod-use1"
  kubernetes_version = "1.36"

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnet_ids # nodes
  control_plane_subnet_ids = module.vpc.intra_subnet_ids   # control-plane ENIs

  irsa_roles = {
    external_dns = {
      namespace       = "kube-system"
      service_account = "external-dns"
      policy_arns     = ["arn:aws:iam::aws:policy/AmazonRoute53FullAccess"]
    }
  }

  tags = { Environment = "prod", Team = "platform" }
}
```

## Key inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | string | — | Cluster name / prefix. |
| `kubernetes_version` | string | — | Control-plane version (e.g. `1.31`). |
| `vpc_id` | string | — | Target VPC. |
| `subnet_ids` | list(string) | — | Private subnets for nodes. |
| `control_plane_subnet_ids` | list(string) | — | Subnets for control-plane ENIs (intra tier). |
| `endpoint_public_access` | bool | `false` | Expose the API server publicly. |
| `authentication_mode` | string | `"API"` | `API` (access entries) or `API_AND_CONFIG_MAP`. |
| `eks_managed_node_groups` | any | OD + Spot | Managed node groups (see defaults). |
| `addons` | any | cni/coredns/kube-proxy/ebs-csi | Terraform-managed add-ons. |
| `irsa_roles` | map(object) | `{}` | namespace/SA → IAM role + policies. |
| `security_group_additional_rules` | any | `{}` | Extra rules to whitelist CIDRs/SGs on the **control-plane** SG (e.g. bastion → API on 443). |
| `node_security_group_additional_rules` | any | `{}` | Extra rules to whitelist CIDRs/SGs on the **node** SG (specify the ports). |
| `create_kms_key` | bool | `true` | KMS envelope encryption for secrets. |

## Outputs

`cluster_name`, `cluster_endpoint`, `cluster_certificate_authority_data`, `oidc_provider_arn`,
`node_security_group_id`, `irsa_role_arns` (map of logical name → role ARN).

## Testing

```bash
terraform -chdir=infra/modules/eks-cluster init -backend=false
terraform -chdir=infra/modules/eks-cluster test
```
