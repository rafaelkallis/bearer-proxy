#!/bin/sh
# Unit tests for generate-api-keys-map.sh.
# No external dependencies — runs directly on the CI runner.

PASS=0
FAIL=0

pass() { printf 'PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

assert_eq() {
  if [ "$2" = "$3" ]; then
    pass "$1"
  else
    fail "$1"
    printf '      expected: %s\n' "$2"
    printf '      actual:   %s\n' "$3"
  fi
}

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/generate-api-keys-map.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# run_ok <keys_file> <map_file> — runs the script, expects success
run_ok() {
  UPSTREAM="http://upstream:80" API_KEYS_FILE="$1" API_KEYS_MAP_FILE="$2" \
    sh "$SCRIPT" >/dev/null 2>&1
}

# run_exit <upstream> <keys_file> <map_file> — returns the exit code
run_exit() {
  _re_code=0
  UPSTREAM="$1" API_KEYS_FILE="$2" API_KEYS_MAP_FILE="$3" \
    sh "$SCRIPT" >/dev/null 2>&1 || _re_code=$?
  echo "$_re_code"
}

count_lines() { grep -c '' "$1" 2>/dev/null || echo 0; }

# ── Test 1: normal key produces correct map entry ────────────────────────────
printf 'myapikey123\n' > "$WORK/t1_keys"
run_ok "$WORK/t1_keys" "$WORK/t1_map"
assert_eq "normal key: map entry format" \
  '~^[Bb][Ee][Aa][Rr][Ee][Rr]\s+myapikey123$    1;' \
  "$(cat "$WORK/t1_map")"

# ── Test 2: special characters are regex-escaped ─────────────────────────────
# key: a.b^c$d*e+f?g{h}i[j]k(l)m\n|o  (the \n is a literal backslash-n)
printf 'a.b^c$d*e+f?g{h}i[j]k(l)m\\n|o\n' > "$WORK/t2_keys"
run_ok "$WORK/t2_keys" "$WORK/t2_map"
assert_eq "special chars: escaped in map entry" \
  '~^[Bb][Ee][Aa][Rr][Ee][Rr]\s+a\.b\^c\$d\*e\+f\?g\{h\}i\[j\]k\(l\)m\\n\|o$    1;' \
  "$(cat "$WORK/t2_map")"

# ── Test 3: CRLF line endings are stripped ───────────────────────────────────
printf 'key1\r\nkey2\r\n' > "$WORK/t3_keys"
run_ok "$WORK/t3_keys" "$WORK/t3_map"
assert_eq "CRLF stripped: entry has no carriage return" \
  '~^[Bb][Ee][Aa][Rr][Ee][Rr]\s+key1$    1;' \
  "$(head -n 1 "$WORK/t3_map")"
assert_eq "CRLF: 2 entries loaded" "2" "$(count_lines "$WORK/t3_map")"

# ── Test 4: comment lines are skipped ────────────────────────────────────────
printf '# comment\nrealkey\n# another\n' > "$WORK/t4_keys"
run_ok "$WORK/t4_keys" "$WORK/t4_map"
assert_eq "comments skipped: 1 entry in map" "1" "$(count_lines "$WORK/t4_map")"

# ── Test 5: blank lines are skipped ──────────────────────────────────────────
printf '\nkey1\n\nkey2\n\n' > "$WORK/t5_keys"
run_ok "$WORK/t5_keys" "$WORK/t5_map"
assert_eq "blank lines skipped: 2 entries in map" "2" "$(count_lines "$WORK/t5_map")"

# ── Test 6: missing UPSTREAM exits 1 ─────────────────────────────────────────
printf 'somekey\n' > "$WORK/t6_keys"
assert_eq "missing UPSTREAM: exits 1" "1" \
  "$(run_exit "" "$WORK/t6_keys" "$WORK/t6_map")"

# ── Test 7: missing API keys file exits 1 ────────────────────────────────────
assert_eq "missing keys file: exits 1" "1" \
  "$(run_exit "http://upstream" "$WORK/nonexistent" "$WORK/t7_map")"

# ── Test 8: all-comment keys file exits 1 ────────────────────────────────────
printf '# only a comment\n' > "$WORK/t8_keys"
assert_eq "all-comment keys file: exits 1" "1" \
  "$(run_exit "http://upstream" "$WORK/t8_keys" "$WORK/t8_map")"

# ── Test 9: map file has mode 600 ────────────────────────────────────────────
printf 'somekey\n' > "$WORK/t9_keys"
run_ok "$WORK/t9_keys" "$WORK/t9_map"
assert_eq "map file permissions: 600" "600" "$(stat -c '%a' "$WORK/t9_map")"

# ── summary ──────────────────────────────────────────────────────────────────
printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
