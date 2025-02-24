variable "namespace" {
  description = "The namespace to deploy the file server into"
  type        = string
  default     = "file-server"
}

variable "helm_chart_path" {
  description = "Path to the Helm chart"
  type        = string
}

variable "values_file" {
  description = "Path to the values file"
  type        = string
}
