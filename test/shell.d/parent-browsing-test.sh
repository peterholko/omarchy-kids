#!/bin/bash
#
# `omarchy-parent browsing` keeps a child install's browsing history where the
# kid cannot erase it, and answers which YouTube videos were watched. DNS can't:
# HTTPS hides the URL. The extractors, the reports, and the policy writers run
# extracted against a scratch tree; the real command runs as namespaced root.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

browsing="$ROOT/lib/parent/omarchy_parent/browsing/command.sh"
parent="$ROOT/bin/omarchy-parent"
service="$ROOT/default/parent/omarchy-parent-browsing.service"
timer="$ROOT/default/parent/omarchy-parent-browsing.timer"

grep -q '^# omarchy:summary=Keep a child install' "$browsing" || fail "omarchy-parent-browsing announces itself as a feature"
grep -q '^# omarchy:requires-sudo=true' "$browsing" || fail "browsing runs as root"
[[ $(OMARCHY_PATH="$ROOT" bash "$parent" --help) == *"browsing  Keep a child install"* ]] || fail "omarchy-parent lists browsing as a feature"
grep -Fq 'source "$OMARCHY_PATH/lib/parent/omarchy_parent/core/parent.sh"' "$browsing" || fail "browsing reads parent.conf through the shared helper"
grep -qx 'ExecStart=/usr/bin/omarchy-parent-browsing collect' "$service" || fail "the service runs the collector"
grep -q 'ConditionPathExistsGlob=/var/lib/omarchy/parent/\*/browsing/enabled' "$service" || fail "the service only runs when an account has it on"
grep -qx 'OnUnitActiveSec=1min' "$timer" || fail "the timer runs every minute"
pass "browsing ships as a feature command with its collection units"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export OMARCHY_PATH="$ROOT" OMARCHY_PARENT_SYSROOT="$tmp/root" OMARCHY_PARENT_STATE_DIR="$tmp/state"
mkdir -p "$tmp/state" "$tmp/root"

eval "$(sed -n '/^SYSROOT=/,/^# --- end browsing ---$/p' "$browsing")"

# A Chromium-shaped History db, times in microseconds since 1601.
build_chromium() {
  local path="$1"; shift
  OMARCHY_DB="$path" python3 - "$@" <<'PY'
import sqlite3, sys, datetime
con = sqlite3.connect(__import__("os").environ["OMARCHY_DB"])
con.execute("CREATE TABLE urls (id INTEGER PRIMARY KEY, url TEXT, title TEXT)")
con.execute("CREATE TABLE visits (id INTEGER PRIMARY KEY, url INTEGER, visit_time INTEGER)")
def cepoch(s): return (int(s) + 11644473600) * 1000000
for i, arg in enumerate(sys.argv[1:], start=1):
    ts, url, title = arg.split("|", 2)
    con.execute("INSERT INTO urls VALUES (?,?,?)", (i, url, title))
    con.execute("INSERT INTO visits VALUES (?,?,?)", (i, i, cepoch(ts)))
con.commit(); con.close()
PY
}
append_chromium() {
  local path="$1"; shift
  OMARCHY_DB="$path" python3 - "$@" <<'PY'
import sqlite3, sys, os
con = sqlite3.connect(os.environ["OMARCHY_DB"])
def cepoch(s): return (int(s) + 11644473600) * 1000000
for arg in sys.argv[1:]:
    ts, url, title = arg.split("|", 2)
    url_id = con.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM urls").fetchone()[0]
    visit_id = con.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM visits").fetchone()[0]
    con.execute("INSERT INTO urls VALUES (?,?,?)", (url_id, url, title))
    con.execute("INSERT INTO visits VALUES (?,?,?)", (visit_id, url_id, cepoch(ts)))
con.commit(); con.close()
PY
}
build_firefox() {
  local path="$1"; shift
  OMARCHY_DB="$path" python3 - "$@" <<'PY'
import sqlite3, sys, os
con = sqlite3.connect(os.environ["OMARCHY_DB"])
con.execute("CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url TEXT, title TEXT)")
con.execute("CREATE TABLE moz_historyvisits (id INTEGER PRIMARY KEY, place_id INTEGER, visit_date INTEGER)")
for i, arg in enumerate(sys.argv[1:], start=1):
    ts, url, title = arg.split("|", 2)
    con.execute("INSERT INTO moz_places VALUES (?,?,?)", (i, url, title))
    con.execute("INSERT INTO moz_historyvisits VALUES (?,?,?)", (i, i, int(ts) * 1000000))
con.commit(); con.close()
PY
}

