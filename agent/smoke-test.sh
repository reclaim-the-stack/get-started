#!/usr/bin/env bash
# Basic health checks for a test cluster. Exits non-zero on any failure --
# diagnosing *why* something failed is the agent's job, not this script's.
#
# Usage: agent/smoke-test.sh <run-id>

source "$(dirname "$0")/common.sh"

RUN_ID="${1:?Usage: smoke-test.sh <run-id>}"
export KUBECONFIG="$(run_dir "$RUN_ID")/kubeconfig"

FAILURES=0
fail() {
  echo "FAIL: $1"
  FAILURES=$((FAILURES + 1))
}
pass() { echo "PASS: $1"; }

NOT_READY="$(kubectl get nodes --no-headers | awk '$2 != "Ready" { print $1 }')"
if [ -n "$NOT_READY" ]; then
  fail "nodes not Ready:"$'\n'"$NOT_READY"
else
  pass "all nodes Ready"
fi

UNHEALTHY_PODS="$(kubectl get pods -A --no-headers | grep -vE 'Running|Completed' || true)"
if [ -n "$UNHEALTHY_PODS" ]; then
  fail "pods not Running/Completed:"$'\n'"$UNHEALTHY_PODS"
else
  pass "all pods Running or Completed"
fi

UNSYNCED_APPS="$(kubectl get applications -n argocd -o json | jq -r '
  .items[] |
  select(.status.sync.status != "Synced" or .status.health.status != "Healthy") |
  "\(.metadata.name): sync=\(.status.sync.status) health=\(.status.health.status)"
')"
if [ -n "$UNSYNCED_APPS" ]; then
  fail "ArgoCD applications not Synced/Healthy:"$'\n'"$UNSYNCED_APPS"
else
  pass "all ArgoCD applications Synced and Healthy"
fi

# Ingress checks only run when the tunnel/DNS phase has been completed
if [ -n "${RTS_TEST_DOMAIN:-}" ]; then
  DOMAIN="$(cluster_name "$RUN_ID").$RTS_TEST_DOMAIN"
  for host in argocd grafana; do
    STATUS="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://$host.$DOMAIN" || echo "connection failed")"
    # Any HTTP response < 500 proves DNS, TLS, the tunnel and the backing
    # service all work (login pages redirect, hence 2xx/3xx both fine)
    case "$STATUS" in
      2*|3*|401|403) pass "https://$host.$DOMAIN responds ($STATUS)" ;;
      *) fail "https://$host.$DOMAIN returned: $STATUS" ;;
    esac
  done
fi

echo
if [ "$FAILURES" -gt 0 ]; then
  echo "$FAILURES check(s) failed"
  exit 1
fi
echo "All checks passed"
