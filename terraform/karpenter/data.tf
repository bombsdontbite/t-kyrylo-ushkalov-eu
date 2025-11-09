data "terraform_remote_state" "aws" {
  backend = "local"

  config = {
    path = "${path.module}/../infra/terraform.tfstate"
  }
}

data "aws_eks_cluster" "this" {
  name = data.terraform_remote_state.aws.outputs.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = data.terraform_remote_state.aws.outputs.cluster_name
}

data "aws_ecrpublic_authorization_token" "karpenter" {
  region = data.terraform_remote_state.aws.outputs.aws_region
}
