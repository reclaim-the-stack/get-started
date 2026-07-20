# Verification learnings

Checks and pitfalls discovered during test runs, beyond what smoke-test.sh
covers. Append to this file when a run teaches you something the checks missed.

## Run 36df1f (2026-07-20, second run; cluster kept for operator upgrade testing)

- **`rails-example:latest` is a moving target.** The image was rebuilt between
  two same-day runs (Sidekiq 7 -> 8), and Sidekiq 8 requires Redis 7+ while the
  spotahome operator defaults to redis:6.2.6-alpine when the RedisFailover
  spec has no image -- sidekiq crashlooped with "Sidekiq requires Redis 7.0.0
  or greater". Fixed by pinning redis:7.4.9-alpine (redis + sentinel) in the
  redis generator. When a deployment behaves differently between runs, check
  whether the image tag moved (Docker Hub API shows `last_updated`).
- Platform bootstrap + tunnel + smoke test needed zero manual intervention
  this run — all run-0d0024 fixes (sealed-secrets URL, explicit DNS records,
  ES quantity quoting, K_CONTEXT procedure) validated from scratch.

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
- **Use explicit per-hostname DNS records, not wildcards.** Multi-level
  wildcards (`*.rts-<id>.<domain>`) only get edge certs on zones with
  ACM/Total TLS, and even there issuance took 15-50 minutes on run 0d0024 —
  until then every hostname under the wildcard fails TLS handshake. Specific
  proxied hostnames get certs within seconds on any plan. The harness
  therefore creates explicit records only (`agent/add-dns.sh`); don't
  conclude "TLS is broken" from a handshake failure on a hostname whose
  record was just created — retry for a minute first.
- **End-to-end app verification**: agent/verify-rails-example.sh exercises
  Postgres (post create/read), Redis+Sidekiq (async link title resolution)
  and Elasticsearch (search) through the tunnel.
