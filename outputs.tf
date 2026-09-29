output "environment" {
  value = var.environment
}

output "cluster_api_url" {
  value = local.cluster_api_url
}

output "topic" {
  value = redpanda_topic.orders.name
}

output "user" {
  value = redpanda_user.orders_app.name
}

output "role" {
  value = redpanda_role.orders_producer.name
}
