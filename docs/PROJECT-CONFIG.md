# Project Configuration

This document is the single source of truth for the project.
All team members should follow and update it whenever project configurations change.

---

# Project Information

| Item | Value |
|------|-------|
| Project Name | Production DevOps Platform on AWS EKS |
| Cloud Provider | AWS |
| Infrastructure as Code | Terraform |
| Kubernetes Platform | Amazon EKS |
| Container Registry | Amazon ECR |
| CI/CD | GitHub Actions |
| Monitoring | Prometheus & Grafana |

---

# AWS Configuration

| Item | Value |
|------|-------|
| AWS Region | us-east-1 |
| VPC Name | my-eks-cluster-vpc |
| EKS Cluster Name | my-eks-cluster |
| ECR Repository Name | my-app |

---

# Kubernetes Configuration

| Item | Value |
|------|-------|
| Namespace | TBD |
| Helm Release Name | TBD |
| Application Name | TBD |
| Deployment Name | TBD |
| Service Name | TBD |
| Ingress Name | TBD |
| Service Type | ClusterIP |
| Ingress Controller | AWS Load Balancer Controller |

---

# Git Workflow

| Item | Value |
|------|-------|
| Default Branch | main |
| Branch Naming | feature/<name> |
| Merge Strategy | Pull Request |

### Commit Convention

Examples:

```text
feat: add github actions workflow
fix: update terraform configuration
docs: update project configuration
chore: initialize repository
```

---

# General Rules

- Never commit secrets or credentials.
- Keep this document updated whenever configurations change.
- Use feature branches for all development work.
- Open a Pull Request before merging into `main`.

---

# Change Log

| Date | Updated By | Description |
|------|------------|-------------|
| 2026-07-20 | Mahmoud | Initial project configuration |
| 2026-07-21 | Infrastructure Team | Updated AWS region, VPC, EKS cluster, and ECR configuration from Terraform |
