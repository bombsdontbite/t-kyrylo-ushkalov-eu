resource "kubernetes_manifest" "demo_workload_amd64" {
  count = var.enable_demo_workloads ? 1 : 0

  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "demo-amd64-spot"
      namespace = "default"
      labels    = { app = "demo-amd64-spot" }
    }
    spec = {
      replicas = 2
      selector = {
        matchLabels = { app = "demo-amd64-spot" }
      }
      template = {
        metadata = { labels = { app = "demo-amd64-spot" } }
        spec = {
          nodeSelector = {
            "kubernetes.io/arch"         = "amd64"
            "karpenter.sh/capacity-type" = "spot"
          }
          containers = [{
            name  = "web"
            image = "public.ecr.aws/docker/library/nginx:stable"
            ports = [{
              containerPort = 80
              name          = "http"
            }]
          }]
        }
      }
    }
  }
  lifecycle {
    precondition {
      condition = (
        !var.enable_demo_workloads ||
        (contains(keys(var.nodepools), "amd64-spot") &&
        contains(keys(var.nodepools), "amd64-ondemand"))
      )
      error_message = "Demo workloads require 'amd64-spot' and 'amd64-ondemand' node pools to be defined."
    }
  }

  depends_on = [kubectl_manifest.node_pool]

}

resource "kubernetes_manifest" "demo_workload_arm64" {
  count = var.enable_demo_workloads ? 1 : 0

  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "demo-arm64-ondemand"
      namespace = "default"
      labels    = { app = "demo-arm64-ondemand" }
    }
    spec = {
      replicas = 2
      selector = {
        matchLabels = { app = "demo-arm64-ondemand" }
      }
      template = {
        metadata = { labels = { app = "demo-arm64-ondemand" } }
        spec = {
          nodeSelector = {
            "kubernetes.io/arch"         = "arm64"
            "karpenter.sh/capacity-type" = "on-demand"
          }
          containers = [{
            name  = "web"
            image = "public.ecr.aws/docker/library/nginx:stable"
            ports = [{
              containerPort = 80
              name          = "http"
            }]
          }]
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition = (
        !var.enable_demo_workloads ||
        (contains(keys(var.nodepools), "arm64-spot") &&
        contains(keys(var.nodepools), "arm64-ondemand"))
      )
      error_message = "Demo workloads require 'arm64-spot' and 'arm64-ondemand' node pools to be defined."
    }
  }

  depends_on = [kubectl_manifest.node_pool]
}