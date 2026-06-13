variable "name" {
  type        = string
  description = "Transit Gateway name."
}

variable "description" {
  type        = string
  default     = "Regional hub Transit Gateway"
  description = "Description on the Transit Gateway."
}

variable "amazon_side_asn" {
  type        = number
  default     = null
  description = "Private ASN for the Amazon side of the TGW. Null lets AWS assign. Must be unique per TGW when peering regions."
}

### Routing ###
variable "enable_default_route_table_association" {
  type        = bool
  default     = true
  description = "Associate attachments with the default TGW route table"
}

variable "enable_default_route_table_propagation" {
  type        = bool
  default     = true
  description = "Propagate attachment routes into the default TGW route table."
}

### VPC attachments ###
variable "vpc_attachments" {
  type        = any
  default     = {}
  description = "Map of VPC attachments. Key = logical name; each value is at least: { vpc_id = string, subnet_ids = list(string) }. Attach the VPC's private (or intra) subnets one per AZ"
}

### Cross-account sharing (RAM) ###
variable "share_with_account_ids" {
  type        = list(string)
  default     = []
  description = "Account IDs to share the TGW with via RAM. Empty = not shared (default). Sharing is only enabled when this is non-empty."
}

variable "enable_auto_accept_shared_attachments" {
  type        = bool
  default     = false
  description = "Auto-accept cross-account attachments. Off by default — attachments should be reviewed."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to all resources."
}
