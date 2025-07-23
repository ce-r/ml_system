terraform {
  required_version = ">= 1.0"
  
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "minikube"
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "minikube"
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}

# Create namespaces
resource "kubernetes_namespace" "ml_platform" {
  metadata {
    name = "ml-platform"
  }
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

# resource "kubernetes_namespace" "ingress" {
#   metadata {
#     name = "ingress-nginx"
#   }
# }

# Modify the resource to use data source and use existing ingress-nginx namespace created by minikube
data "kubernetes_namespace" "ingress" {
  metadata {
    name = "ingress-nginx"
  }
}

# Local storage class
resource "kubernetes_storage_class" "local_storage" {
  metadata {
    name = "local-storage"
  }
  storage_provisioner = "kubernetes.io/no-provisioner"
  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"
}

# Docker volumes for persistent storage
resource "docker_volume" "ml_data" {
  name = "ml-platform-data"
}

resource "docker_volume" "ml_models" {
  name = "ml-platform-models"
}

output "namespace" {
  value = kubernetes_namespace.ml_platform.metadata[0].name
}
