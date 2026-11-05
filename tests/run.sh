#!/bin/sh
# Builds the site and checks what it renders.
# Needs hugo on PATH (the version Workers Builds uses is HUGO_VERSION). Exits non-zero on the first failed check.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
has() { grep -q -- "$2" "$1" || fail "$1 lacks $2"; }
sections() { grep -o 'class="bestiary-index-section"[^>]*>[^<]*<a [^>]*>[^<]*' "$1" | sed 's/.*>//' | paste -sd, -; }

hugo --panicOnWarning -s "$root" -d "$out" >/dev/null
home=$out/index.html

[ "$(sections "$home")" = "Origins,Browser Extensions,IDE and Programming Editors,Playgrounds,Singles" ] || fail "home index sections: $(sections "$home")"
has "$home" 'Fantastic Vimmer Software and Where to Find Them'
has "$home" 'googletagmanager.com/gtag/js?id=G-8HP6ECSQKQ'
grep -A3 '<footer' "$home" | grep -q 'href="/privacypolicy/">Privacy policy</a>' || fail "home has no footer link to the privacy policy"

for page in "$out"/*/*/index.html; do
  case $page in "$out"/kind/*) continue ;; esac
  grep -q 'class="bestiary-field-label">Kind<' "$page" || fail "$page has no kind"
done

has "$out/browser/firenvim/index.html" '<a class="bestiary-choice" href="/kind/parasite/"'
has "$out/kind/mimic/index.html" 'href="/ide/ideavim/"'
has "$out/kind/index.html" 'href="/kind/symbiont/"'
has "$out/browser/firenvim/index.html" '<a href="https://github.com/glacambre/firenvim">GitHub repository</a>'
has "$out/playgrouds/index.html" 'url=https://vhabitat.shortarrow.jp/playgrounds/'

echo ok
