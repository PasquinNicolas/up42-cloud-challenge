output "namespace" {
  description = "The namespace where the file server is deployed"
  value       = var.namespace
}

output "release_name" {
  description = "The name of the Helm release"
  value       = helm_release.file_server.name
}

output "release_status" {
  description = "Status of the release"
  value       = helm_release.file_server.status
}
