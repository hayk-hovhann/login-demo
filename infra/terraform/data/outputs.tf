# What the rest of the system needs from the database: where it is, how to
# log in, and the badge that lets a caller through. Written once here; each
# value goes out twice, as an output below for terraform output at the
# terminal, and as an SSM parameter (parameters.tf) for every other reader.
locals {
  published = {
    # The backend's DB_HOST: the bare hostname, no port. Named for what it
    # feeds, not after the provider's endpoint attribute, which is host:port.
    db_host = aws_db_instance.db.address

    # A string, as every parameter value is.
    db_port = tostring(aws_db_instance.db.port)

    # Read back from the instance, so a restore reports the snapshot's
    # database, which is this one under the same name.
    db_name = aws_db_instance.db.db_name

    # The RDS-managed master secret: JSON with username and password keys.
    # The backend and migrate tasks pull each key into its own env var at task
    # start, and the app's execution role must be allowed to read it. The ARN,
    # not the secret: nothing here ever holds the password.
    db_secret_arn = aws_db_instance.db.master_user_secret[0].secret_arn

    # The badge: the backend tasks, the migrate task and the bastion wear it.
    db_client_security_group_id = aws_security_group.db_client.id
  }
}

output "db_host" {
  description = "RDS endpoint hostname, without the port."
  value       = local.published.db_host
}

output "db_port" {
  description = "Port Postgres listens on."
  value       = local.published.db_port
}

output "db_name" {
  description = "Database the app connects to."
  value       = local.published.db_name
}

output "db_secret_arn" {
  description = "Secrets Manager ARN of the RDS-managed master credentials."
  value       = local.published.db_secret_arn
}

output "db_client_security_group_id" {
  description = "Attach to anything that needs Postgres on 5432."
  value       = local.published.db_client_security_group_id
}
