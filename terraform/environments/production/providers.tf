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
  # In production, you would typically use S3/DynamoDB or Terraform Cloud
  # Lets use Gitlab Instance to manage the statefile
  backend "http" {}
}

provider "kubernetes" {
  config_path = "~/.kube/config"
  #config_context = "minikube"
  config_context = "microk8s"
}

provider "gitlab" {
  token    = data.kubernetes_secrets.gitlab_token.data.token
  base_url = "https://gitlab.nickpasquin.com"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
    #config_context = "minikube"
    config_context = "microk8s"
  }
}
