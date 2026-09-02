subscription_id = "dd0500ca-c7d3-42c6-a391-9389ca0e2848"
location        = "eastus2"
project         = "nextweb"
environment     = "prod"

min_replicas = 2
max_replicas = 10

# After adding these endpoints to the app, use:
# liveness_probe_path  = "/api/health/live"
# readiness_probe_path = "/api/health/ready"

tags = {
  managed-by  = "terraform"
  workload    = "nextjs"
  owner       = "platform-team"
  cost-center = "replace-me"
}
