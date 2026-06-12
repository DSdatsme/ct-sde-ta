output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "VPC primary CIDR."
  value       = module.vpc.vpc_cidr_block
}

output "availability_zones" {
  description = "Availability Zones the VPC spans (sorted)."
  value       = local.availability_zones
}

output "private_subnet_ids" {
  description = "Private subnet IDs (workload node groups)."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs (internet-facing LBs)."
  value       = module.vpc.public_subnets
}

output "intra_subnet_ids" {
  description = "Intra (isolated) subnet IDs (databases + EKS control-plane ENIs)."
  value       = module.vpc.intra_subnets
}

output "public_subnet_cidrs" {
  description = "CIDR blocks of the public subnets (ordered by AZ)."
  value       = local.public_subnets
}

output "private_subnet_cidrs" {
  description = "CIDR blocks of the private subnets (ordered by AZ)."
  value       = local.private_subnets
}

output "intra_subnet_cidrs" {
  description = "CIDR blocks of the intra subnets (ordered by AZ)."
  value       = local.intra_subnets
}

output "flow_log_bucket_arn" {
  description = "ARN of the VPC flow-log S3 bucket."
  value       = aws_s3_bucket.flow_logs.arn
}
