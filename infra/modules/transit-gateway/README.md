# Transit Gateway module

A thin, opinionated wrapper over [`terraform-aws-modules/transit-gateway`](https://registry.terraform.io/modules/terraform-aws-modules/transit-gateway/aws/3.3.0)
(pinned `3.3.0`) that creates a regional Transit Gateway and attaches VPC subnets to it.

## Usage — regional TGW + VPC attachment

```hcl
module "tgw" {
  source = "../../modules/transit-gateway"

  name            = "clevertap-use1"
  amazon_side_asn = 12345                       # unique per region when peering

  vpc_attachments = {
    main = {
      vpc_id     = module.vpc.vpc_id
      subnet_ids = module.vpc.intra_subnet_ids  # one attachment subnet per AZ
    }
  }

  tags = { Environment = "prod", Region = "us-east-1" }
}
```

## Cross-region connectivity (root-level)

Connect two regional TGWs like so:

```hcl
# us-east-1 (requester) → ap-south-1 (accepter)
resource "aws_ec2_transit_gateway_peering_attachment" "use1_to_aps1" {
  provider                = aws.use1
  transit_gateway_id      = module.tgw_use1.transit_gateway_id
  peer_transit_gateway_id = module.tgw_aps1.transit_gateway_id
  peer_region             = "ap-south-1"
  peer_account_id         = data.aws_caller_identity.current.account_id
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "aps1" {
  provider                      = aws.aps1
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.use1_to_aps1.id
}
```

## Key inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | string | — | TGW name / prefix. |
| `amazon_side_asn` | number | `null` | Private ASN (null = AWS-assigned). Unique per region when peering. |
| `vpc_attachments` | any | `{}` | Map of `{ vpc_id, subnet_ids }` attachments. |
| `share_with_account_ids` | list(string) | `[]` | RAM-share to these accounts; empty = unshared. |
| `enable_auto_accept_shared_attachments` | bool | `false` | Auto-accept cross-account attachments. |
| `enable_default_route_table_association` | bool | `true` | Associate attachments with the default route table. |
| `enable_default_route_table_propagation` | bool | `true` | Propagate routes into the default route table. |

## Outputs

`transit_gateway_id`, `transit_gateway_arn`, `association_default_route_table_id`, `vpc_attachment_ids`.
