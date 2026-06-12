locals {
  availability_zones = keys(var.az_subnets)
  public_subnets     = [for az in local.availability_zones : var.az_subnets[az].public]
  private_subnets    = [for az in local.availability_zones : var.az_subnets[az].private]
  intra_subnets      = [for az in local.availability_zones : var.az_subnets[az].intra]
}
