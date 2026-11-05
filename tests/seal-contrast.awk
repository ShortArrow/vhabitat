# Reads config/_default/params.toml and checks that every kind's seal text keeps a contrast of at least `least`
# with its seal's background (its colour mixed 10% into the paper), by day with `color` and by night with `nightColor`.
# The paper colours are the theme's --paper tokens. The margin above WCAG AA's 4.5 allows for the worn-ink filter on seals.
function hex(s, i) { return index("0123456789abcdef", tolower(substr(s, i, 1))) - 1 }
function channel(s, i) { return hex(s, i) * 16 + hex(s, i + 1) }
function linear(v) { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ^ 2.4 }
function lum(r, g, b) { return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b) }
function ratio(a, b) { return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05) }
function seal(c, p,    r, g, b, pr, pg, pb) {
  r = channel(c, 2); g = channel(c, 4); b = channel(c, 6)
  pr = channel(p, 2); pg = channel(p, 4); pb = channel(p, 6)
  return ratio(lum(r, g, b), lum(0.1 * r + 0.9 * pr, 0.1 * g + 0.9 * pg, 0.1 * b + 0.9 * pb))
}
function check(scheme, colour, paper,    r) {
  r = seal(colour, paper)
  printf "%-10s %-5s %s %.2f\n", value, scheme, colour, r
  if (r < least) bad = 1
}
BEGIN { least = 5.5; day = "#f3ead6"; night = "#1f1914" }
/^ *value = / { value = $3; gsub(/"/, "", value) }
/^ *color = / { c = $3; gsub(/"/, "", c); check("day", c, day); seen++ }
/^ *nightColor = / { c = $3; gsub(/"/, "", c); check("night", c, night); nights++ }
END { if (seen == 0 || nights != seen) bad = 1; exit bad }
