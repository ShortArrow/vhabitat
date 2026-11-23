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

# Without the requirement Hugo fetches the theme's latest version, so a go.mod that lost it would still build (ADR-0003 pins it).
grep -q '^require github\.com/ShortArrow/hugo-theme-bestiary v[0-9]' "$root/go.mod" || fail "go.mod does not pin hugo-theme-bestiary"
hugo --panicOnWarning -s "$root" -d "$out" >/dev/null
awk -f "$root/tests/seal-contrast.awk" "$root/config/_default/params.toml" >/dev/null || fail "a kind's seal is too faint against the paper, by day or by night: $(awk -f "$root/tests/seal-contrast.awk" "$root/config/_default/params.toml")"
home=$out/index.html

[ "$(sections "$home")" = "Origins,Browser Extensions,IDE and Programming Editors,Playgrounds,Singles" ] || fail "home index sections: $(sections "$home")"
has "$home" 'Fantastic Vimmer Software and Where to Find Them'
grep -q '<link rel="icon" type="image/svg+xml" href="/favicon\.[0-9a-f]*\.svg"' "$home" || fail "home links no favicon"
has "$home" 'googletagmanager.com/gtag/js?id=G-8HP6ECSQKQ'
grep -A3 '<footer' "$home" | grep -q 'href="/privacy/">Privacy policy</a>' || fail "home has no footer link to the privacy policy"
grep -A6 '<footer' "$home" | grep -q 'href="/kind/">Kinds</a>' || fail "home has no footer link to the kinds"

for page in "$out"/*/*/index.html; do
  case $page in "$out"/kind/*) continue ;; esac
  grep -q 'class="bestiary-field-label">Kind<' "$page" || fail "$page has no kind"
done

has "$out/browser/firenvim/index.html" '<a class="bestiary-choice" href="/kind/parasite/"'
has "$out/kind/mimic/index.html" 'href="/ide/ideavim/"'
for entry in browser/firenvim browser/ghosttext; do
  has "$out/$entry/index.html" '<figure class="bestiary-plate">'
done
has "$out/ide/ideavim/index.html" '<figure class="bestiary-plate bestiary-plate-wanted">'
grep -A2 'class="bestiary-field-label">Last sighted<' "$out/browser/firenvim/index.html" | grep -q '<time datetime="20[0-9][0-9]-' || fail "Firenvim shows no date it was last sighted"
has "$out/kind/index.html" 'href="/kind/symbiont/"'
has "$out/browser/firenvim/index.html" '<a href="https://github.com/glacambre/firenvim">GitHub repository</a>'
has "$out/playgrouds/index.html" 'url=https://vhabitat.shortarrow.jp/playgrounds/'
# Every measurement the page runs, including the beacon Cloudflare injects, is named in the privacy policy.
for measurement in 'Google Analytics' 'Cloudflare Web Analytics'; do
  has "$out/privacy/index.html" "$measurement"
done
# Links and search results from before /privacy/ became the address still reach the page.
has "$out/privacypolicy/index.html" 'url=https://vhabitat.shortarrow.jp/privacy/'
# Cloudflare's bot detection can leave a cf_clearance cookie that none of the site's own scripts sets.
has "$out/privacy/index.html" 'cf_clearance'

echo ok
