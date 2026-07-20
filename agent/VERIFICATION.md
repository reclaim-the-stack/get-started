# Verification learnings

Checks and pitfalls discovered during test runs, beyond what smoke-test.sh
covers. Append to this file when a run teaches you something the checks missed.

## Run 0d0024 (2026-07-20, first end-to-end run)

- **Root/parent ArgoCD apps can be Healthy while a child app is broken.**
  `platform` reported Synced/Healthy while `sealed-secrets` had sync status
  Unknown (chart repo 404). Always check every Application, and treat sync
  status `Unknown` as an error: the details are in `.status.conditions`
  (ComparisonError etc), not in health status.
- **Cloudflare edge caches error responses.** cloudflared's catch-all
  `http_status:404` is cacheable (max-age=14400) — a hostname can keep
  serving 404 from cache after the tunnel config is fixed. Always cache-bust
  (`?cb=<random>`) when verifying ingress changes.
- **cloudflared config changes are picked up via the `cloudflared` app, not
  `platform`** — refresh that app after editing `platform/cloudflared/config.yaml`;
  Reloader then restarts the pod automatically (~30s).
- **Verify resource names before writing wait conditions.** The ECK
  Elasticsearch CR is named `rails-example` while its pods are
  `rails-example-es-*`. A wait loop querying a nonexistent name spins forever;
  a 2-minute deploy looked like a 20-minute one. Check
  `kubectl get <kind>` output first, and prefer wait conditions that also have
  a failure/timeout path.
- **hetzner-k3s 2.6.0 deploys cluster-autoscaler even with no autoscaled
  node pools**; it crashloops with `No cluster config present provider: <nil>`.
  Workaround: `kubectl -n kube-system scale deployment cluster-autoscaler --replicas=0`.
  Worth reporting upstream to vitobotta/hetzner-k3s.
- **Total TLS issues wildcard certs SLOWLY.** A wildcard record like
  `*.rts-<id>.<domain>` does get an edge cert, but issuance took somewhere
  between 15 and 50 minutes on run 0d0024 — until then every hostname under
  it fails TLS handshake. Specific proxied hostnames get their cert in
  seconds. Don't conclude "wildcards unsupported" from an early handshake
  failure (this run initially did). Recommended: wildcard record for apps
  plus instant specific records for argocd/grafana so ingress verification
  never blocks on wildcard issuance.
- **End-to-end app verification**: agent/verify-rails-example.sh exercises
  Postgres (post create/read), Redis+Sidekiq (async link title resolution)
  and Elasticsearch (search) through the tunnel.
