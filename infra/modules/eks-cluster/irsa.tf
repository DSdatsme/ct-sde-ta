# IRSA: one IAM role per requested service account, trusting the cluster's OIDC

data "aws_iam_policy_document" "irsa_assume" {
  for_each = var.irsa_roles

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:${each.value.namespace}:${each.value.service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "irsa" {
  for_each = var.irsa_roles

  name               = "${var.name}-irsa-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume[each.key].json
  tags               = var.tags
}

# Flatten {role_key => {..., policy_arns=[...]}} into role<->policy pairs.
locals {
  irsa_policy_attachments = merge([
    for role_key, role in var.irsa_roles : {
      for policy_arn in role.policy_arns :
      "${role_key}::${policy_arn}" => { role_key = role_key, policy_arn = policy_arn }
    }
  ]...)
}

resource "aws_iam_role_policy_attachment" "irsa" {
  for_each = local.irsa_policy_attachments

  role       = aws_iam_role.irsa[each.value.role_key].name
  policy_arn = each.value.policy_arn
}
