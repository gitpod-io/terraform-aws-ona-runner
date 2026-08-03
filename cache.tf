resource "random_password" "cache" {
  length           = 32
  special          = true
  override_special = "_"
}

resource "aws_security_group" "memorydb" {
  count       = var.cache_engine == "MemoryDB" ? 1 : 0
  name_prefix = "${local.name_prefix}-memorydb-"
  description = "Security group for Ona AI execution MemoryDB"
  vpc_id      = var.vpc_id

  ingress {
    security_groups = [aws_security_group.ecs.id]
    protocol        = "tcp"
    from_port       = 6379
    to_port         = 6379
    description     = "Allow ECS tasks to connect to MemoryDB"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-memorydb" })
}

resource "aws_memorydb_subnet_group" "this" {
  count       = var.cache_engine == "MemoryDB" ? 1 : 0
  name        = "${local.memorydb_subnet_name_prefix}-memorydb-subnet"
  description = "Subnet group for Ona AI execution MemoryDB"
  subnet_ids  = var.runner_subnet_ids
  tags        = local.common_tags
}

resource "aws_memorydb_user" "this" {
  count     = var.cache_engine == "MemoryDB" ? 1 : 0
  user_name = "${local.memorydb_user_name_prefix}-memorydb-user"
  // MemoryDB normalizes an unrestricted ACL to include resetchannels.
  access_string = "on ~* resetchannels +@all"

  authentication_mode {
    type      = "password"
    passwords = [random_password.cache.result]
  }

  tags = local.common_tags
}

resource "aws_memorydb_acl" "this" {
  count      = var.cache_engine == "MemoryDB" ? 1 : 0
  name       = "${local.memorydb_acl_name_prefix}-memorydb-acl"
  user_names = [aws_memorydb_user.this[0].user_name]
  tags       = local.common_tags
}

resource "aws_memorydb_cluster" "this" {
  count                      = var.cache_engine == "MemoryDB" ? 1 : 0
  name                       = "${local.memorydb_name_prefix}-memorydb"
  description                = "AI execution data store with TLS enabled"
  node_type                  = local.memorydb_node_type
  num_shards                 = 1
  num_replicas_per_shard     = 0
  parameter_group_name       = "default.memorydb-valkey7"
  subnet_group_name          = aws_memorydb_subnet_group.this[0].name
  security_group_ids         = [aws_security_group.memorydb[0].id]
  tls_enabled                = true
  port                       = 6379
  acl_name                   = aws_memorydb_acl.this[0].name
  engine_version             = "7.3"
  engine                     = "valkey"
  auto_minor_version_upgrade = true
  tags                       = local.common_tags
}

resource "aws_security_group" "elasticache" {
  count       = var.cache_engine == "ElastiCache" ? 1 : 0
  name_prefix = "${local.name_prefix}-redis-"
  description = "Security group for Ona AI execution ElastiCache Redis"
  vpc_id      = var.vpc_id

  ingress {
    security_groups = [aws_security_group.ecs.id]
    protocol        = "tcp"
    from_port       = 6379
    to_port         = 6379
    description     = "Allow ECS tasks to connect to Redis"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-redis" })
}

resource "aws_elasticache_subnet_group" "this" {
  count      = var.cache_engine == "ElastiCache" ? 1 : 0
  name       = "${local.elasticache_subnet_name_prefix}-redis-subnet"
  subnet_ids = var.runner_subnet_ids
}

resource "aws_elasticache_replication_group" "this" {
  count                      = var.cache_engine == "ElastiCache" ? 1 : 0
  replication_group_id       = "${local.elasticache_name_prefix}-redis"
  description                = "AI execution data store with TLS enabled"
  engine                     = "redis"
  engine_version             = "7.1"
  parameter_group_name       = "default.redis7.cluster.on"
  node_type                  = local.elasticache_node_type
  num_node_groups            = 1
  replicas_per_node_group    = 0
  port                       = 6379
  subnet_group_name          = aws_elasticache_subnet_group.this[0].name
  security_group_ids         = [aws_security_group.elasticache[0].id]
  transit_encryption_enabled = true
  at_rest_encryption_enabled = true
  auth_token                 = random_password.cache.result
  apply_immediately          = true
  auto_minor_version_upgrade = true
  tags                       = local.common_tags
}

locals {
  cache_connection_string = var.cache_engine == "MemoryDB" ? "redis://${aws_memorydb_user.this[0].user_name}:${random_password.cache.result}@${aws_memorydb_cluster.this[0].cluster_endpoint[0].address}:6379/0" : "redis://default:${random_password.cache.result}@${aws_elasticache_replication_group.this[0].configuration_endpoint_address}:6379/0"
}

resource "aws_ssm_parameter" "redis_connection" {
  name        = local.redis_parameter_name
  description = "Cache connection string for AI feature"
  type        = "SecureString"
  value       = local.cache_connection_string
  tags        = local.common_tags
}
