resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = "kube-system"
  create_namespace = false

  repository  = "oci://public.ecr.aws/karpenter"
  chart       = "karpenter"
  version     = "1.8.2"

  repository_username = data.aws_ecrpublic_authorization_token.karpenter.user_name
  repository_password = data.aws_ecrpublic_authorization_token.karpenter.password

  wait                       = true
  disable_openapi_validation = true

  values = [<<-EOF
serviceAccount:
  create: true
  name: karpenter
  annotations:
    eks.amazonaws.com/role-arn: ${data.terraform_remote_state.aws.outputs.karpenter_controller_role_arn}

logLevel: debug

controller:
  nodeSelector:
    karpenter.sh/controller: "true"
  env:
    - name: AWS_REGION
      value: ${data.terraform_remote_state.aws.outputs.aws_region}
    - name: AWS_DEFAULT_REGION
      value: ${data.terraform_remote_state.aws.outputs.aws_region}
    - name: KARPENTER_LOG_LEVEL
      value: debug

settings:
  clusterName: ${data.terraform_remote_state.aws.outputs.cluster_name}
  clusterEndpoint: ${data.aws_eks_cluster.this.endpoint}
  interruptionQueue: ${data.terraform_remote_state.aws.outputs.karpenter_queue_name}
  defaultInstanceProfile: ${data.terraform_remote_state.aws.outputs.karpenter_instance_profile_name}
  defaultLaunchTemplate:
    amiFamily: AL2023
  disableDryRun: true
  aws:
    nodePool:
      enabled: true
    nodeClass:
      enabled: true
EOF
  ]
}

resource "kubectl_manifest" "ec2_node_class" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata   = {
      name = "${data.terraform_remote_state.aws.outputs.cluster_name}-ec2-nodeclass"
    }
    spec = {
      amiFamily      = "AL2023"
      instanceProfile = data.terraform_remote_state.aws.outputs.karpenter_instance_profile_name
      amiSelectorTerms = [
        {
          ssmParameter = "/aws/service/eks/optimized-ami/${data.terraform_remote_state.aws.outputs.kubernetes_version}/amazon-linux-2023/x86_64/standard/recommended/image_id"
        },
        {
          ssmParameter = "/aws/service/eks/optimized-ami/${data.terraform_remote_state.aws.outputs.kubernetes_version}/amazon-linux-2023/arm64/standard/recommended/image_id"
        }
      ]
      subnetSelectorTerms = [
        {
          tags = { "karpenter.sh/discovery" = data.terraform_remote_state.aws.outputs.cluster_name }
        }
      ]
      securityGroupSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = data.terraform_remote_state.aws.outputs.cluster_name
          }
        }
      ]
      tags = {
        "karpenter.sh/discovery" = data.terraform_remote_state.aws.outputs.cluster_name
      }
    }
  })

  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "node_pool" {
  for_each = var.nodepools

  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata   = { name = each.key }
    spec = {
      template = {
        metadata = {
          labels = {
            "kubernetes.io/arch"         = each.value.arch
            "karpenter.sh/capacity-type" = each.value.capacity_type
          }
        }
        spec = merge({
          requirements = [
            { key = "kubernetes.io/arch", operator = "In", values = [each.value.arch] },
            { key = "karpenter.sh/capacity-type", operator = "In", values = [each.value.capacity_type] },
        {
          key      = "node.kubernetes.io/instance-type"
          operator = "In"
          values   = each.value.instance_types
        }
          ]
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "${data.terraform_remote_state.aws.outputs.cluster_name}-ec2-nodeclass"
          }
        }, lookup(each.value, "expire_after", null) != null ? {
          expireAfter = each.value.expire_after
        } : {})
      }
      disruption = {
        consolidationPolicy = lookup(each.value, "consolidation", "WhenEmptyOrUnderutilized")
        consolidateAfter    = lookup(each.value, "consolidate_after", "5m")
      }
      limits = {
        cpu = lookup(each.value, "cpu_limit", "256")
      }
    }
  })

  depends_on = [kubectl_manifest.ec2_node_class]
}
