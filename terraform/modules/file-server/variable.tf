variable "namespace" {
  description = "The namespace to deploy the file server into"
  type        = string
}
variable "linkerd_enabled" {
  description = "Whether to enable Linkerd injection"
  type        = bool
  default     = true
}

variable "helm_chart_path" {
  description = "Path to the Helm chart"
  type        = string
}

variable "release_name" {
  description = "Name of the Helm release"
  type        = string
  default     = "file-server"
}

variable "values_file" {
  description = "Path to the values file"
  type        = string
}

variable "create_namespace" {
  description = "Whether to create the namespace"
  type        = bool
  default     = true
}

variable "max_history" {
  description = "Maximum number of release versions stored per release"
  type        = number
  default     = 5
}

variable "timeout_seconds" {
  description = "Time in seconds to wait for any individual kubernetes operation"
  type        = number
  default     = 300
}
