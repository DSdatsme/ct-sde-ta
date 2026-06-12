variable "name" {
  type        = string
  description = "Name prefix for the VPC and its resources (e.g. clevertap-prod-use1)."
}

variable "vpc_cidr" {
  type        = string
  description = "The VPC's primary CIDR block (e.g. 10.0.0.0/16). All subnet CIDRs must fall within it."
}

variable "az_subnets" {
  description = "Per-AZ subnet CIDRs. Map key = Availability Zone; each value gives that AZ's public/private/intra CIDR. Map order is irrelevant — keys are sorted deterministically, so the CIDR->AZ mapping is explicit and reorder-proof."
  type = map(object({
    public  = string
    private = string
    intra   = string
  }))

  validation {
    condition     = length(var.az_subnets) >= 2
    error_message = "Provide at least 2 Availability Zones for HA."
  }

  validation {
    condition = length(distinct(flatten([
      for az, s in var.az_subnets : [s.public, s.private, s.intra]
    ]))) == length(var.az_subnets) * 3
    error_message = "All subnet CIDRs across all AZs must be unique."
  }
}

### NAT ###
variable "enable_nat_gateway" {
  type        = bool
  default     = true
  description = "Provision NAT gateways for private-subnet egress."
}

variable "one_nat_gateway_per_az" {
  type        = bool
  default     = true
  description = "true = one NAT per AZ (HA, prod default). Ignored when single_nat_gateway = true."
}

variable "single_nat_gateway" {
  type        = bool
  default     = false
  description = "Collapse to a single NAT gateway (non-prod cost saving). Overrides one_nat_gateway_per_az."
}

### Flow logs ###
variable "flow_log_retention_days" {
  type        = number
  default     = 90
  description = "Days before flow-log objects expire from S3."
}

variable "flow_log_transition_ia_days" {
  type        = number
  default     = 30
  description = "Days before flow-log objects transition to STANDARD_IA."
}

variable "flow_log_transition_glacier_days" {
  type        = number
  default     = 60
  description = "Days before flow-log objects transition to GLACIER."
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "Optional KMS key for flow-log bucket SSE. null => SSE-S3 (AES256)."
}

variable "flow_log_bucket_force_destroy" {
  type        = bool
  default     = false
  description = "Allow deletion of a non-empty flow-log bucket (set true only in throwaway envs)."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to all resources."
}
