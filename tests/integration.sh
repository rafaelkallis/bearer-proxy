#!/bin/sh
# Integration tests for bearer-proxy.
# Requires: docker (with compose plugin), curl.
# The image must be built and tagged as bearer-proxy:test before running.

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="$TESTS_DIR/docker-compose.test.yml"
PROXY_PORT=18080
HEALTH_PORT=19494
VALID_KEY="test-key-abc123"

PASS=0
FAIL=0

pass() { printf 'PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

cleanup() {
  docker compose -f "$COMPOSE_FILE" down --volumes --remove-orphans 2>/dev/null || true
}
trap cleanup EXIT

# ── start services ───────────────────────────────────────────────────────────
printf 'Starting services...\n'
docker compose -f "$COMPOSE_FILE" up -d

printf 'Waiting for proxy...\n'
i=0
while ! curl -sf --max-time 2 "http://localhost:$HEALTH_PORT/health" >/dev/null 2>&1; do
  i=$((i + 1))
  [ "$i" -ge 30 ] && printf 'ERROR: proxy did not become healthy\n' >&2 && exit 1
  sleep 1
done
printf 'Proxy ready.\n\n'

# ── helpers ──────────────────────────────────────────────────────────────────
proxy_url() { printf 'http://localhost:%s/' "$PROXY_PORT"; }
health_url() { printf 'http://localhost:%s/health' "$HEALTH_PORT"; }

assert_status() {
  _as_name="$1"; _as_expected="$2"; shift 2
  _as_actual=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$@")
  if [ "$_as_actual" = "$_as_expected" ]; then
    pass "$_as_name"
  else
    fail "$_as_name (expected HTTP $_as_expected, got HTTP $_as_actual)"
  fi
}

assert_body_has() {
  _bh_name="$1"; _bh_pattern="$2"; shift 2
  _bh_body=$(curl -s --max-time 10 "$@")
  if printf '%s' "$_bh_body" | grep -q "$_bh_pattern"; then
    pass "$_bh_name"
  else
    fail "$_bh_name (pattern '$_bh_pattern' not found)"
    printf '    body: %s\n' "$_bh_body"
  fi
}

assert_body_not_has() {
  _bnh_name="$1"; _bnh_pattern="$2"; shift 2
  _bnh_body=$(curl -s --max-time 10 "$@")
  if printf '%s' "$_bnh_body" | grep -q "$_bnh_pattern"; then
    fail "$_bnh_name (pattern '$_bnh_pattern' unexpectedly found)"
    printf '    body: %s\n' "$_bnh_body"
  else
    pass "$_bnh_name"
  fi
}

# ── tests ────────────────────────────────────────────────────────────────────
assert_status "health check"            "200" "$(health_url)"
assert_status "valid token → 200"       "200" -H "Authorization: Bearer $VALID_KEY" "$(proxy_url)"
assert_status "invalid token → 401"     "401" -H "Authorization: Bearer wrong-key"  "$(proxy_url)"
assert_status "no auth header → 401"    "401"                                        "$(proxy_url)"
assert_status "bearer lowercase → 200"  "200" -H "Authorization: bearer $VALID_KEY" "$(proxy_url)"
assert_status "bearer uppercase → 200"  "200" -H "Authorization: BEARER $VALID_KEY" "$(proxy_url)"

assert_body_has \
  "401 body: error code is invalid_api_key" \
  '"invalid_api_key"' \
  -H "Authorization: Bearer wrong-key" "$(proxy_url)"

# traefik/whoami echoes all received headers; Authorization must not appear
assert_body_not_has \
  "Authorization header stripped from upstream" \
  "Authorization:" \
  -H "Authorization: Bearer $VALID_KEY" "$(proxy_url)"

# ── summary ──────────────────────────────────────────────────────────────────
printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
