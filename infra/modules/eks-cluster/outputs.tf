output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded CA data for the cluster."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS control plane."
  value       = module.eks.cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN for IRSA."
  value       = module.eks.oidc_provider_arn
}

output "node_security_group_id" {
  description = "Security group ID attached to managed node groups."
  value       = module.eks.node_security_group_id
}


output "irsa_role_arns" {
  description = "Map of irsa_roles key -> created IAM role ARN."
  value       = { for k, r in aws_iam_role.irsa : k => r.arn }
}
