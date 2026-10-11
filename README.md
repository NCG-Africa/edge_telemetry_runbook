# EdgeTelemetry Deployment Guide & Runbook

Single-file interactive guide (`index.html`) for deploying the **Go** EdgeTelemetry
stack (single-host) on Linux, plus the on-call runbook: upgrade, rollback,
troubleshooting, acceptance run, secret rotation and command reference.

Source of truth for every command is the deployment repo
[`NCG-Africa/edge_telemetry_deployment_go`](https://github.com/NCG-Africa/edge_telemetry_deployment_go)
(README §2–§6). When that repo changes, update this page and rebuild the package.

## What it covers

1. Prerequisites (incl. stopping the Python stack)
2. Config builder: generates `configs/single-host.env` and `configs/kafka-ui.env` in the browser
3. Server prep with `getstarted.sh` (Debian, RHEL, SUSE families)
4. Download package (`downloads/edge_telemetry_deployment_go.zip`)
5. Transfer to `/opt/edgetelemetry`
6. Write config + `make config-check`
7. `make db-baseline`
8. `make deploy`
9. nginx + TLS (`/collector-go/`, `/processor-go/`, `/api/`)
10. Verify

The runbook section below the steps is always unlocked.

## Local preview

```bash
python3 -m http.server 8000   # http://localhost:8000
```

Deployed as static assets on Cloudflare Workers (`wrangler.jsonc`).

## Rebuild the deployment package

From the deployment repo, tracked files only (never real env files or keys):

```bash
cd /path/to/edge_telemetry_deployment_go
git archive --format=zip --prefix=edge_telemetry_deployment_go/ \
  -o /path/to/runbook/downloads/edge_telemetry_deployment_go.zip HEAD
```

Internal use only - NCG Africa
