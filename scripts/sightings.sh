#!/bin/sh
# Sets params.lastsighted in every entry to the date of the newest commit on the default branch
# of the repository its "GitHub repository" sighting links to, and leaves entries without one alone.
# Run it when entries are reviewed or a new edition is cut. Needs gh, authenticated (GH_TOKEN in Actions), and GNU sed. See docs/adr/0004.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)

repository() {
  awk '/label: "GitHub repository"/ { getline; sub(/.*url: */, ""); print; exit }' "$1" |
    sed -n 's#^https://\(www\.\)\{0,1\}github\.com/\([^/]*/[^/]*\).*#\2#p'
}

for entry in "$root"/content/en/*/*.md; do
  [ "$(basename "$entry")" = _index.md ] && continue
  repo=$(repository "$entry")
  [ -n "$repo" ] || continue
  if ! sighted=$(gh api "repos/$repo/commits?per_page=1" --jq '.[0].commit.committer.date' 2>/dev/null); then
    echo "skipped $repo: the API did not answer" >&2
    continue
  fi
  sighted=$(printf '%s' "$sighted" | cut -c1-10)
  if grep -q '^  lastsighted:' "$entry"; then
    sed -i "s/^  lastsighted: .*/  lastsighted: $sighted/" "$entry"
  else
    sed -i "0,/^  sightings:/s//  lastsighted: $sighted\n  sightings:/" "$entry"
  fi
done
