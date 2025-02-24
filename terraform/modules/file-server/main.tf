terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0.0"
    }
  }
}

resource "kubernetes_namespace" "this" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}
resource "null_resource" "namespace_linkerd_injection" {
  count = var.linkerd_enabled ? 1 : 0

  provisioner "local-exec" {
    command = "kubectl label namespace ${var.namespace} linkerd.io/inject=enabled --overwrite"
  }

  depends_on = [
    kubernetes_namespace.this
  ]
}

# Create ServiceAccount for External Secrets
resource "kubernetes_service_account_v1" "file_server" {
  metadata {
    name      = "file-server"
    namespace = var.namespace
  }

  depends_on = [
    kubernetes_namespace.this
  ]
}

# Create SecretStore
resource "kubernetes_manifest" "secret_store" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "SecretStore"
    metadata = {
      name      = "vault-backend"
      namespace = var.namespace
    }
    spec = {
      provider = {
        vault = {
          server  = "http://vault.default:8200"
          path    = "secret"
          version = "v2"
          auth = {
            kubernetes = {
              mountPath = "kubernetes"
              role      = "file-server"
              serviceAccountRef = {
                name = "file-server"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_service_account_v1.file_server
  ]
}

# Create ExternalSecret
resource "kubernetes_manifest" "external_secret" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "minio-credentials"
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "15m"
      secretStoreRef = {
        name = "vault-backend"
        kind = "SecretStore"
      }
      target = {
        name           = "file-server-minio-secret"
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "access-key"
          remoteRef = {
            key      = "file-server/minio"
            property = "access_key"
          }
        },
        {
          secretKey = "secret-key"
          remoteRef = {
            key      = "file-server/minio"
            property = "secret_key"
          }
        }
      ]
    }
  }

  depends_on = [
    kubernetes_manifest.secret_store
  ]
}

resource "helm_release" "file_server" {
  name        = var.release_name
  chart       = var.helm_chart_path
  namespace   = var.namespace
  max_history = var.max_history
  timeout     = var.timeout_seconds

  cleanup_on_fail = true
  force_update    = true
  replace         = true
  recreate_pods   = true

  set {
    name  = "linkerd.enabled"
    value = "true"
  }

  values = [
    file(var.values_file)
  ]

  depends_on = [
    kubernetes_namespace.this,
    kubernetes_service_account_v1.file_server,
    kubernetes_manifest.secret_store,
    kubernetes_manifest.external_secret
  ]
}
