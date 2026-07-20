# Verification learnings

Checks and pitfalls discovered during test runs, beyond what smoke-test.sh
covers. Append to this file when a run teaches you something the checks missed.

## Run 36df1f promtail -> vector migration (2026-07-20)

- Label parity verified exactly: a VRL remap reproduces promtail's scheme
  (app/component from pod labels with app.kubernetes.io/* fallbacks,
  job=namespace/app, instance, container, filename, namespace, node_name,
  pod, stream). Verified by diffing /loki/api/v1/labels and per-pod
  /series output before and after cutover -- identical.
- vector 0.57 gotchas: VRL rejects ?? on infallible path lookups (use
  if-null fallbacks), and dynamic "*" label maps need
  dangerously_allow_unconfined_template_resolution: true on the loki sink.
  Disable the sink healthcheck -- gigapipe has no /ready endpoint.
- **Gigapipe has ~1-2 min ingest visibility lag** (ClickHouse insert
  buffering): query_range returns nothing for very fresh lines while
  /series and /labels already show them. Wait before concluding the
  pipeline is broken.
- Footprint: ~15m CPU / ~196Mi RAM total across 7 vector agents.

## Run 36df1f linkerd migration (2026-07-20, stable-2.14.10 -> edge-26.5.1)

- **The linkerd OSS stable channel is dead** — stable-2.14 was the last;
  open source releases now ship on the edge channel only (helm repo
  https://helm.linkerd.io/edge). Use releases marked "recommended" in the
  GitHub release notes, per Mynewsdesk operational practice.
- The 2.14 -> 26.5.1 jump synced cleanly in one step on a live mesh; meshed
  workloads kept serving on old proxies until restarted (README process:
  control plane, then viz, then rollout-restart all meshed workloads).
  Meshed pods are found by looking for a linkerd-proxy container OR
  initContainer (native sidecar mode moves it to initContainers).
- installGatewayAPI defaults to false in current edge charts — no Gateway
  API CRDs are required unless HTTPRoute policy is wanted.

## Run 36df1f upgrade batch 2 (2026-07-20, nine components)

- **talosctl 1.13 restructured `cluster create`** into provisioner
  subcommands (`talosctl cluster create docker`) and renamed flags
  (--cpus-controlplanes, --memory-controlplanes with GiB format,
  --config-patch-workers). The v1.6-era README syntax prints usage help and
  exits 0 -- validate README commands by running them, not by exit codes.

- **altinity-clickhouse-operator chart 0.25+ CRD hooks break under ArgoCD.**
  The chart installs CRDs via PreSync hook ConfigMaps + a job; ArgoCD applies
  hooks client-side (app-level ServerSideApply does NOT cover hooks) and the
  CRD ConfigMaps exceed the 262KB annotation limit, wedging the sync on
  "waiting for completion of hook". Fix: `crdHook.enabled: false` (CRDs are
  already managed via helm template --include-crds) + ServerSideApply for the
  big CRDs themselves.
- **SSA can't switch a Deployment to `strategy: Recreate`** when the live
  object has a defaulted rollingUpdate block ("Forbidden: may not be
  specified"). Patch the live strategy first (remove rollingUpdate, set type)
  or delete the deployment and let ArgoCD recreate it.
- **Check stale upgrade-blocker comments against the upstream issue.** The
  altinity manifest said "not upgrading until #1714" — that issue was fixed
  in 0.25.1, a year before this run.
- **Self-managed ArgoCD upgrades need SSA for the ApplicationSet CRD**
  (also >262KB). And on ArgoCD 3.4.x, triggering a sync by patching
  `.operation` does NOT inherit `spec.syncPolicy.syncOptions` — pass them
  explicitly: `{"operation":{"sync":{"syncOptions":["ServerSideApply=true"]}}}`.
- **Application manifests propagate via the `platform` app.** Changing
  anything under platform-applications/ requires refreshing `platform` first,
  then the target app. A watcher asserting only Synced/Healthy can pass
  against the STALE spec — assert the new targetRevision/image too (this
  batch's ECK watcher initially "passed" with the old operator running).
  Also: app names don't always match file names (file
  elastic-cloud-on-kubernetes.yaml -> app elastic-cloud-kubernetes-operator).
- **Single-replica ClickHouse restarts briefly break gigapipe ingestion**
  (transient "no such host" on the headless service during pod roll;
  self-heals in <30s). HA would need replicas 2+ plus keeper.
- kube-prometheus-stack 74 -> 87 (13 chart majors) applied cleanly in one
  sync thanks to pre-existing ServerSideApply; Prometheus 3.13.1, 44 targets
  up afterwards. ECK 3.0 -> 3.4.1 rolled in ~30s with ES green throughout.

## Run 36df1f upgrade phase (2026-07-20, CNPG 1.26.0 -> 1.30.0, PG 17.5 -> 18.4)

- **CNPG operator upgrade restarts every instance.** The 1.26 -> 1.30 jump
  rolled the instance managers: replicas restarted first, then the primary
  in-place ("Primary instance is being restarted without a switchover",
  ~3.5 min with a brief write-unavailability window). Total ~4 min back to
  healthy; data and app unaffected. Expect this on any operator bump.
- **Declarative PG major upgrades work and are fast on small data.**
  Changing imageName 17.5 -> 18.4 triggered CNPG's offline pg_upgrade path:
  "Upgrading Postgres major version" (~4 min, cluster offline), primary up,
  replica re-cloned, healthy at ~4.5 min. Data verified intact afterwards.
  Watch `.status.phase` on the Cluster resource for the timeline.
- **Switching enablePodMonitor -> explicit PodMonitor loses the monitor once.**
  The operator deletes its auto-managed PodMonitor when the flag goes away,
  taking the identically-named ArgoCD-created one with it; without selfHeal
  the app then sits OutOfSync (Healthy). One manual sync fixes it — trigger
  headless with:
  `kubectl patch application <app> -n argocd --type merge -p '{"operation":{"sync":{"revision":"<branch>"}}}'`

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
