#!/usr/bin/env bash
# Destroys everything a test run created: Hetzner cluster (servers, network,
# firewall, ssh key via hetzner-k3s), Cloudflare DNS records and tunnel.
# Enumerates resources by the rts-<run-id> naming convention rather than
# relying on local state, so it also works for runs it didn't create.
#
# Usage: agent/teardown.sh <run-id>
#        agent/teardown.sh --list    # show all rts-* cloud resources (orphan check)

source "$(dirname "$0")/common.sh"

if [ "${1:-}" = "--list" ]; then
  require_env HCLOUD_TOKEN
  echo "# Hetzner servers (rts-*):"
  curl -s -H "Authorization: Bearer $HCLOUD_TOKEN" \
    "https://api.hetzner.cloud/v1/servers?per_page=50" |
    jq -r '.servers[].name | select(startswith("rts-"))'
  if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
    echo "# Cloudflare tunnels (rts-*):"
    cf_api GET "/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel?is_deleted=false&per_page=100" |
      jq -r '.result[].name | select(startswith("rts-"))'
    echo "# Cloudflare DNS records (rts-*):"
    cf_api GET "/zones/$CLOUDFLARE_ZONE_ID/dns_records?per_page=100" |
      jq -r '.result[].name | select(contains("rts-"))'
  fi
  exit 0
fi

RUN_ID="${1:?Usage: teardown.sh <run-id> | --list}"
NAME="$(cluster_name "$RUN_ID")"

echo "# Deleting Hetzner cluster $NAME..."
generate_cluster_config "$RUN_ID"
# delete prompts for the cluster name as confirmation, even with
# protect_against_deletion: false -- pipe it in to stay headless
echo "$NAME" | hetzner-k3s delete --config "$(run_dir "$RUN_ID")/cluster_config.yaml"

if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
  require_env CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_ZONE_ID RTS_TEST_DOMAIN

  echo "# Deleting DNS records under $NAME.$RTS_TEST_DOMAIN..."
  cf_api GET "/zones/$CLOUDFLARE_ZONE_ID/dns_records?per_page=100" |
    jq -r ".result[] | select(.name | endswith(\"$NAME.$RTS_TEST_DOMAIN\")) | .id" |
    while read -r record_id; do
      cf_api DELETE "/zones/$CLOUDFLARE_ZONE_ID/dns_records/$record_id" > /dev/null
    done

  echo "# Deleting tunnel $NAME..."
  TUNNEL_ID="$(cf_api GET "/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel?name=$NAME&is_deleted=false" |
    jq -r '.result[0].id // empty')"
  if [ -n "$TUNNEL_ID" ]; then
    # Stale connections block deletion if the cluster died uncleanly
    cf_api DELETE "/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/connections" > /dev/null || true
    cf_api DELETE "/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID" > /dev/null
  else
    echo "  (no tunnel named $NAME found)"
  fi
fi

rm -rf "$(run_dir "$RUN_ID")"
echo "Teardown of $NAME complete. Run 'agent/teardown.sh --list' to verify nothing is left."
