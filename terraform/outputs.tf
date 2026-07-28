###############################################################################
# Outputs
###############################################################################

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS cluster API server endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data for the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL used for IRSA"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (nodes/pods)"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (NAT Gateway / ALB)"
  value       = aws_subnet.public[*].id
}

output "node_group_role_arn" {
  description = "IAM role ARN used by worker nodes"
  value       = aws_iam_role.eks_node.arn
}

output "alb_controller_role_arn" {
  description = "IRSA IAM role ARN used by the AWS Load Balancer Controller"
  value       = aws_iam_role.alb_controller.arn
}

output "ecr_repository_url" {
  description = "URL of the ECR repository (use for docker push/pull)"
  value       = aws_ecr_repository.app.repository_url
}

output "configure_kubectl" {
  description = "Command to configure kubectl for this cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}

