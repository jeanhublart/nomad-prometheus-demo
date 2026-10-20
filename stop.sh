#!/usr/bin/env bash
# Stop the Nomad dev agent, then remove any container it left behind.
cd "$(dirname "$0")"

if pkill -f 'nomad agent -dev'; then
  while pgrep -f 'nomad agent -dev' >/dev/null; do sleep 1; done
fi
docker rm -f $(docker ps -aq --filter label=com.hashicorp.nomad.alloc_id) >/dev/null 2>&1
rm -f .nomad-token
echo "Stopped."