t1=1788300000
cdb="$tmp/History"
build_chromium "$cdb" \
  "$t1|https://www.youtube.com/watch?v=abc123XYZ|Cats compilation - YouTube" \
  "$((t1+120))|https://www.khanacademy.org/math|Math | Khan Academy"
newest=$(extract_visits "$cdb" chromium 0 2>&1 >/dev/null)
rows=$(extract_visits "$cdb" chromium 0 2>/dev/null)
[[ $(grep -c . <<<"$rows") == 2 ]] || fail "the Chromium extractor reads every visit" "$rows"
[[ $rows == *$'\t''https://www.youtube.com/watch?v=abc123XYZ'$'\t''Cats compilation - YouTube'* ]] || fail "the Chromium extractor keeps url and title"
[[ $(head -1 <<<"$rows" | cut -f1) == "$t1" ]] || fail "the Chromium time becomes a unix epoch" "$(head -1 <<<"$rows")"
[[ -z $(extract_visits "$cdb" chromium "$newest" 2>/dev/null) ]] || fail "a rerun past the cursor takes nothing"
(( newest > 0 )) || fail "the extractor reports a newest cursor"
pass "the Chromium extractor reads new visits and advances a cursor"

fdb="$tmp/places.sqlite"
build_firefox "$fdb" "$((t1+300))|https://youtu.be/deffff999|Space documentary - YouTube"
frows=$(extract_visits "$fdb" firefox 0 2>/dev/null)
[[ $frows == "$((t1+300))"$'\t''https://youtu.be/deffff999'$'\t''Space documentary - YouTube' ]] || fail "the Firefox extractor reads a visit as a unix epoch" "$frows"
pass "the Firefox extractor reads places.sqlite"

dir="$tmp/state/kid/browsing"
mkdir -p "$dir"
cursor_set "$dir" "chromium:$cdb" 42
[[ $(cursor_get "$dir" "chromium:$cdb") == 42 ]] || fail "a cursor round-trips"
[[ $(cursor_get "$dir" "firefox:other") == 0 ]] || fail "an unknown cursor reads 0"
cursor_set "$dir" "chromium:$cdb" 99
[[ $(cursor_get "$dir" "chromium:$cdb") == 99 && $(grep -c . "$dir/cursors") == 1 ]] || fail "a cursor is rewritten in place"
pass "cursors are kept per history file"

# videos, from a canned log with the on-screen minutes joining by title.
mkdir -p "$dir"
now=$(date +%s)
printf '%s\thttps://www.youtube.com/watch?v=abc123XYZ\tCats compilation - YouTube\tchromium\n' "$((now-3600))" >"$dir/visits.tsv"
printf '%s\thttps://www.youtube.com/watch?v=abc123XYZ\tCats compilation - YouTube\tchromium\n' "$((now-1800))" >>"$dir/visits.tsv"
printf '%s\thttps://youtu.be/deffff999\tSpace documentary - YouTube\tchromium\n' "$((now-600))" >>"$dir/visits.tsv"
printf '%s\thttps://www.khanacademy.org/math\tMath\tchromium\n' "$((now-500))" >>"$dir/visits.tsv"
for m in 0 1 2; do printf '%s\tCats compilation - YouTube - Chromium\n' "$((now-3600+m*60))" >>"$dir/titles.tsv"; done
out=$(show_videos kid 7)
[[ $out == *"Cats compilation"* && $out == *"Space documentary"* ]] || fail "videos lists each watched video" "$out"
[[ $out != *"khanacademy"* && $out != *"Math"* ]] || fail "videos lists only YouTube"
[[ $out == *"2 opens"* ]] || fail "videos counts repeat opens" "$out"
[[ $out == *"3 min"* ]] || fail "videos counts on-screen minutes from the titles" "$out"
[[ $(grep -n 'Space documentary' <<<"$out" | cut -d: -f1) -lt $(grep -n 'Cats compilation' <<<"$out" | cut -d: -f1) ]] || fail "videos are most recent first" "$out"
pages=$(show_pages kid 7 100)
[[ $pages == *"khanacademy.org/math"* && $pages == *"youtube.com/watch"* ]] || fail "pages lists every page" "$pages"
[[ $(grep -c 'https://' <<<"$pages") -ge 4 ]] || fail "pages lists all visits"
pass "videos answers which YouTube videos were watched; pages lists everything"

