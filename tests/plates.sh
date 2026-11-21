#!/bin/sh
# Checks every entry's plate.svg with tests/plate_check.py, and checks that the checker refuses SVGs that could run script
# or reach outside the drawing when the theme inlines them into a page. Needs python3 (or $PYTHON). Exits non-zero on the first failed check.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
python=${PYTHON:-python3}
check() { "$python" -I "$root/tests/plate_check.py" "$@"; }

fail() { echo "FAIL: $1" >&2; exit 1; }

find "$root/content" -name plate.svg >"$work/plates"
[ -s "$work/plates" ] || fail "no plate.svg was found"
# shellcheck disable=SC2046
check $(cat "$work/plates") || fail "a plate is refused"

# Every file in a page bundle is published as it is, and the theme picks the plate by resource name, which front matter
# can give any file. So content holds only pages and files named plate.svg.
strays() { find "$1" -type f ! -name '*.md' ! -name plate.svg; }
[ -z "$(strays "$root/content")" ] || fail "content holds files other than pages and plates: $(strays "$root/content")"
mkdir -p "$work/content/en/sec/entry"
: >"$work/content/en/sec/entry/index.md"
: >"$work/content/en/sec/entry/drawing.svg"
: >"$work/content/en/sec/entry/Plate.SVG"
[ "$(strays "$work/content" | wc -l)" -eq 2 ] || fail "stray files went unnoticed: $(strays "$work/content")"

# What the theme inlines is what counts, so check the plates in the built pages too.
hugo --panicOnWarning -s "$root" -d "$work/site" >/dev/null
# shellcheck disable=SC2046
inlined=$(check --pages $(find "$work/site" -name '*.html')) || fail "a page inlines a refused plate"
[ "$inlined" -gt 0 ] || fail "no inlined plate was found in the built pages"
plate() { printf '<html><body><figure class="bestiary-plate">\n  %s\n  <figcaption>A caption</figcaption>\n</figure></body></html>\n' "$1" >"$work/page.html"; }
plate '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"><path d="M0 0" stroke="currentColor"/></svg>'
[ "$(check --pages "$work/page.html")" = 1 ] || fail "the checker refused a page with a plain plate"
plate '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>'
if check --pages "$work/page.html" >/dev/null 2>&1; then fail "the checker accepted a page that inlines a script"; fi

ok='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10" fill="none" stroke="currentColor">'
refuse() { # refuse <name> <svg>
  printf '%s\n' "$2" >"$work/$1.svg"
  if check "$work/$1.svg" 2>/dev/null; then fail "the checker accepted $1"; fi
}

refuse script "$ok<script>alert(1)</script></svg>"
refuse handler "$ok<path d=\"M0 0\" onload=\"alert(1)\"/></svg>"
refuse handler-upper "$ok<path d=\"M0 0\" ONLOAD=\"alert(1)\"/></svg>"
refuse foreign-object "$ok<foreignObject><div xmlns=\"http://www.w3.org/1999/xhtml\">x</div></foreignObject></svg>"
refuse use-href "$ok<use href=\"data:image/svg+xml,x#a\"/></svg>"
refuse xlink-href '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 1 1"><a xlink:href="javascript:alert(1)"><path d="M0 0"/></a></svg>'
refuse html-script "$ok<h:script xmlns:h=\"http://www.w3.org/1999/xhtml\">alert(1)</h:script></svg>"
refuse style-element "$ok<style>path{fill:url(https://example.com/x)}</style></svg>"
refuse style-attribute "$ok<path d=\"M0 0\" style=\"fill:red\"/></svg>"
refuse paint-url "$ok<path d=\"M0 0\" fill=\"url(https://example.com/x.svg#a)\"/></svg>"
refuse paint-colour "$ok<path d=\"M0 0\" fill=\"#ff0000\"/></svg>"
refuse entity '<!DOCTYPE svg [<!ENTITY e "x">]><svg xmlns="http://www.w3.org/2000/svg"><title>&e;</title></svg>'
refuse comment "$ok<!--><script>alert(1)</script>--></svg>"
refuse processing-instruction "$ok<?x a><script>alert(1)</script>?></svg>"
refuse cdata "$ok<title><![CDATA[x]]></title></svg>"
refuse stray-text "${ok}x<path d=\"M0 0\"/></svg>"
refuse not-svg '<html xmlns="http://www.w3.org/1999/xhtml"><script>alert(1)</script></html>'
refuse not-xml "$ok<path d=\"M0 0\"></svg>"

# The theme inlines the file's bytes into a UTF-8 page, so a plate the checker reads in any other encoding
# can spell markup the checker never sees. These title characters are "<script>" when their UTF-16LE bytes are read as UTF-8.
printf '%s\n' "$ok<title>猼牣灩㹴污牥⡴⤱⼼捳楲瑰‾</title></svg>" | iconv -f UTF-8 -t UTF-16 >"$work/utf-16.svg"
if check "$work/utf-16.svg" 2>/dev/null; then fail "the checker accepted utf-16"; fi
refuse declared-latin-1 "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>$ok</svg>"
printf '\357\273\277%s\n' "$ok</svg>" >"$work/bom.svg"
if check "$work/bom.svg" 2>/dev/null; then fail "the checker accepted a byte order mark"; fi
printf '%s\000\n' "$ok</svg>" >"$work/nul.svg"
if check "$work/nul.svg" 2>/dev/null; then fail "the checker accepted a NUL byte"; fi
printf '%s\377\n' "$ok</svg>" >"$work/not-utf-8.svg"
if check "$work/not-utf-8.svg" 2>/dev/null; then fail "the checker accepted bytes that are not UTF-8"; fi

echo ok
