mock_provider "aws" {}

variables {
  name     = "test"
  vpc_cidr = "10.0.0.0/16"

  az_subnets = {
    "us-east-1a" = { public = "10.0.0.0/24", private = "10.0.16.0/20", intra = "10.0.8.0/24" }
    "us-east-1b" = { public = "10.0.1.0/24", private = "10.0.32.0/20", intra = "10.0.9.0/24" }
    "us-east-1c" = { public = "10.0.2.0/24", private = "10.0.48.0/20", intra = "10.0.10.0/24" }
  }
}

run "subnets_derive_one_per_az" {
  command = plan

  assert {
    condition     = length(output.private_subnet_cidrs) == length(var.az_subnets)
    error_message = "Each AZ should contribute exactly one subnet per tier."
  }
  assert {
    condition     = output.availability_zones == sort(keys(var.az_subnets))
    error_message = "Derived AZ order must be the sorted map keys (deterministic, reorder-proof)."
  }
}

# Duplicate CIDRs across AZs must be rejected at plan time.
run "rejects_duplicate_subnet_cidrs" {
  command = plan

  variables {
    az_subnets = {
      "us-east-1a" = { public = "10.0.0.0/24", private = "10.0.16.0/20", intra = "10.0.8.0/24" }
      "us-east-1b" = { public = "10.0.0.0/24", private = "10.0.32.0/20", intra = "10.0.9.0/24" } # dup public
    }
  }

  expect_failures = [var.az_subnets]
}


run "flow_logs_tier_to_ia_then_glacier_then_expire" {
  command = plan

  assert {
    condition     = anytrue([for t in aws_s3_bucket_lifecycle_configuration.flow_logs.rule[0].transition : t.storage_class == "STANDARD_IA"])
    error_message = "Flow-log bucket must transition objects to STANDARD_IA."
  }
  assert {
    condition     = anytrue([for t in aws_s3_bucket_lifecycle_configuration.flow_logs.rule[0].transition : t.storage_class == "GLACIER"])
    error_message = "Flow-log bucket must transition objects to GLACIER."
  }
  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.flow_logs.rule[0].expiration[0].days == var.flow_log_retention_days
    error_message = "Flow-log bucket must expire objects per the retention variable."
  }
}
