module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.name}-vpc"
  cidr = var.cidr

  azs = length(var.azs) > 0 ? var.azs : slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = length(var.private_subnets) > 0 ? var.private_subnets : [
    for index, az in(length(var.azs) > 0 ? var.azs : slice(data.aws_availability_zones.available.names, 0, 3)) : cidrsubnet(var.cidr, 4, index)
  ]
  public_subnets = length(var.public_subnets) > 0 ? var.public_subnets : [
    for index, az in(length(var.azs) > 0 ? var.azs : slice(data.aws_availability_zones.available.names, 0, 3)) : cidrsubnet(var.cidr, 8, index + 48)
  ]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "karpenter.sh/discovery"                    = "${var.name}-cluster"
    "kubernetes.io/cluster/${var.name}-cluster" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "karpenter.sh/discovery"                    = "${var.name}-cluster"
    "kubernetes.io/cluster/${var.name}-cluster" = "shared"
  }

  tags = var.tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = "${var.name}-cluster"
  kubernetes_version = var.kubernetes_version

  enable_cluster_creator_admin_permissions = true
  endpoint_public_access                   = true

  security_group_tags = {
    "karpenter.sh/discovery" = "${var.name}-cluster"
  }

  node_security_group_tags = {
    "karpenter.sh/discovery" = "${var.name}-cluster"
  }

  addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
    eks-pod-identity-agent = {
      most_recent    = true
      before_compute = true
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = aws_iam_role.ebs_csi.arn
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    karpenter = {
      ami_type       = "BOTTLEROCKET_x86_64"
      instance_types = ["t3.large"]

      min_size     = 1
      max_size     = 3
      desired_size = 2

      labels = {
        "karpenter.sh/controller" = "true"
      }
    }
  }

  tags = var.tags
}

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.0"

  cluster_name                    = module.eks.cluster_name
  namespace                       = "kube-system"
  service_account                 = "karpenter"
  create_pod_identity_association = var.create_pod_identity_association
  create_access_entry             = true

  tags = var.tags
}

resource "aws_iam_instance_profile" "karpenter" {
  name = "${module.eks.cluster_name}-karpenter-node-profile"
  role = module.karpenter.node_iam_role_name
  tags = var.tags
}

resource "aws_iam_policy" "karpenter_controller_spot" {
  name        = "${module.eks.cluster_name}-karpenter-controller-spot"
  description = "Allows Karpenter controller to manage EC2 Spot service-linked role."
  policy      = data.aws_iam_policy_document.karpenter_controller_spot.json
}

resource "aws_iam_role_policy_attachment" "karpenter_controller_spot" {
  role       = module.karpenter.iam_role_name
  policy_arn = aws_iam_policy.karpenter_controller_spot.arn
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

