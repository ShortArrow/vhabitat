#!/bin/sh
# Runs scripts/sightings.sh against fixture entries, with a stub gh that answers from fixture files,
# and checks which entries it dates. Needs GNU sed, like the script. Exits non-zero on the first failed check.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
field() { sed -n "s/^  $2: //p" "$work/content/en/$1"; }

mkdir -p "$work/scripts" "$work/bin" "$work/answers" "$work/content/en/sec/bundled"
cp "$root/scripts/sightings.sh" "$work/scripts/"

# The stub answers `gh api repos/<owner>/<repo>/commits...` with answers/<owner>_<repo>, and fails when there is none.
cat >"$work/bin/gh" <<'EOF'
#!/bin/sh
repo=$(printf '%s' "$2" | sed 's#^repos/\([^/]*\)/\([^/]*\)/.*#\1_\2#')
[ -f "$GH_ANSWERS/$repo" ] || exit 1
cat "$GH_ANSWERS/$repo"
EOF
chmod +x "$work/bin/gh"

entry() { # entry <path> <url> [lastsighted]
  {
    echo '---'
    echo 'title: "Fixture"'
    echo 'params:'
    echo '  kind: kin'
    [ -z "${3:-}" ] || echo "  lastsighted: $3"
    echo '  sightings:'
    echo '    - label: "GitHub repository"'
    echo "      url: $2"
    echo '---'
  } >"$work/content/en/$1"
}
answer() { printf '%s\n' "$2" >"$work/answers/$1"; }

entry sec/dated.md https://github.com/o/dated 2020-01-01
answer o_dated 2026-05-06T07:08:09Z
entry sec/undated.md https://github.com/o/undated
answer o_undated 2026-02-03T00:00:00Z
entry sec/offline.md https://github.com/o/offline 2020-01-01
entry sec/elsewhere.md https://gitlab.com/o/elsewhere 2020-01-01
answer o_elsewhere 2026-01-01T00:00:00Z
entry sec/bundled/index.md https://github.com/o/bundled 2020-01-01
answer o_bundled 2026-03-04T00:00:00Z
entry sec/empty.md https://github.com/o/empty 2020-01-01
answer o_empty null
entry sec/odd.md https://github.com/o/odd 2020-01-01
answer o_odd '2026/01/02 & more'
entry sec/lines.md https://github.com/o/lines 2020-01-01
answer o_lines "$(printf '2026-01-02\n2026-01-03')"
entry sec/_index.md https://github.com/o/index
answer o_index 2026-01-01T00:00:00Z

GH_ANSWERS=$work/answers PATH="$work/bin:$PATH" sh "$work/scripts/sightings.sh" 2>"$work/stderr" || fail "the script failed: $(cat "$work/stderr")"

[ "$(field sec/dated.md lastsighted)" = 2026-05-06 ] || fail "a dated entry was not redated: $(field sec/dated.md lastsighted)"
[ "$(sed -n '5p' "$work/content/en/sec/undated.md")" = '  lastsighted: 2026-02-03' ] || fail "an undated entry got no date before its sightings"
[ "$(field sec/offline.md lastsighted)" = 2020-01-01 ] || fail "an entry whose repository did not answer was changed"
grep -q 'skipped o/offline' "$work/stderr" || fail "an unanswered repository was not reported"
for odd in empty odd lines; do
  [ "$(field sec/$odd.md lastsighted)" = 2020-01-01 ] || fail "an entry whose repository answered no date was changed: $(field sec/$odd.md lastsighted)"
  grep -q "skipped o/$odd" "$work/stderr" || fail "a repository that answered no date was not reported"
done
[ "$(field sec/elsewhere.md lastsighted)" = 2020-01-01 ] || fail "an entry without a GitHub repository was changed"
[ -z "$(field sec/_index.md lastsighted)" ] || fail "a section's _index.md was dated"
[ "$(field sec/bundled/index.md lastsighted)" = 2026-03-04 ] || fail "an entry in a page bundle was not redated: $(field sec/bundled/index.md lastsighted)"

# With no page bundle, the bundle glob matches nothing and must not be read as a file.
rm -r "$work/content/en/sec/bundled"
GH_ANSWERS=$work/answers PATH="$work/bin:$PATH" sh "$work/scripts/sightings.sh" 2>"$work/stderr" || fail "the script failed without bundles: $(cat "$work/stderr")"
grep -v '^skipped ' "$work/stderr" >&2 && fail "the script complained without bundles"

echo ok
