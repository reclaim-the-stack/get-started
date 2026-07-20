#!/usr/bin/env bash
# Headless replacement for the `cloudflared tunnel login` flow in the README.
# Creates a Cloudflare tunnel named rts-<run-id> via the API, adds a wildcard
# DNS record *.rts-<run-id>.$RTS_TEST_DOMAIN pointing at it, and seals the
# tunnel credentials into platform/cloudflared/templates/tunnel-credentials.yaml.
#
# Requires the cluster to be up with the sealed-secrets controller running
# (ie. after `kubectl create -f argocd-root.yaml` has synced).
#
# Usage: agent/create-tunnel.sh <run-id>

source "$(dirname "$0")/common.sh"

RUN_ID="${1:?Usage: create-tunnel.sh <run-id>}"
require_env CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_ZONE_ID RTS_TEST_DOMAIN

NAME="$(cluster_name "$RUN_ID")"
DOMAIN="$NAME.$RTS_TEST_DOMAIN"
DIR="$(run_dir "$RUN_ID")"
mkdir -p "$DIR"

if [ -f "$DIR/kubeconfig" ]; then
  export KUBECONFIG="$DIR/kubeconfig"
fi

# Supplying our own tunnel secret lets us construct the credentials file
# without the browser-interactive `cloudflared tunnel login` step.
TUNNEL_SECRET="$(openssl rand -base64 32)"
TUNNEL_ID="$(
  cf_api POST "/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel" --data "$(
    jq -n --arg name "$NAME" --arg secret "$TUNNEL_SECRET" \
      '{name: $name, tunnel_secret: $secret, config_src: "local"}'
  )" | jq -r '.result.id'
)"

jq -n --arg a "$CLOUDFLARE_ACCOUNT_ID" --arg s "$TUNNEL_SECRET" --arg t "$TUNNEL_ID" \
  '{AccountTag: $a, TunnelSecret: $s, TunnelID: $t}' > "$DIR/tunnel-credentials.json"

cf_api POST "/zones/$CLOUDFLARE_ZONE_ID/dns_records" --data "$(
  jq -n --arg name "*.$DOMAIN" --arg content "$TUNNEL_ID.cfargotunnel.com" \
    '{type: "CNAME", name: $name, content: $content, proxied: true}'
)" > /dev/null

kubectl create secret generic tunnel-credentials --dry-run=client \
  --from-file=credentials.json="$DIR/tunnel-credentials.json" \
  -o yaml | kubeseal -o yaml > "$REPO_ROOT/platform/cloudflared/templates/tunnel-credentials.yaml"

echo "Created tunnel $NAME ($TUNNEL_ID) with DNS *.$DOMAIN -> $TUNNEL_ID.cfargotunnel.com"
echo "Sealed credentials written to platform/cloudflared/templates/tunnel-credentials.yaml"
echo
echo "Remaining manual steps from the README's cloudflared section:"
echo "  1. mv platform-applications/disabled/cloudflared.yaml platform-applications/"
echo "  2. In platform/cloudflared/config.yaml: set 'tunnel: $NAME' and replace example.com with $DOMAIN"
echo "  3. Commit + push, then sync the platform application"
