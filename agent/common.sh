#!/usr/bin/env bash
# Shared helpers for the agent test-run scripts. Source this, don't execute it.

set -euo pipefail

AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$AGENT_DIR")"

if [ -f "$REPO_ROOT/.env.local" ]; then
  set -a
  source "$REPO_ROOT/.env.local"
  set +a
fi

require_env() {
  for var in "$@"; do
    if [ -z "${!var:-}" ]; then
      echo "Missing required environment variable: $var (see .env.local.example)" >&2
      exit 1
    fi
  done
}

cluster_name() { echo "rts-$1"; }
run_dir() { echo "$AGENT_DIR/runs/$1"; }

# Renders the repo's hetzner-k3s config with per-run cluster name and
# kubeconfig path into runs/<run-id>/cluster_config.yaml. Deterministic, so
# teardown can regenerate it if lost. hetzner-k3s reads the token from the
# HCLOUD_TOKEN env var (exported above via .env.local).
generate_cluster_config() {
  local run_id="$1"
  local dir
  dir="$(run_dir "$run_id")"
  mkdir -p "$dir"
  require_env HCLOUD_TOKEN
  CLUSTER_NAME="$(cluster_name "$run_id")" KUBECONFIG_PATH="$dir/kubeconfig" \
    yq e '.cluster_name = strenv(CLUSTER_NAME) |
          .kubeconfig_path = strenv(KUBECONFIG_PATH)' \
    "$REPO_ROOT/hetzner-k3s_cluster_config.yaml" > "$dir/cluster_config.yaml"
}

# cf_api METHOD PATH [extra curl args...] -- calls the Cloudflare v4 API,
# prints the JSON response, fails loudly if .success != true.
cf_api() {
  local method="$1" path="$2"
  shift 2
  require_env CLOUDFLARE_API_TOKEN
  local response
  response="$(curl -s -X "$method" "https://api.cloudflare.com/client/v4$path" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json" "$@")"
  if [ "$(echo "$response" | jq -r '.success')" != "true" ]; then
    echo "Cloudflare API error ($method $path): $(echo "$response" | jq -c '.errors')" >&2
    return 1
  fi
  echo "$response"
}
