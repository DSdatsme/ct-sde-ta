output "transit_gateway_id" {
  description = "Transit Gateway ID. Pass to the peer region to establish cross-region peering."
  value       = module.tgw.ec2_transit_gateway_id
}

output "transit_gateway_arn" {
  description = "Transit Gateway ARN."
  value       = module.tgw.ec2_transit_gateway_arn
}

output "association_default_route_table_id" {
  description = "Default route table the attachments associate with."
  value       = module.tgw.ec2_transit_gateway_association_default_route_table_id
}

output "vpc_attachment_ids" {
  description = "Map of logical name -> VPC attachment ID."
  value       = module.tgw.ec2_transit_gateway_vpc_attachment_ids
}
