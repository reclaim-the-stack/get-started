---
description: Full automated test run — disposable cluster, platform, rails-example, optional upgrades
---

Perform an automated test run of this repository per AGENTS.md. Read AGENTS.md
and agent/VERIFICATION.md fully before starting.

1. Preflight: verify .env.local credentials and required CLIs, and sync the
   testbed fork's master with upstream.
2. Generate a run id; create the localized run branch and push it to the fork.
3. agent/create-cluster.sh, then bootstrap the platform per the README
   (apply the known workarounds from VERIFICATION.md "Known standing issues").
4. agent/create-tunnel.sh, enable cloudflared, then agent/smoke-test.sh.
5. Deploy rails-example with the k CLI (K_CONTEXT procedure in AGENTS.md) and
   verify with agent/verify-rails-example.sh.
6. Check all platform components and generator templates for available
   upstream updates (compare pinned versions against latest releases). Report
   what is outdated. If asked to proceed with upgrades: apply them one
   component at a time on the live cluster, verify each, capture learnings in
   VERIFICATION.md, and prepare upstream PRs per the branch conventions in
   AGENTS.md.
7. Report results. Ask before tearing down ($ARGUMENTS may say "teardown when
   green" to skip asking).
