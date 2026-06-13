
module "vpc" {
  source = "../../../../modules/vpc"

  name       = var.name
  vpc_cidr   = var.vpc_cidr
  az_subnets = var.az_subnets

  tags = {
    environment = "prod"
    team        = "platform"
    purpose     = "demo"
    project     = "assignment"

  }
}
