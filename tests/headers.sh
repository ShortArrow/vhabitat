#!/bin/sh
# Builds the site as Workers Builds does (the build.command in wrangler.jsonc) and checks the response headers
# that the built _headers file gives every page. Needs hugo on PATH, like tests/run.sh. Exits non-zero on the first failed check.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
# header <name>: the value _headers gives every path (/*), or nothing.
header() { awk -v name="$1" '/^[^ \t]/ { all = ($0 == "/*") } all && sub("^[ \t]+" name ":[ \t]*", "") { print }' "$out/_headers"; }
expect() { [ "$(header "$1")" = "$2" ] || fail "every page should send $1: $2, not: $(header "$1")"; }

hugo --minify --panicOnWarning -s "$root" -d "$out" >/dev/null
[ -f "$out/_headers" ] || fail "the build has no _headers"

expect X-Content-Type-Options nosniff
expect Referrer-Policy strict-origin-when-cross-origin
expect X-Frame-Options DENY
expect Permissions-Policy 'camera=(), microphone=(), geolocation=()'

echo ok
