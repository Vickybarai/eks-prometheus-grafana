output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.eks.name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = aws_eks_cluster.eks.endpoint
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.eks.arn
}

output "cluster_status" {
  description = "EKS cluster status"
  value       = aws_eks_cluster.eks.status
}

output "node_group_status" {
  description = "Node group status"
  value       = aws_eks_node_group.node_group.status
}