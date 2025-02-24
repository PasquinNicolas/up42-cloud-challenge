# Terraform Deployment Process

This document details the steps to deploy the UP42 File Server using Terraform with GitLab as the state backend.

## Prerequisites

- Kubernetes cluster running
- Terraform installed (or using OpenTofu as equivalent)
- kubectl configured to access the cluster
- GitLab access token with API scope
- All supporting infrastructure (Linkerd, Vault, External Secrets, etc.) installed

## Deployment Process

### 1. Set Environment Variables

Set the GitLab access token and state name for the backend:

```bash
export TF_STATE_NAME=live-up42-s3www-production
export GITLAB_ACCESS_TOKEN=your_gitlab_access_token
```

### 2. Initialize Terraform with GitLab Backend

Navigate to the appropriate environment directory (local or production):

```bash
cd terraform/environments/production
```

Initialize Terraform with the GitLab backend configuration:

```bash
terraform init \
    -backend-config="address=https://gitlab.example.com/api/v4/projects/14/terraform/state/$TF_STATE_NAME" \
    -backend-config="lock_address=https://gitlab.example.com/api/v4/projects/14/terraform/state/$TF_STATE_NAME/lock" \
    -backend-config="unlock_address=https://gitlab.example.com/api/v4/projects/14/terraform/state/$TF_STATE_NAME/lock" \
    -backend-config="username=username" \
    -backend-config="password=$GITLAB_ACCESS_TOKEN" \
    -backend-config="lock_method=POST" \
    -backend-config="unlock_method=DELETE" \
    -backend-config="retry_wait_min=5"
```

For subsequent initializations or changes to backend configuration:

```bash
terraform init --reconfigure
```

# Terraform Deployment Process

### 3. Create Terraform Plan

Generate an execution plan:

```bash
terraform plan
```

Review the plan to ensure it will create the expected resources.

### 4. Apply Terraform Configuration

Apply the Terraform configuration to create the resources:

```bash
terraform apply
```

For automated deployments, you can use:

```bash
terraform apply --auto-approve
```

### 5. Verify Deployment

Check if the Kubernetes resources have been created:

```bash
kubectl get pods -n file-server
kubectl get svc -n file-server
```

### 6. Manage Terraform State

The state is stored in GitLab, but you can still interact with it:

To list resources in the current state:
```bash
terraform state list
```

To show details of a specific resource:
```bash
terraform state show 'module.file_server.helm_release.file_server'
```

### 7. Destroy Infrastructure

When you need to tear down the infrastructure:

```bash
terraform destroy
```

## Directory Structure and Configuration Files

### Understanding the Directory Structure

The Terraform configuration is organized as follows:

- `terraform/`
  - `environments/`
    - `local/` - Configuration for local development
    - `production/` - Configuration for production environment
  - `modules/`
    - `file-server/` - Reusable module for the file server

### Key Configuration Files

#### environments/production/main.tf

```hcl
module "file_server" {
  source = "../../modules/file-server"

  namespace        = var.namespace
  helm_chart_path  = var.helm_chart_path
  values_file      = var.values_file
  create_namespace = true
}
```

#### environments/production/providers.tf

```hcl
terraform {
  required_version = ">= 1.0.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0.0"
    }
    gitlab = {
      source  = "gitlabhq/gitlab"
      version = "17.8.0"
    }
  }
  backend "http" {}
}

provider "kubernetes" {
  # Kubernetes provider configuration for production
}

provider "gitlab" {
  token    = var.admin_token
  base_url = "https://gitlab.example.com"
}

provider "helm" {
  kubernetes {
    # Kubernetes configuration for Helm provider
  }
}
```

#### environments/production/variables.tf

```hcl
variable "admin_token" {
  description = "Owner PAT token with the api scope applied."
  type        = string
  sensitive   = true
}

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
```

#### environments/production/terraform.tfvars

```hcl
namespace       = "file-server"
helm_chart_path = "../../../charts/up42-file-server"
values_file     = "../../../charts/up42-file-server/values.yaml"
```

#### modules/file-server/main.tf

```hcl
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
          server  = "http://vault.vault:8200"
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
  set {
    name  = "linkerd.enabled"
    value = "true"
  }
  values = [
    file(var.values_file)
  ]

  depends_on = [
    kubernetes_namespace.this,
    kubernetes_manifest.external_secret
  ]
}
```

#### modules/file-server/variables.tf

```hcl
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
```

## Troubleshooting

### Common Issues

1. **GitLab Authentication Errors**:
   - Check that your GitLab token has the correct permissions and hasn't expired
   - Verify the GitLab base URL is correct

2. **Terraform State Lock Issues**:
   - If the state is locked, use `terraform force-unlock <LOCK_ID>`

3. **Resource Creation Failures**:
   - Check Kubernetes pod logs: `kubectl logs -n file-server <pod_name>`
   - Check events: `kubectl get events -n file-server`

4. **Helm Chart Application Failures**:
   - Check Helm release status: `helm status file-server -n file-server`

### Debugging Tips

1. Use the `-trace` flag for detailed terraform logging:
   ```bash
   terraform apply -trace
   ```

2. Enable Terraform debug logging:
   ```bash
   export TF_LOG=DEBUG
   export TF_LOG_PATH=./terraform.log
   ```

3. Validate your Terraform files:
   ```bash
   terraform validate
   ```
