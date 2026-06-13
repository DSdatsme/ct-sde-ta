module "tgw" {
  source  = "terraform-aws-modules/transit-gateway/aws"
  version = "3.3.0"

  name            = var.name
  description     = var.description
  amazon_side_asn = var.amazon_side_asn == null ? null : tostring(var.amazon_side_asn)

  # Simple hub-and-spoke: attachments auto-associate and propagate into the default route table.
  enable_default_route_table_association = var.enable_default_route_table_association
  enable_default_route_table_propagation = var.enable_default_route_table_propagation

  # Attachments are reviewed, not auto-accepted, unless explicitly opted in.
  enable_auto_accept_shared_attachments = var.enable_auto_accept_shared_attachments

  # All the VPCs are listed here
  vpc_attachments = var.vpc_attachments

  share_tgw                     = local.share_tgw
  ram_allow_external_principals = false   # security review
  ram_principals                = var.share_with_account_ids

  tags = var.tags
}
