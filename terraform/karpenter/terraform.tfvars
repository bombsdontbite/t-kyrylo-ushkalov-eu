nodepools = {
  "amd64-spot" = {
    arch          = "amd64"
    capacity_type = "spot"
    instance_types = [
      "t3a.small",
      "t3.small",
      "t3a.medium"
    ]
    cpu_limit = "128"
  }

  "amd64-ondemand" = {
    arch          = "amd64"
    capacity_type = "on-demand"
    instance_types = [
      "t3a.small",
      "t3.small"
    ]
    cpu_limit = "64"
  }

  "arm64-spot" = {
    arch          = "arm64"
    capacity_type = "spot"
    instance_types = [
      "t4g.small",
      "t4g.medium"
    ]
    cpu_limit = "128"
  }

  "arm64-ondemand" = {
    arch          = "arm64"
    capacity_type = "on-demand"
    instance_types = [
      "t4g.small"
    ]
    cpu_limit = "64"
  }
}

enable_demo_workloads = true