# The browser policy in and out.
mkdir -p "$SYSROOT/etc/chromium/policies/managed" "$SYSROOT/usr/lib/firefox/distribution"
printf '{"policies":{"Preferences":{}}}\n' >"$SYSROOT/usr/lib/firefox/distribution/policies.json"
install_browser_policies
p="$SYSROOT/etc/chromium/policies/managed/omarchy-parent-browsing.json"
[[ -f $p ]] || fail "Chromium gets a managed policy"
grep -q '"IncognitoModeAvailability": 1' "$p" && grep -q '"AllowDeletingBrowserHistory": false' "$p" || fail "the policy disables private windows and forbids clearing history" "$(cat "$p")"
if command -v jq >/dev/null; then
  [[ $(jq '.policies.DisablePrivateBrowsing' "$SYSROOT/usr/lib/firefox/distribution/policies.json") == true ]] || fail "Firefox private browsing is disabled"
  [[ $(jq '.policies.Preferences' "$SYSROOT/usr/lib/firefox/distribution/policies.json") == '{}' ]] || fail "the Firefox merge keeps existing policies"
fi
remove_browser_policies
[[ ! -e $p ]] || fail "off removes the Chromium policy"
if command -v jq >/dev/null; then
  [[ $(jq '.policies | has("DisablePrivateBrowsing")' "$SYSROOT/usr/lib/firefox/distribution/policies.json") == false ]] || fail "off takes the Firefox key back out"
fi
pass "the browser is told not to offer a private window, and untold on off"

# Window titles from a stubbed hyprctl via runuser.
mkdir -p "$tmp/bin" "$tmp/root/run/user/$(id -u)/hypr/sig123"
cat >"$tmp/bin/runuser" <<'SH'
#!/bin/bash
# runuser -u NAME -- env ... hyprctl -j clients  →  print canned clients JSON
cat <<'JSON'
[{"title":"Cats compilation - YouTube - Chromium"},{"title":"Untitled - Text Editor"},{"title":""}]
JSON
SH
cat >"$tmp/bin/id" <<SH
#!/bin/bash
[[ \$1 == -u ]] && { echo $(id -u); exit 0; }
exec /usr/bin/id "\$@"
SH
if ! command -v flock >/dev/null; then
  cat >"$tmp/bin/flock" <<'SH'
