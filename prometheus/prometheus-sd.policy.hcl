# Minimal permissions for Prometheus service discovery:
# list and read Nomad services in the "default" namespace, nothing else.
namespace "default" {
  capabilities = ["read-job"]
}