#!/usr/bin/env bash
# Usage:
#   ./run.sh                          start Nomad, Prometheus and every job in apps/
#   ./run.sh extra/caddy.nomad.hcl    deploy one or more additional jobs
set -euo pipefail
cd "$(dirname "$0")"
export NOMAD_ADDR=http://127.0.0.1:4646

docker info >/dev/null 2>&1 || { echo "Docker is not running" >&2; exit 1; }

# Start a dev agent with ACLs enabled, unless one is already running
fresh=false
if ! curl -sf "$NOMAD_ADDR/v1/status/leader" >/dev/null; then
  fresh=true
  DOCKER_HOST=$(docker context inspect -f '{{.Endpoints.docker.Host}}') \
    nohup nomad agent -dev -acl-enabled >nomad.log 2>&1 &
  # Bootstrap fails until the agent is up and has a leader, so just retry
  until nomad acl bootstrap 2>/dev/null | awk '/^Secret ID/ {print $NF}' >.nomad-token && [ -s .nomad-token ]; do
    sleep 1
  done
fi
export NOMAD_TOKEN=$(cat .nomad-token)

if $fresh; then
  # Least-privilege token for Prometheus, stored in a variable only the "prometheus" job can read
  nomad acl policy apply prometheus-sd prometheus/prometheus-sd.policy.hcl
  sd_token=$(nomad acl token create -name prometheus-sd -policy prometheus-sd | awk '/^Secret ID/ {print $NF}')
  nomad var put nomad/jobs/prometheus sd_token="$sd_token" >/dev/null 2>&1
  until nomad node status -self 2>/dev/null | grep -q 'Driver Status.*docker'; do sleep 1; done
fi

# No argument, or fresh agent: deploy Prometheus and every app
if $fresh || [ $# -eq 0 ]; then
  set -- prometheus/prometheus.nomad.hcl apps/*.nomad.hcl "$@"
fi

# Run each job from its own directory so that file() resolves relative paths
for job in "$@"; do
  (cd "$(dirname "$job")" && nomad job run "$(basename "$job")")
done

echo
echo "Nomad UI:   $NOMAD_ADDR/ui  (token: $NOMAD_TOKEN)"
echo "Prometheus: http://localhost:9090/targets"
echo "Services:"
for svc in $(nomad service list -t '{{range .}}{{range .Services}}{{.ServiceName}} {{end}}{{end}}'); do
  nomad service info -t '{{range .}}{{printf "  %-11s http://%s:%d  %v\n" .ServiceName .Address .Port .Tags}}{{end}}' "$svc"
done
echo
echo "CLI: export NOMAD_ADDR=$NOMAD_ADDR NOMAD_TOKEN=$NOMAD_TOKEN"