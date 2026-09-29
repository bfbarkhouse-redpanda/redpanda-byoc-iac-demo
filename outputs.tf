output "environment" {
  value = var.environment
}

output "cluster_api_url" {
  value = local.cluster_api_url
}

output "topic" {
  value = redpanda_topic.demo.name
}

output "user" {
  value = redpanda_user.demo.name
}

output "role" {
  value = redpanda_role.demo.name
}
