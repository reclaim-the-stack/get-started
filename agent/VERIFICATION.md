# Verification learnings

Durable checks and pitfalls discovered during test runs, beyond what
smoke-test.sh covers. Append when a run teaches something new; prune entries
that become obsolete (eg. fixed in the repo) to keep this file lean.

## Verifying ArgoCD state

- **Root/parent apps can be Healthy while a child app is broken.** Check every
  Application, and treat sync status `Unknown` as an error — details are in
  `.status.conditions` (ComparisonError etc), not in health status.
- **Application manifests propagate via the `platform` app.** After changing
  anything under platform-applications/, refresh `platform` first, then the
  target app. A watcher asserting only Synced/Healthy can pass against the
  stale spec — also assert the new targetRevision/image. App names don't
  always match file names (eg. elastic-cloud-on-kubernetes.yaml -> app
  elastic-cloud-kubernetes-operator).
- **Headless sync must pass syncOptions explicitly** — patching `.operation`
  does not inherit `spec.syncPolicy.syncOptions` (observed on ArgoCD 3.4.x):
  `kubectl patch application <app> -n argocd --type merge -p '{"operation":{"sync":{"syncOptions":["ServerSideApply=true"]}}}'`
- **ArgoCD applies hook resources client-side** — app-level ServerSideApply
  does not cover them, so charts shipping CRDs via hook ConfigMaps >262KB
  wedge the sync on "waiting for completion of hook" (why crdHook is disabled
  for altinity-clickhouse-operator; CRDs come via helm --include-crds).
- **SSA can't switch a Deployment to `strategy: Recreate`** over a live
  defaulted rollingUpdate block. Patch the live strategy first or delete the
  deployment and let ArgoCD recreate it.

## Verifying ingress and the application

- **Cloudflare edge caches error responses** (eg. cloudflared's catch-all 404,
  max-age=14400). Always cache-bust (`?cb=<random>`) when verifying ingress.
- **Use explicit per-hostname DNS records, not wildcards** — multi-level
  wildcard certs require ACM/Total TLS and issue slowly; explicit proxied
  hostnames get certs in seconds on any plan (`agent/add-dns.sh`). A fresh
  record can fail TLS handshake for up to a minute — retry before concluding
  breakage.
- **cloudflared config changes sync via the `cloudflared` app**, not
  `platform`; Reloader then restarts the pod automatically (~30s).
- **agent/verify-rails-example.sh** exercises Postgres (post create/read),
  Redis+Sidekiq (async link title resolution) and Elasticsearch (search)
  through the tunnel.

## Verifying logs

- **Gigapipe is near-realtime** (~3s write-to-queryable; flush default
  BULK_MAX_AGE_MS=100). Verify ingestion with a unique marker line plus a
  poll loop, never a single query — one-off blind spots (eg. right after a
  collector change, or during single-replica ClickHouse restarts, which break
  ingestion for <30s) look identical to a broken pipeline.

## Upgrade playbook notes

- **CNPG operator upgrades roll every postgres instance** (replicas first,
  then the primary in-place with a brief write-unavailability window, ~4 min
  total). Declarative PG major upgrades (change imageName) run an offline
  pg_upgrade — watch `.status.phase` on the Cluster for the timeline.
- **linkerd ships via the edge channel only** (OSS stable ended at 2.14); use
  releases marked "recommended" in the GitHub release notes. Upgrade order:
  control plane, then viz, then rollout-restart all meshed workloads. Meshed
  pods have a linkerd-proxy container OR initContainer (native sidecar mode).
- **Check stale upgrade-blocker comments against their upstream issue** —
  they outlive their reason (one blocked an upgrade a full year after the
  issue was fixed).
- **`latest` image tags are moving targets** — when behavior differs between
  runs, check whether the tag moved (Docker Hub API shows `last_updated`).
  Pin versions wherever an operator or template would otherwise default to
  latest.
- **Validate documented commands by executing them**, not by reading or exit
  codes — a restructured CLI can print usage help and exit 0 (talosctl did).

## General verification pitfalls

- **Verify resource names before writing wait conditions** (eg. the ECK
  Elasticsearch CR is `rails-example`, its pods `rails-example-es-*`). Always
  give wait loops a deadline and print observed state on timeout.

## Known standing issues

- **hetzner-k3s 2.6.0 deploys cluster-autoscaler even with no autoscaled node
  pools**; it crashloops with `No cluster config present provider: <nil>`.
  Workaround each run: `kubectl -n kube-system scale deployment cluster-autoscaler --replicas=0`.
  Worth reporting upstream to vitobotta/hetzner-k3s.
