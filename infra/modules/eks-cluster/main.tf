module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.23.0"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  # Networking
  vpc_id                   = var.vpc_id
  subnet_ids               = var.subnet_ids
  control_plane_subnet_ids = var.control_plane_subnet_ids

  endpoint_private_access      = var.endpoint_private_access
  endpoint_public_access       = var.endpoint_public_access
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  # Authentication
  authentication_mode                      = var.authentication_mode
  access_entries                           = var.access_entries
  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions

  # Encryption
  create_kms_key    = var.create_kms_key
  encryption_config = { resources = ["secrets"] }

  enable_irsa = var.enable_irsa

  # Node Groups
  eks_managed_node_groups = var.eks_managed_node_groups
  addons                  = var.addons

  # Ingress whitelisting on the control-plane / node security groups.
  security_group_additional_rules      = var.security_group_additional_rules
  node_security_group_additional_rules = var.node_security_group_additional_rules

  tags = var.tags
}
