mock_provider "aws" {
  # IAM policy-document data sources must mock to valid JSON, else assume_role_policy
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
  # Real-looking partition/account so the module's ARN construction validates.
  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:role/terraform"
    }
  }
  # The module resolves the caller's session context from its ARN.
  mock_data "aws_iam_session_context" {
    defaults = {
      issuer_arn = "arn:aws:iam::123456789012:role/terraform"
    }
  }
}

variables {
  name                     = "test"
  kubernetes_version       = "1.31"
  vpc_id                   = "vpc-12345678"
  subnet_ids               = ["subnet-1a", "subnet-1b", "subnet-1c"]
  control_plane_subnet_ids = ["subnet-ca", "subnet-cb", "subnet-cc"]
}

run "private_endpoint_and_api_auth_by_default" {
  command = plan

  assert {
    condition     = var.endpoint_public_access == false
    error_message = "API server endpoint must be private by default."
  }
  assert {
    condition     = var.authentication_mode == "API"
    error_message = "Cluster must default to API authentication mode (access entries, no aws-auth configmap)."
  }
}

run "default_node_groups_mix_on_demand_and_spot" {
  command = plan

  assert {
    condition     = var.eks_managed_node_groups["on_demand"].capacity_type == "ON_DEMAND"
    error_message = "Expected an on-demand baseline node group."
  }
  assert {
    condition     = var.eks_managed_node_groups["spot"].capacity_type == "SPOT"
    error_message = "Expected a spot node group for cost efficiency."
  }
}
