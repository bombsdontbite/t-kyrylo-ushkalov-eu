# Common
variable "name" {
  description = "Name prefix for resource names"
  type        = string
}

variable "aws_region" {
  description = "AWS region to deploy to"
  type        = string
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}

# Network
variable "cidr" {
  description = "CIDR for the new VPC"
  type        = string
}

variable "azs" {
  description = "Optional list of AZs to use (defaults to first three available)"
  type        = list(string)
  default     = []
}

variable "private_subnets" {
  description = "Optional explicit private subnet CIDRs"
  type        = list(string)
  default     = []
}

variable "public_subnets" {
  description = "Optional explicit public subnet CIDRs"
  type        = list(string)
  default     = []
}

# EKS
variable "kubernetes_version" {
  description = "Desired Kubernetes version for EKS (e.g., 1.30)."
  type        = string
  default     = null
}

# Karpenter
variable "create_pod_identity_association" {
  description = "Whether to create the Pod Identity association for the Karpenter controller"
  type        = bool
  default     = true
}


