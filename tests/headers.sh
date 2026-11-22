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

csp=$(header Content-Security-Policy)
[ -n "$csp" ] || fail "every page should send a Content-Security-Policy"
# directive <name>: the sources the policy lists for one directive, space-separated with a space at each end.
directive() { printf '%s' "$csp" | tr ';' '\n' | sed -n "s/^ *$1 \(.*\)/ \1 /p"; }
for d in "object-src 'none'" "base-uri 'self'" "frame-ancestors 'none'" "form-action 'self'"; do
  case " $(directive "${d%% *}")" in *" ${d#* } "*) ;; *) fail "the policy lacks $d" ;; esac
done
# The origins Google lists for Analytics without Ads features (developers.google.com/tag-platform/security/guides/csp).
for origin in https://*.google-analytics.com https://*.google.com https://*.googletagmanager.com; do
  case $(directive connect-src) in *" $origin "*) ;; *) fail "connect-src lacks $origin, where Google Analytics sends its hits" ;; esac
done
# Cloudflare injects its Web Analytics beacon into the pages it serves, so the build never shows it. The injected
# beacon reports to this site's own /cdn-cgi/rum, so connect-src needs only 'self'; cloudflareinsights.com is where a
# beacon embedded by hand reports (developers.cloudflare.com/web-analytics/faq/).
case $(directive script-src) in *" https://static.cloudflareinsights.com "*) ;; *) fail "script-src lacks https://static.cloudflareinsights.com, where Cloudflare Web Analytics loads its beacon" ;; esac
case $(directive connect-src) in *" 'self' "*) ;; *) fail "connect-src lacks 'self', where Cloudflare Web Analytics sends its beacons" ;; esac
case $(directive connect-src) in *" https://cloudflareinsights.com "*) fail "connect-src allows https://cloudflareinsights.com, which only a beacon embedded by hand needs" ;; esac

# Every script a page runs must be allowed: inline ones by the hash of their text, external ones by their origin.
script_src=$(directive script-src)
missing=$(perl -e '
  use Digest::SHA qw(sha256_base64);
  my ($allowed, %missing) = (shift);
  for my $page (@ARGV) {
    open my $fh, "<:raw", $page or die "$page: $!";
    my $html = do { local $/; <$fh> };
    while ($html =~ m{<script\b([^>]*)>(.*?)</script>}gs) {
      my ($attributes, $text) = ($1, $2);
      my $source;
      if ($attributes =~ m{\bsrc=["\x27]?(https?://[^/"\x27 >]+)}) { $source = $1 }
      elsif ($attributes =~ m{\bsrc=}) { $source = "\x27self\x27" }
      else { my $h = sha256_base64($text); $h .= "=" x (-length($h) % 4); $source = "\x27sha256-$h\x27" }
      my $wildcard = $source =~ s{^(https?://)[^.]+(\..+)$}{$1*$2}r;
      $missing{$source} = 1 unless index($allowed, " $source ") >= 0 || index($allowed, " $wildcard ") >= 0;
    }
  }
  print join(" ", sort keys %missing);
' "$script_src" $(find "$out" -name '*.html'))
[ -z "$missing" ] || fail "script-src does not allow scripts the pages run: $missing"

echo ok
