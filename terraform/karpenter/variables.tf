variable "nodepools" {
  description = "Map of node pool definitions keyed by pool name"
  type = map(object({
    arch              = string
    capacity_type     = string
    instance_types    = list(string)
    cpu_limit         = optional(string, "256")
    consolidation     = optional(string, "WhenEmptyOrUnderutilized")
    consolidate_after = optional(string, "5m")
    expire_after      = optional(string, "720h")
  }))
  default = {}
}

variable "enable_demo_workloads" {
  description = "Set to true to deploy sample amd64 and arm64 demo workloads for validating Karpenter provisioning"
  type        = bool
  default     = false
}

