###############################################################################
# Provider Requirements & Configuration
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }

    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.3"
    }
  }
}

###############################################################################
# AWS Provider
###############################################################################

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      var.tags,
      {
        Project = var.cluster_name
      }
    )
  }
}

###############################################################################
# EKS Authentication
###############################################################################

data "aws_eks_cluster_auth" "this" {
  name = aws_eks_cluster.main.name
}

###############################################################################
# Kubernetes Provider
###############################################################################

provider "kubernetes" {
  host = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(
    aws_eks_cluster.main.certificate_authority[0].data
  )
  token = data.aws_eks_cluster_auth.this.token
}

###############################################################################
# Helm Provider
###############################################################################

provider "helm" {
  kubernetes {
    host = aws_eks_cluster.main.endpoint

    cluster_ca_certificate = base64decode(
      aws_eks_cluster.main.certificate_authority[0].data
    )

    token = data.aws_eks_cluster_auth.this.token
  }
}