#!/bin/bash
# macOS lacks util-linux flock; this test's collections run serially.
exit 0
SH
fi
chmod +x "$tmp/bin"/*
titles=$(PATH="$tmp/bin:$PATH" RUN_ROOT="$tmp/root/run/user" window_titles kid)
[[ $titles == *"Cats compilation - YouTube - Chromium"* ]] || fail "window titles come back from hyprctl" "$titles"
[[ $(grep -c . <<<"$titles") == 2 ]] || fail "an empty title is dropped"
pass "the on-screen YouTube titles are read from the kid's Hyprland"

# The collector end to end: a kid home with a Chromium profile, a YouTube
# window on screen, and then neither, all under this file's set -e.
kid_home="$tmp/kidhome"
mkdir -p "$kid_home/.config/chromium/Default" "$tmp/state/kid/browsing"
: >"$tmp/state/kid/browsing/enabled"
rm -f "$tmp/state/kid/browsing/visits.tsv" "$tmp/state/kid/browsing/titles.tsv" "$tmp/state/kid/browsing/cursors"
build_chromium "$kid_home/.config/chromium/Default/History" \
  "$((now-120))|https://www.youtube.com/watch?v=zzz999AAA|Volcano facts - YouTube" \
  "$((now-60))|https://en.wikipedia.org/wiki/Volcano|Volcano - Wikipedia"
user_home() { printf '%s\n' "$kid_home"; }
PATH="$tmp/bin:$PATH" RUN_ROOT="$tmp/root/run/user" collect_user kid
[[ $(grep -c . "$tmp/state/kid/browsing/visits.tsv") == 2 ]] || fail "the collector takes the profile's visits" "$(cat "$tmp/state/kid/browsing/visits.tsv")"
grep -q $'\tchromium$' "$tmp/state/kid/browsing/visits.tsv" || fail "the collector notes which browser"
[[ $(grep -c . "$tmp/state/kid/browsing/titles.tsv") == 1 ]] || fail "the collector keeps the YouTube title on screen once per run"
grep -q "^chromium:$kid_home/.config/chromium/Default/History" "$tmp/state/kid/browsing/cursors" || fail "the collector records a cursor per history file"
PATH="$tmp/bin:$PATH" RUN_ROOT="$tmp/root/run/user" collect_user kid
[[ $(grep -c . "$tmp/state/kid/browsing/visits.tsv") == 2 ]] || fail "a rerun takes no visit twice"
[[ $(grep -c . "$tmp/state/kid/browsing/titles.tsv") == 2 ]] || fail "a rerun adds another minute on screen"
printf '#!/bin/bash\necho "[]"\n' >"$tmp/bin/runuser"
rm -f "$tmp/state/kid/browsing/titles.tsv"
PATH="$tmp/bin:$PATH" RUN_ROOT="$tmp/root/run/user" collect_user kid || fail "the collector succeeds with no YouTube window open"
[[ ! -e $tmp/state/kid/browsing/titles.tsv ]] || fail "no window, no title row"
[[ $(stat -f %Lp "$tmp/state/kid/browsing/visits.tsv" 2>/dev/null || stat -c %a "$tmp/state/kid/browsing/visits.tsv") == 600 ]] || fail "the log is root's alone"
append_chromium "$kid_home/.config/chromium/Default/History" \
  "$((now-30))|https://school.example/fresh-assignment|Fresh assignment"
fresh_pages=$(PATH="$tmp/bin:$PATH" RUN_ROOT="$tmp/root/run/user" report_pages kid 7 100)
[[ $fresh_pages == *"Fresh assignment"* && $fresh_pages == *"school.example/fresh-assignment"* ]] || fail "pages collects a newly committed visit before rendering" "$fresh_pages"
[[ $(grep -c 'school.example/fresh-assignment' "$tmp/state/kid/browsing/visits.tsv") == 1 ]] || fail "the report-time collection keeps the fresh visit once"
append_chromium "$kid_home/.config/chromium/Default/History" \
  "$((now-20))|https://www.youtube.com/watch?v=fresh12345|Fresh lesson - YouTube"
fresh_videos=$(PATH="$tmp/bin:$PATH" RUN_ROOT="$tmp/root/run/user" report_videos kid 7)
[[ $fresh_videos == *"Fresh lesson"* ]] || fail "videos collects a newly committed visit before rendering" "$fresh_videos"
unset -f user_home
pass "the collector runs clean, and reports refresh newly committed visits"

# The real command: on writes state and policy, off reverses, videos reports.
if ! unshare --user --map-root-user true 2>/dev/null; then
  pass "no unprivileged user namespace; skipping the browsing on/off probes"
  exit 0
fi
mkdir -p "$tmp/rbin"
for s in systemctl systemd-detect-virt; do printf '#!/bin/bash\nexit 0\n' >"$tmp/rbin/$s"; done
printf '#!/bin/bash\n[[ ${STUB_PROFILE:-child} == child ]]\n' >"$tmp/rbin/omarchy-profile-child"
cat >"$tmp/rbin/getent" <<SH
#!/bin/bash
[[ \$2 == kid ]] && { echo "kid:x:$(id -u):$(id -g)::$tmp/kidhome:/bin/bash"; exit 0; }
exit 2
SH
chmod +x "$tmp/rbin"/*
mkdir -p "$tmp/kidhome"
rm -rf "$tmp/state" "$SYSROOT/etc/systemd" && mkdir -p "$tmp/state"
run_browsing() { PATH="$tmp/rbin:$tmp/bin:$PATH" unshare --user --map-root-user bash "$browsing" "$@"; }
run_browsing on --user kid >/dev/null || fail "browsing on succeeds"
[[ -f $tmp/state/kid/browsing/enabled ]] || fail "on marks the account enabled"
[[ -f $SYSROOT/etc/systemd/system/omarchy-parent-browsing.timer ]] || fail "on installs the timer"
[[ -f $SYSROOT/etc/chromium/policies/managed/omarchy-parent-browsing.json ]] || fail "on writes the browser policy"
[[ $(run_browsing status) == *"kid:"* ]] || fail "status names the account"
if STUB_PROFILE=default run_browsing status >/dev/null 2>&1; then fail "browsing refuses outside the child profile"; fi
run_browsing off --user kid >/dev/null || fail "browsing off succeeds"
[[ ! -e $tmp/state/kid/browsing/enabled ]] || fail "off clears the marker"
[[ ! -e $SYSROOT/etc/systemd/system/omarchy-parent-browsing.timer ]] || fail "off removes the timer when idle"
[[ ! -e $SYSROOT/etc/chromium/policies/managed/omarchy-parent-browsing.json ]] || fail "off removes the browser policy when idle"
pass "omarchy-parent browsing switches on and off through the real command"
