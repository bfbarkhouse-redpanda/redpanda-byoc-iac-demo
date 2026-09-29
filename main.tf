# Look up the existing BYOC cluster so every resource targets its data plane API.
data "redpanda_cluster" "this" {
  id = var.cluster_id
}

locals {
  cluster_api_url = data.redpanda_cluster.this.cluster_api_url

  topic_name = "orders"
  user_name  = "orders-app"
  role_name  = "orders-producer"

  # Shared topic configuration. Change it here and the change is promoted
  # dev -> prod through the pipeline.
  topic_config = {
    "cleanup.policy" = "delete"
    "retention.ms"   = "604800000" # 7 days
  }

  # Operations the role grants on the topic.
  role_topic_operations = ["DESCRIBE", "READ", "WRITE"]
}

resource "redpanda_topic" "orders" {
  name               = local.topic_name
  partition_count    = var.topic_partitions
  replication_factor = 3
  configuration      = local.topic_config
  cluster_api_url    = local.cluster_api_url
  allow_deletion     = var.allow_deletion
}

resource "redpanda_user" "orders_app" {
  name                = local.user_name
  password_wo         = var.app_user_password
  password_wo_version = var.app_user_password_version
  mechanism           = "scram-sha-256"
  cluster_api_url     = local.cluster_api_url
  allow_deletion      = var.allow_deletion
}

resource "redpanda_role" "orders_producer" {
  name            = local.role_name
  cluster_api_url = local.cluster_api_url
  allow_deletion  = var.allow_deletion
}

# ACLs are bound to the role, not the user. Access is granted through the role binding below.
resource "redpanda_acl" "orders_producer_topic" {
  for_each = toset(local.role_topic_operations)

  resource_type         = "TOPIC"
  resource_name         = redpanda_topic.orders.name
  resource_pattern_type = "LITERAL"
  principal             = "RedpandaRole:${redpanda_role.orders_producer.name}"
  host                  = "*"
  operation             = each.value
  permission_type       = "ALLOW"
  cluster_api_url       = local.cluster_api_url
  allow_deletion        = var.allow_deletion
}

# Role binding: attach the user to the role.
resource "redpanda_role_assignment" "orders_app" {
  role_name       = redpanda_role.orders_producer.name
  principal       = "User:${redpanda_user.orders_app.name}"
  cluster_api_url = local.cluster_api_url
}
