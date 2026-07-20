# Agent Instructions

This file is context for AI agents running automated test/upgrade cycles of the
Reclaim the Stack platform. Humans: you can ignore it (or read it as a preview
of how the stack is continuously tested).

## The README is the product

This repo is a gitops template that people bootstrap by following README.md by
hand. When testing, **follow the README as the source of truth** — if you get
stuck or need outside knowledge to complete a step, that is a documentation bug
and one of the most valuable findings a run can produce. Report it, or fix it
in a way that helps human readers too.

The exceptions, where you should deviate from the README:

- **Interactive steps don't work headless.** `cloudflared tunnel login` opens a
  browser; use `agent/create-tunnel.sh` instead (same result via the
  Cloudflare API). Dashboard-clicking steps (DNS records, webhooks) are also
  handled by the scripts or the `gh` CLI.
- **The ArgoCD UI is for humans.** Verify sync/health with kubectl instead:
  `kubectl get applications -n argocd` (add `-o json` for condition details).

## Setup

Credentials live in `.env.local` (gitignored, see `.env.local.example`).
Required CLIs: `hetzner-k3s`, `kubectl`, `yq`, `jq`, `kubeseal`, `gh`.

## Test run lifecycle

Every run has a run id (short, lowercase, eg. `openssl rand -hex 3`). All cloud
resources the run creates are named `rts-<run-id>` so they can be found and
destroyed without local state.

1. `agent/create-cluster.sh <run-id>` — Hetzner cluster up, node roles labeled,
   kubeconfig in `agent/runs/<run-id>/kubeconfig`
2. Follow the README Installation section (ArgoCD, argocd-root)
3. `agent/create-tunnel.sh <run-id>` — tunnel + DNS records for argocd and
   grafana + sealed credentials; finish the manual steps it prints. Every
   ingress hostname needs its own DNS record (`agent/add-dns.sh`) — explicit
   records keep TLS working on any Cloudflare plan, wildcards would not
4. Deploy https://github.com/reclaim-the-stack/rails-example with the
   [k CLI](https://github.com/reclaim-the-stack/k) per its README to exercise
   Postgres, Redis and Elasticsearch; add its hostname with
   `agent/add-dns.sh <run-id> rails-example`
5. `agent/smoke-test.sh <run-id>` — must pass before and after any upgrade work
6. Upgrade iteration (see below)
7. `agent/teardown.sh <run-id>` — **always run this before finishing**, even
   after failed runs. `agent/teardown.sh --list` shows leftovers from any run.

Verification beyond the smoke test: when a run teaches you a check worth
keeping (a failure mode the smoke test missed), append it to
`agent/VERIFICATION.md` so future runs check it too.

## Branch conventions (work happens on a fork)

Upgrade testing happens on a fork of reclaim-the-stack/get-started. Keep
history so that upgrade work can be cherry-picked cleanly onto upstream master:

- `master` — pure mirror of upstream, never diverges
- `run/<run-id>` — branched from master, starts with a single **localize
  commit** (repo URL search+replace, cloudflared domain/tunnel name, sealed
  tunnel credentials, ArgoCD `targetRevision` pointed at the run branch)
- Upgrade commits on top: **one component per commit**, including any related
  docs/generator updates, never touching localized values
- Merging within the fork needs no human review; commit messages should record
  what was verified

The end product of successful runs is an upstream PR: cherry-pick the upgrade
commits onto a fresh branch off upstream master, run a from-scratch
verification of that branch (new run id, full lifecycle), then open the PR
with the run evidence in the description. This final phase is only done when
explicitly requested.

## Safety rules

- Only modify the fork and PRs targeting reclaim-the-stack/get-started.
  No other repos, no other write operations on GitHub.
- Only create/delete cloud resources named `rts-<run-id>`. Never touch
  anything else in the Hetzner project or Cloudflare zone.
- Never commit secrets. `.env.local`, `tunnel-credentials.json`, kubeconfigs
  and `agent/runs/` are gitignored — keep it that way. The only secret that
  belongs in git is the *sealed* tunnel credential.
- Leave no orphans: if a run aborts, tear down what was created.
