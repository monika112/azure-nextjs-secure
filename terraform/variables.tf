variable "subscription_id" {
  description = "Azure subscription ID."
  type        = string
  default ="dd0500ca-c7d3-42c6-a391-9389ca0e2848"
}

variable "location" {
  description = "Azure region for regional resources. Confirm ACA Private Link support before changing."
  type        = string
  default     = "eastus2"
}

variable "project" {
  description = "Short lowercase project identifier."
  type        = string
  default     = "nextweb"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,15}$", var.project))
    error_message = "project must be 3-16 lowercase letters, numbers, or hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "prod"
}

variable "vnet_address_space" {
  type    = list(string)
  default = ["10.40.0.0/16"]
}

variable "container_apps_subnet_cidr" {
  description = "Dedicated ACA infrastructure subnet. /23 leaves room for Consumption profile growth."
  type        = string
  default     = "10.40.0.0/23"
}

variable "private_endpoints_subnet_cidr" {
  type    = string
  default = "10.40.2.0/27"
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "liveness_probe_path" {
  description = "Keep / for bootstrap; change to a shallow app health endpoint after implementing it."
  type        = string
  default     = "/"
}

variable "readiness_probe_path" {
  description = "Use a readiness endpoint that verifies only dependencies required to serve traffic."
  type        = string
  default     = "/"
}

variable "initial_image" {
  description = "Bootstrap image. CI/CD replaces it with an immutable ACR image digest/tag."
  type        = string
  default     = "mcr.microsoft.com/dotnet/samples:aspnetapp"
}

variable "min_replicas" {
  type    = number
  default = 2
}

variable "max_replicas" {
  type    = number
  default = 10
}

variable "tags" {
  type = map(string)
  default = {
    managed-by = "terraform"
    workload   = "nextjs"
  }
}
