data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_iam_policy_document" "ebs_csi_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = format("%s:sub", replace(module.eks.cluster_oidc_issuer_url, "https://", ""))
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = format("%s:aud", replace(module.eks.cluster_oidc_issuer_url, "https://", ""))
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "karpenter_controller_spot" {
  statement {
    sid     = "AllowSpotServiceLinkedRole"
    actions = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["spot.amazonaws.com"]
    }
  }

  statement {
    sid = "AllowRoleRead"
    actions = [
      "iam:GetRole",
      "iam:ListRoles"
    ]
    resources = ["*"]
  }
}


