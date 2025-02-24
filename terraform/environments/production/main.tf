module "file_server" {
  source = "../../modules/file-server"

  namespace        = var.namespace
  helm_chart_path  = var.helm_chart_path
  values_file      = var.values_file
  create_namespace = true
}
