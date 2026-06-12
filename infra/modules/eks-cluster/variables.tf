variable "name" {
  type        = string
  description = "Cluster name / resource name prefix."
}

variable "kubernetes_version" {
  type        = string
  default     = "1.35"
  description = "EKS Kubernetes control-plane version (e.g. 1.31)."
}

variable "vpc_id" {
  type        = string
  description = "VPC the cluster runs in."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for worker nodes / workloads."
}

variable "control_plane_subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the EKS control-plane ENIs (typically the intra/isolated tier)."
}

### API endpoint ###
variable "endpoint_private_access" {
  type        = bool
  default     = true
  description = "Enable the private API server endpoint."
}

variable "endpoint_public_access" {
  type        = bool
  default     = false
  description = "Expose the API server publicly. Default false (private-only)."
}

variable "endpoint_public_access_cidrs" {
  type        = list(string)
  default     = []
  description = "CIDRs allowed to reach the public endpoint (only useful when endpoint_public_access = true)."
}

### Authentication ###
variable "authentication_mode" {
  type        = string
  default     = "API"
  description = "Cluster auth mode. API = access entries only (no aws-auth configmap)."

  validation {
    condition     = contains(["API", "API_AND_CONFIG_MAP"], var.authentication_mode)
    error_message = "authentication_mode must be API or API_AND_CONFIG_MAP."
  }
}

variable "access_entries" {
  type        = any
  default     = {}
  description = "Map of access entries to add to the cluster. Refer: https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/21.23.0?utm_content=documentLink&utm_medium=Antigravity+IDE&utm_source=terraform-ls#input_access_entries"
}

variable "enable_cluster_creator_admin_permissions" {
  type        = bool
  default     = true
  description = "Grant the Terraform-applying principal cluster-admin via an access entry."
}

### Node groups ###
variable "eks_managed_node_groups" {
  type        = any
  description = "EKS managed node groups. Defaults to an on-demand baseline + a tainted spot pool (mixed instance types)."
  default = {
    on_demand = {
      capacity_type  = "ON_DEMAND"
      instance_types = ["m6i.large", "m6a.large", "m5.large"]
      min_size       = 2
      max_size       = 6
      desired_size   = 2
      labels         = { workload = "baseline" }
    }
    spot = {
      capacity_type  = "SPOT"
      instance_types = ["m6i.large", "m6a.large", "m5.large", "m5a.large"]
      min_size       = 0
      max_size       = 20
      desired_size   = 2
      labels         = { workload = "spot" }
      taints = {
        spot = { key = "spot", value = "true", effect = "NO_SCHEDULE" }
      }
    }
  }
}

### Addons ###
variable "addons" {
  type        = any
  description = "EKS addons managed by Terraform. vpc-cni installs before compute so pods get IPs on first boot."
  default = {
    coredns            = { most_recent = true }
    kube-proxy         = { most_recent = true }
    vpc-cni            = { most_recent = true, before_compute = true }
    aws-ebs-csi-driver = { most_recent = true }
  }
}

### Security groups (Ingress whitelisting) ###
variable "security_group_additional_rules" {
  type        = any
  default     = {}
  description = "Additional ingress rules for the EKS control-plane (cluster) security group. Whitelist extra CIDRs/SGs here (e.g. a bastion or on-prem range reaching the private API on 443). Each rule: { description, protocol, from_port, to_port, type, cidr_blocks }."
}

variable "node_security_group_additional_rules" {
  type        = any
  default     = {}
  description = "Additional ingress rules for the worker-node security group. Whitelist extra CIDRs/SGs to the nodes, specifying the ports they may reach."
}

### IRSA ###
variable "enable_irsa" {
  type        = bool
  default     = true
  description = "Create the IAM OIDC provider for IRSA workload identity."
}

variable "irsa_roles" {
  type = map(object({
    namespace       = string
    service_account = string
    policy_arns     = optional(list(string), [])
  }))
  default     = {}
  description = "IAM Roles for Service Accounts. Key = logical name; each binds one namespace/SA to the cluster OIDC provider and attaches the given managed-policy ARNs."
}

### Encryption ###
variable "create_kms_key" {
  type        = bool
  default     = true
  description = "Create a KMS key for envelope encryption of Kubernetes secrets."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to all resources."
}
