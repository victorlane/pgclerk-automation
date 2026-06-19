
# Stub modules emit no real resources yet. The pgclerk operator UI
# reads jit-seed via /api/clusters/:id/jit-seed using the hostnames
# this output should eventually surface (one row per PG/etcd/backup
# host).
output "pg_hosts" {
  description = "List of { hostname, ip, role } objects for jit-seed."
  value       = []
}
