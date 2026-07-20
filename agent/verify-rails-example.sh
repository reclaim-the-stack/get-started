#!/usr/bin/env bash
# End-to-end verification of rails-example: exercises Postgres (post create),
# Redis+Sidekiq (link title resolution job), and Elasticsearch (search).
set -euo pipefail

RUN_ID="${1:?Usage: verify-rails-example.sh <run-id>}"
source "$(dirname "$0")/common.sh"
require_env RTS_TEST_DOMAIN
BASE="https://rails-example.$(cluster_name "$RUN_ID").$RTS_TEST_DOMAIN"
JAR="$(mktemp)"
STAMP="e2e-$(date +%s)"
FAIL=0

req() { curl -s -b "$JAR" -c "$JAR" --max-time 20 "$@"; }
token_from() { grep -o 'name="authenticity_token" value="[^"]*"' <<<"$1" | head -1 | sed 's/.*value="//;s/"//'; }

# 1. Create a post (Postgres write + Redis cache path)
form=$(req "$BASE/posts/new?cb=$RANDOM")
token=$(token_from "$form")
[ -n "$token" ] || { echo "FAIL: no CSRF token on /posts/new"; exit 1; }
status=$(req -o /dev/null -w '%{http_code}' -X POST "$BASE/posts" \
  --data-urlencode "authenticity_token=$token" \
  --data-urlencode "post[title]=Test post $STAMP" \
  --data-urlencode "post[body]=Created by automated verification run $RUN_ID")
if [ "$status" = "302" ]; then echo "PASS: post created (302)"; else echo "FAIL: post create returned $status"; FAIL=1; fi

# 2. Post appears on index (Postgres read)
if req "$BASE/posts?cb=$RANDOM" | grep -q "$STAMP"; then
  echo "PASS: post visible on index"
else
  echo "FAIL: post not on index"; FAIL=1
fi

# 3. Create a link -> sidekiq job resolves its title asynchronously
form=$(req "$BASE/links/new?cb=$RANDOM")
token=$(token_from "$form")
status=$(req -o /dev/null -w '%{http_code}' -X POST "$BASE/links" \
  --data-urlencode "authenticity_token=$token" \
  --data-urlencode "link[url]=https://reclaim-the-stack.com")
if [ "$status" = "302" ]; then echo "PASS: link created (302)"; else echo "FAIL: link create returned $status"; FAIL=1; fi

# Sidekiq should replace the bare URL with the fetched page title
resolved=""
for i in $(seq 1 20); do
  page=$(req "$BASE/links?cb=$RANDOM$i")
  if grep -qi "reclaim the stack" <<<"$page"; then resolved=yes; break; fi
  sleep 5
done
if [ "$resolved" = "yes" ]; then
  echo "PASS: sidekiq resolved link title"
else
  echo "FAIL: link title not resolved after 100s"; FAIL=1
fi

# 4. Search finds the post (Elasticsearch)
found=""
for i in $(seq 1 12); do
  if req "$BASE/search?query=$STAMP&cb=$RANDOM$i" | grep -q "$STAMP"; then found=yes; break; fi
  sleep 5
done
if [ "$found" = "yes" ]; then
  echo "PASS: elasticsearch search finds the post"
else
  echo "FAIL: search does not find the post after 60s"; FAIL=1
fi

rm -f "$JAR"
[ "$FAIL" = "0" ] && echo "ALL APP CHECKS PASSED" || exit 1
