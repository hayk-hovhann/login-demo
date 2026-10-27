# db-tunnel.sh and redis-tunnel.sh read it: the --target of the SSM
# port-forward session.
output "instance_id" {
  description = "Bastion instance id, the --target for an SSM port-forward session."
  value       = aws_instance.bastion.id
}
