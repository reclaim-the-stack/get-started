#!/usr/bin/env bash
# Adds proxied CNAME records pointing at the run's tunnel, one per hostname:
#
#   agent/add-dns.sh <run-id> <hostname> [<hostname>...]
#   eg: agent/add-dns.sh abc123 rails-example
#
# Explicit per-hostname records (rather than a wildcard) keep edge TLS
# working on any Cloudflare plan: multi-level wildcards need an ACM
# subscription and even then take a long time to get certificates issued,
# while specific proxied hostnames are covered within seconds.

source "$(dirname "$0")/common.sh"

RUN_ID="${1:?Usage: add-dns.sh <run-id> <hostname> [<hostname>...]}"
shift
[ $# -ge 1 ] || { echo "Usage: add-dns.sh <run-id> <hostname> [<hostname>...]" >&2; exit 1; }
require_env CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_ZONE_ID RTS_TEST_DOMAIN

NAME="$(cluster_name "$RUN_ID")"
TUNNEL_ID="$(cf_api GET "/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel?name=$NAME&is_deleted=false" | jq -r '.result[0].id // empty')"
[ -n "$TUNNEL_ID" ] || { echo "Error: no tunnel named $NAME found -- run create-tunnel.sh first" >&2; exit 1; }

for host in "$@"; do
  payload="$(jq -n --arg name "$host.$NAME.$RTS_TEST_DOMAIN" --arg content "$TUNNEL_ID.cfargotunnel.com" \
    '{type: "CNAME", name: $name, content: $content, proxied: true}')"
  cf_api POST "/zones/$CLOUDFLARE_ZONE_ID/dns_records" --data "$payload" | jq -r '.result.name + " -> " + .result.content'
done
