# data.tf
data "kubernetes_secret" "gitlab_token" {
  metadata {
    name      = "gitlab-token"
    namespace = "file-server"
  }
}
