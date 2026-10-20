# Nomad + Prometheus demo: automatic service scraping

Every Nomad service tagged `prometheus-metrics` is discovered and scraped by
Prometheus, without ever touching the Prometheus configuration.
Adding an application means deploying its job: monitoring follows on its own.

## Requirements

- macOS with Docker Desktop running
- Nomad 1.7 or later (tested with 2.0.4): `brew install hashicorp/tap/nomad`

## Quick start

```bash
chmod +x run.sh stop.sh
./run.sh
```

The script:

1. starts a Nomad dev agent with ACLs enabled;
2. creates the ACL policy and token used by Prometheus;
3. deploys Prometheus and every job in `apps/`;
4. prints the URLs.

## Access

| Interface                     | URL                                     | Notes                                         |
|-------------------------------|-----------------------------------------|-----------------------------------------------|
| Nomad UI                      | http://127.0.0.1:4646/ui                | Sign in with the token, see below             |
| Prometheus targets            | http://localhost:9090/targets           | Status and URL of every scraped target        |
| Prometheus service discovery  | http://localhost:9090/service-discovery | Discovered services, including dropped ones   |
| Applications (podinfo, caddy) | printed by `run.sh`                     | Dynamic ports picked by Nomad                 |

**Signing in to the Nomad UI:** the management token is stored in `.nomad-token`.

1. Copy it with `pbcopy < .nomad-token`.
2. Click **Sign In** at the top right of the UI.
3. Paste it into the *Secret ID* field.

**Using the `nomad` CLI from another terminal:**

```bash
export NOMAD_ADDR=http://127.0.0.1:4646 NOMAD_TOKEN=$(cat .nomad-token)
nomad ui -authenticate   # opens the UI already signed in
```

## Demo walkthrough

1. **Start.** Run `./run.sh`. The `/targets` page shows 3 targets UP
   (prometheus and 2 podinfo instances), none of them hard-coded.
2. **Traffic.** Open a podinfo URL and refresh it a few times, then run this
   query in Prometheus:
   `sum by (job) (rate(http_requests_total[1m]))`
3. **Live new service.** Run `./run.sh extra/caddy.nomad.hcl`. Within about
   25 seconds, the `caddy` target appears, scraped on `/stats/prometheus`.
4. **Scale.** With the CLI configured (see above):
   - `nomad job scale podinfo podinfo 4` adds two targets;
   - `nomad job stop caddy` removes its target.
5. **Stop.** Run `./stop.sh`.

## Adding a service

The only contract lives in the job's `service` block:

```hcl
service {
  name     = "my-app"
  port     = "http"
  provider = "nomad"                      # required: native Nomad service catalog
  tags = [
    "prometheus-metrics",                 # enables scraping
    "metrics-path=/path/to/metrics",      # optional, defaults to /metrics
  ]
}
```

Then deploy it with `./run.sh path/to/my-app.nomad.hcl`.
A service without the tag is still visible in Nomad, but Prometheus ignores it.

## How it works

### Discovery

Every 10 seconds, Prometheus queries the Nomad API (`nomad_sd_configs`) and gets
the list of services with their tags. The `relabel_configs`:

- keep only services tagged `prometheus-metrics`;
- apply the path given by `metrics-path=`, when present;
- set readable labels:
  - `job`: the service name,
  - `nomad_job`,
  - `nomad_alloc`,
  - `nomad_dc`.

### Security

ACLs are enabled. On startup, `run.sh`:

1. creates the `prometheus-sd` policy, limited to `read-job` on the `default` namespace;
2. creates a token bound to that policy;
3. stores the token in the Nomad Variable `nomad/jobs/prometheus`.

The Prometheus job reads that variable through its workload identity, and Nomad
renders it into `/secrets/nomad_token`. No secret is stored in the repository.

### macOS specifics

In dev mode, Nomad registers services on `127.0.0.1`. Seen from the Prometheus
container, that address points to the container itself. A relabel rule therefore
rewrites these addresses to `host.docker.internal`.
On a real Linux cluster, services are registered on the node IP and this rule
never applies.

## Project layout

```
.
├── run.sh                      start everything, or add services
├── stop.sh                     stop everything
├── prometheus/
│   ├── prometheus.nomad.hcl    Prometheus job
│   ├── prometheus.yml          discovery and relabeling
│   └── prometheus-sd.policy.hcl
├── apps/                       jobs deployed on startup
│   └── podinfo.nomad.hcl
└── extra/                      jobs to add live
    └── caddy.nomad.hcl
```

## Stopping

`./stop.sh` stops the Nomad agent and removes the containers it started
(label `com.hashicorp.nomad.alloc_id`).

In dev mode, all state (jobs, ACLs, variables) is lost on shutdown:
every `./run.sh` starts from scratch.

## Troubleshooting

| Symptom                                         | What to check                                                                                  |
|-------------------------------------------------|------------------------------------------------------------------------------------------------|
| `/targets` is empty                             | Discovery is failing, usually because of the token: `nomad alloc logs -stderr -job prometheus` |
| Targets are DOWN                                | The `host.docker.internal` path fails: check that Docker Desktop is the active context (`docker context ls`) |
| A job is stuck on a mount error                 | Docker Desktop > Settings > Resources > File sharing: `/var/folders` must be shared            |
| `run.sh` hangs right after starting Nomad       | Nomad cannot start or cannot reach Docker: check `nomad.log`                                   |
| `cat: .nomad-token: No such file or directory`  | A Nomad agent not started by `run.sh` is running: `./stop.sh`, then `./run.sh`                 |