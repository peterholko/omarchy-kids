#!/bin/bash

# omarchy:summary=Keep a child install's browsing history where the kid cannot erase it
# omarchy:args=<status|on|off|videos|pages|collect> [DAYS [N]] [--user NAME]
# omarchy:examples=sudo omarchy-kids browsing on | sudo omarchy-kids browsing videos | sudo omarchy-kids browsing pages 30
# omarchy:requires-sudo=true

# The browsing history of a child install (plans/kids-browsing.md), reached as
# `omarchy-kids browsing ...`. A root timer copies the kid's browser history
# and the YouTube titles on screen into a root-only log every minute, and the
# browser is told by policy not to offer a private window or let history be
# deleted. DNS cannot answer which video was watched, because HTTPS hides the
# URL; the browser's own history can. Off until a parent turns it on.
#
# Runs as root; a bare invocation re-execs itself under sudo, whose prompt is
# the parent password itself, forwarding the caller's gum theme vars.

set -euo pipefail

usage() {
  cat <<USAGE
Usage: omarchy-kids browsing [status]
       omarchy-kids browsing on [--user NAME]
       omarchy-kids browsing off [--user NAME]
       omarchy-kids browsing videos [DAYS] [--user NAME]
       omarchy-kids browsing pages [DAYS] [N] [--user NAME]

on        Keep the kid's browsing history where she cannot erase it: a root
          timer collects it every minute, and the browser is told not to offer
          a private window or let history be deleted. NAME defaults to the
          account that invoked sudo.
off       Stop collecting. What was kept stays, readable only by root.
videos    The YouTube videos watched (watch, shorts, youtu.be), most recent
          first, over the last DAYS days (default 7), with the title, when it
          was first opened, how often, and how many minutes it was on screen.
pages     Every page visited, most recent first, over DAYS days (default 7).
status    On for whom, when it last collected, and how much is kept.

The browser shows it is managed while this is on; nothing here is hidden.
Tell your kid the history is kept.
USAGE
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

if (( EUID != 0 )); then
  mapfile -t gum_env < <(env | grep '^GUM_' || true)
  exec sudo env OMARCHY_PATH="$OMARCHY_PATH" "${gum_env[@]}" "$0" "$@"
fi


fail() {
  echo "Error: $1" >&2
  exit 1
}

SYSROOT="${OMARCHY_KIDS_SYSROOT:-}"
STATE_ROOT="${OMARCHY_KIDS_STATE_DIR:-/var/lib/omarchy/parent}"
source "$OMARCHY_PATH/lib/parent/omarchy_kids/core/parent.sh"

SYSTEM_UNIT_DIR="$SYSROOT/etc/systemd/system"
SERVICE=omarchy-kids-browsing.service
TIMER=omarchy-kids-browsing.timer
RUN_ROOT="${OMARCHY_KIDS_RUN:-$SYSROOT/run/user}"
CHROMIUM_POLICY_DIRS=(
  "$SYSROOT/etc/chromium/policies/managed"
  "$SYSROOT/etc/opt/chrome/policies/managed"
  "$SYSROOT/etc/brave/policies/managed"
  "$SYSROOT/etc/opt/edge/policies/managed"
)
FIREFOX_POLICY_FILES=(
  "$SYSROOT/usr/lib/firefox/distribution/policies.json"
  "$SYSROOT/opt/zen-browser/distribution/policies.json"
)
# Chromium-family managed policy: no private window, no guest, history cannot
# be cleared, and history is kept (not auto-deleted).
CHROMIUM_POLICY='{"IncognitoModeAvailability": 1, "BrowserGuestModeEnabled": false, "AllowDeletingBrowserHistory": false, "SavingBrowserHistoryDisabled": false}'

require_child_install() {
  omarchy-profile-child || fail "this is not a child install; browsing history only applies to the kids mode profile"
}

systemd_running() {
  [[ -d /run/systemd/system ]] && ! systemd-detect-virt --quiet --chroot 2>/dev/null
}

user_home() {
  getent passwd "$1" | cut -d: -f6
}

# --- state ---

state_dir() {
  printf '%s\n' "$STATE_ROOT/$1/browsing"
}

enabled_users() {
  local dir name
  for dir in "$STATE_ROOT"/*/browsing; do
    [[ -f $dir/enabled ]] || continue
    name=${dir%/browsing}
    printf '%s\n' "${name##*/}"
  done
}

# --- collection ---

# Chromium keeps visit_time in microseconds since 1601-01-01; Firefox keeps
# visit_date in microseconds since 1970. Both databases are held open by the
# browser, so copy before reading, and open read-only. Only visits newer than
# the cursor for that file are taken; the cursor is that file's kind so the two
# epochs never mix. Emits: epoch \t url \t title, newest cursor last on stderr.
extract_visits() {
  local db="$1" kind="$2" since="$3"
  OMARCHY_DB="$db" OMARCHY_KIND="$kind" OMARCHY_SINCE="$since" python3 - <<'PY'
import os, sqlite3, sys, tempfile, shutil
db = os.environ["OMARCHY_DB"]
kind = os.environ["OMARCHY_KIND"]
since = int(os.environ["OMARCHY_SINCE"] or 0)
tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".db")
tmp.close()
def clean(s):
    return "".join(ch if ch >= " " and ch != "\x7f" else " " for ch in (s or ""))
try:
    shutil.copy2(db, tmp.name)
    # Firefox keeps recent visits in the write-ahead log until a checkpoint;
    # copying it beside the database lets SQLite apply it on open.
    for suffix in ("-wal", "-shm"):
        if os.path.exists(db + suffix):
            shutil.copy2(db + suffix, tmp.name + suffix)
    con = sqlite3.connect(tmp.name)
    con.text_factory = lambda b: b.decode("utf-8", "replace")
    if kind == "chromium":
        # visit_time -> unix epoch: /1e6 then subtract 1601->1970 seconds.
        rows = con.execute(
            "SELECT v.visit_time, u.url, u.title "
            "FROM visits v JOIN urls u ON u.id = v.url "
            "WHERE v.visit_time > ? ORDER BY v.visit_time", (since,)).fetchall()
        newest = since
        out = []
        for vt, url, title in rows:
            newest = max(newest, vt)
            epoch = int(vt / 1000000 - 11644473600)
            out.append((epoch, url, title or ""))
    else:
        rows = con.execute(
            "SELECT h.visit_date, p.url, p.title "
            "FROM moz_historyvisits h JOIN moz_places p ON p.id = h.place_id "
            "WHERE h.visit_date > ? ORDER BY h.visit_date", (since,)).fetchall()
        newest = since
        out = []
        for vd, url, title in rows:
            newest = max(newest, vd)
            epoch = int(vd / 1000000)
            out.append((epoch, url, title or ""))
    con.close()
    for epoch, url, title in out:
        sys.stdout.write(f"{epoch}\t{clean(url)}\t{clean(title)}\n")
    sys.stderr.write(str(newest) + "\n")
finally:
    for suffix in ("", "-wal", "-shm"):
        try:
            os.unlink(tmp.name + suffix)
        except FileNotFoundError:
            pass
PY
}

# The history databases a user has, one "kind\tpath" per line.
history_files() {
  local home="$1" glob
  for glob in \
    ".config/chromium/*/History" \
    ".config/google-chrome/*/History" \
    ".config/BraveSoftware/Brave-Browser/*/History" \
    ".config/microsoft-edge/*/History"; do
    for f in "$home"/$glob; do
      [[ -f $f ]] && printf 'chromium\t%s\n' "$f"
    done
  done
  for f in "$home"/.mozilla/firefox/*/places.sqlite; do
    [[ -f $f ]] && printf 'firefox\t%s\n' "$f"
  done
}

cursor_get() {
  local dir="$1" key="$2"
  [[ -f $dir/cursors ]] || { echo 0; return; }
  awk -F'\t' -v k="$key" '$1 == k { print $2; found = 1 } END { if (!found) print 0 }' "$dir/cursors"
}

cursor_set() {
  local dir="$1" key="$2" value="$3" stage
  touch "$dir/cursors"
  stage=$(mktemp)
  awk -F'\t' -v k="$key" -v v="$value" '$1 != k { print } END { print k "\t" v }' "$dir/cursors" >"$stage"
  install -m600 "$stage" "$dir/cursors"
  rm -f "$stage"
}

# The titles of the windows on the kid's screen now, from Hyprland through her
# own session. No session, no titles, no error.
window_titles() {
  local user="$1" uid runtime sig
  uid=$(id -u "$user" 2>/dev/null) || return 0
  runtime="$RUN_ROOT/$uid"
  sig=$(basename "$(find "$runtime/hypr" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)" 2>/dev/null) || return 0
  [[ -n $sig ]] || return 0
  runuser -u "$user" -- env "XDG_RUNTIME_DIR=$runtime" "HYPRLAND_INSTANCE_SIGNATURE=$sig" hyprctl -j clients 2>/dev/null |
    python3 -c 'import json,sys
try: data = json.load(sys.stdin)
except Exception: sys.exit(0)
for c in data:
    t = "".join(ch if ch >= " " and ch != "\x7f" else " " for ch in (c.get("title") or ""))
    if t.strip(): print(t.strip())' 2>/dev/null || true
}

collect_user() {
  local user="$1" dir home now line kind db key since newest title
  dir=$(state_dir "$user")
  [[ -f $dir/enabled ]] || return 0
  home=$(user_home "$user")
  [[ -n $home && -d $home ]] || return 0
  now=$(date +%s)

  # A report may request a collection while the timer is already collecting.
  # Serialize them so both runs cannot append the same visits or race cursors.
  exec 9>"$dir/collect.lock"
  chmod 600 "$dir/collect.lock"
  flock 9

  while IFS=$'\t' read -r kind db; do
    [[ -n $db ]] || continue
    key="$kind:$db"
    since=$(cursor_get "$dir" "$key")
    : >"$dir/.visits.new"
    # extract_visits writes "epoch url title" to stdout and the newest visit
    # time to stderr; add the browser column before appending to the log.
    if extract_visits "$db" "$kind" "$since" >"$dir/.visits.new" 2>"$dir/.newest"; then
      [[ -s $dir/.visits.new ]] && sed "s/\$/\t$kind/" "$dir/.visits.new" >>"$dir/visits.tsv"
      newest=$(cat "$dir/.newest" 2>/dev/null || echo "$since")
      (( newest > since )) && cursor_set "$dir" "$key" "$newest"
    fi
    rm -f "$dir/.visits.new" "$dir/.newest"
  done < <(history_files "$home")

  while IFS= read -r title; do
    [[ $title == *YouTube* ]] || continue
    printf '%s\t%s\n' "$now" "$title" >>"$dir/titles.tsv"
  done < <(window_titles "$user")

  chmod 700 "$dir"
  local kept
  for kept in "$dir/visits.tsv" "$dir/titles.tsv" "$dir/cursors"; do
    if [[ -f $kept ]]; then chmod 600 "$kept"; fi
  done
  flock -u 9
  exec 9>&-
  return 0
}

do_collect() {
  local user
  for user in $(enabled_users); do
    collect_user "$user"
  done
}

# --- reports ---

# The YouTube videos in the log, by video id: title, first seen, times opened,
# and minutes on screen (one title row per collection, so one per minute).
show_videos() {
  local user="$1" days="$2" dir since
  dir=$(state_dir "$user")
  since=$(( $(date +%s) - days * 86400 ))
  [[ -f $dir/visits.tsv || -f $dir/titles.tsv ]] || { echo "Nothing kept yet for $user."; return 0; }
  OMARCHY_VISITS="$dir/visits.tsv" OMARCHY_TITLES="$dir/titles.tsv" OMARCHY_SINCE="$since" python3 - <<'PY'
import os, re
since = int(os.environ["OMARCHY_SINCE"])
vid_re = re.compile(r'(?:youtube\.com/watch\?(?:.*&)?v=|youtube\.com/shorts/|youtu\.be/)([A-Za-z0-9_-]{6,})')
videos = {}
try:
    with open(os.environ["OMARCHY_VISITS"], encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3: continue
            epoch = int(parts[0]); url = parts[1]; title = parts[2]
            if epoch < since: continue
            m = vid_re.search(url)
            if not m: continue
            vid = m.group(1)
            v = videos.setdefault(vid, {"title": "", "first": epoch, "opens": 0, "minutes": 0})
            v["opens"] += 1
            v["first"] = min(v["first"], epoch)
            t = re.sub(r'\s*-\s*YouTube.*$', '', title).strip()
            if t: v["title"] = t
except FileNotFoundError:
    pass
titles_path = os.environ.get("OMARCHY_TITLES")
if titles_path and os.path.exists(titles_path):
    seen = {}
    with open(titles_path, encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t", 1)
            if len(parts) < 2: continue
            epoch = int(parts[0]); title = parts[1]
            if epoch < since: continue
            t = re.sub(r'\s*-\s*YouTube.*$', '', title).strip()
            if not t: continue
            seen.setdefault(t, set()).add(epoch // 60)
    # Attach on-screen minutes to a video whose title we know; leave the rest
    # as a fallback bucket so a wiped profile still shows what was watched.
    known = {v["title"]: vid for vid, v in videos.items() if v["title"]}
    for t, minutes in seen.items():
        if t in known:
            videos[known[t]]["minutes"] += len(minutes)
        else:
            videos.setdefault("title:" + t, {"title": t, "first": min(minutes) * 60, "opens": 0, "minutes": len(minutes)})
if not videos:
    print("No YouTube videos kept in that span.")
else:
    import datetime
    print("YouTube videos, most recent first (opened, minutes on screen, first seen, title):")
    for vid, v in sorted(videos.items(), key=lambda kv: kv[1]["first"], reverse=True):
        when = datetime.datetime.fromtimestamp(v["first"]).strftime("%Y-%m-%d %H:%M")
        title = v["title"] or "(title not captured)"
        print("  %3d opens  %4d min  %s  %s" % (v["opens"], v["minutes"], when, title))
PY
}

show_pages() {
  local user="$1" days="$2" n="$3" dir since
  dir=$(state_dir "$user")
  since=$(( $(date +%s) - days * 86400 ))
  [[ -f $dir/visits.tsv ]] || { echo "Nothing kept yet for $user."; return 0; }
  OMARCHY_VISITS="$dir/visits.tsv" OMARCHY_SINCE="$since" OMARCHY_N="$n" python3 - <<'PY'
import os, datetime
since = int(os.environ["OMARCHY_SINCE"]); n = int(os.environ["OMARCHY_N"])
rows = []
with open(os.environ["OMARCHY_VISITS"], encoding="utf-8") as f:
    for line in f:
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 3: continue
        epoch = int(parts[0])
        if epoch < since: continue
        rows.append((epoch, parts[1], parts[2]))
rows.sort(reverse=True)
if not rows:
    print("No pages kept in that span.")
else:
    print("Pages, most recent first (when, title, url):")
    for epoch, url, title in rows[:n]:
        when = datetime.datetime.fromtimestamp(epoch).strftime("%Y-%m-%d %H:%M")
        print("  %s  %s" % (when, (title or url)[:60]))
        print("      %s" % url[:100])
PY
}

# Reports collect first instead of waiting for the minute timer. Chromium may
# still take a few seconds to commit a just-opened page to History, but a visit
# that is already committed appears in this invocation rather than the next.
report_videos() {
  local user="$1" days="$2"
  collect_user "$user"
  show_videos "$user" "$days"
}

report_pages() {
  local user="$1" days="$2" n="$3"
  collect_user "$user"
  show_pages "$user" "$days" "$n"
}

# --- browser policy ---

install_text() {
  local mode="$1" target="$2" stage
  stage=$(mktemp)
  cat >"$stage"
  mkdir -p "$(dirname "$target")"
  install -m "$mode" "$stage" "$target"
  rm -f "$stage"
}

install_browser_policies() {
  local dir file stage
  for dir in "${CHROMIUM_POLICY_DIRS[@]}"; do
    [[ -d $dir ]] || continue
    printf '%s\n' "$CHROMIUM_POLICY" | install_text 644 "$dir/omarchy-kids-browsing.json"
  done
  local fragment='{"DisablePrivateBrowsing": true, "SanitizeOnShutdown": false}'
  for file in "${FIREFOX_POLICY_FILES[@]}"; do
    [[ -f $file ]] || continue
    "$OMARCHY_PATH/bin/omarchy-kids-files" browser "$file" browsing "$fragment"
  done
}

remove_browser_policies() {
  local dir file stage
  for dir in "${CHROMIUM_POLICY_DIRS[@]}"; do
    rm -f "$dir/omarchy-kids-browsing.json"
  done
  for file in "${FIREFOX_POLICY_FILES[@]}"; do
    [[ -f $file ]] || continue
    "$OMARCHY_PATH/bin/omarchy-kids-files" browser "$file" browsing '{}'
  done
}

# --- units ---

install_units() {
  install -d -m 755 "$SYSTEM_UNIT_DIR"
  install -m 644 "$OMARCHY_PATH/default/parent/$SERVICE" "$SYSTEM_UNIT_DIR/$SERVICE"
  install -m 644 "$OMARCHY_PATH/default/parent/$TIMER" "$SYSTEM_UNIT_DIR/$TIMER"
  if systemd_running; then
    systemctl daemon-reload
    systemctl enable --now "$TIMER" >/dev/null 2>&1 || true
  fi
}

remove_units_if_idle() {
  [[ -n $(enabled_users) ]] && return 0
  if systemd_running; then
    systemctl disable --now "$TIMER" >/dev/null 2>&1 || true
  fi
  rm -f "$SYSTEM_UNIT_DIR/$SERVICE" "$SYSTEM_UNIT_DIR/$TIMER"
  systemd_running && systemctl daemon-reload || true
}

# --- switching ---

turn_on() {
  local user="$1" dir
  dir=$(state_dir "$user")
  install -d -m 700 "$dir"
  : >"$dir/enabled"
  chmod 600 "$dir/enabled"
  install_units
  install_browser_policies
  collect_user "$user"
  echo "Browsing history is kept for $user, where $user cannot erase it. The browser will show it is managed; tell $user the history is on."
}

turn_off() {
  local user="$1" dir
  dir=$(state_dir "$user")
  rm -f "$dir/enabled"
  remove_units_if_idle
  [[ -n $(enabled_users) ]] || remove_browser_policies
  echo "Browsing history collection is off for $user. What was kept stays under $dir, readable only by root."
}

status() {
  local users user dir count last
  users=$(enabled_users)
  if [[ -z $users ]]; then
    echo "Browsing history: off. Turn it on with: sudo omarchy-kids browsing on"
    return 0
  fi
  echo "Browsing history: on."
  for user in $users; do
    dir=$(state_dir "$user")
    count=0
    if [[ -f $dir/visits.tsv ]]; then
      count=$(grep -c . "$dir/visits.tsv") || count=0
    fi
    last="never"
    [[ -f $dir/visits.tsv ]] && last=$(date -d "@$(cut -f1 "$dir/visits.tsv" | sort -n | tail -1)" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "unknown")
    echo "  $user: $count visits kept, newest $last. See them with: sudo omarchy-kids browsing videos"
  done
}

# --- end browsing ---

command="${1:-status}"
(($#)) && shift

user=""
positional=()
while (($#)); do
  case "$1" in
    --user) user="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    *) positional+=("$1"); shift ;;
  esac
done

case "$command" in
  collect)
    # Root plumbing for the timer; no profile check so a chroot rerun is a no-op.
    do_collect
    exit 0
    ;;
esac

require_child_install

resolve_user() {
  [[ -n $user ]] || user="${SUDO_USER:-}"
  [[ -n $user ]] || fail "$1 needs --user NAME, or to run through sudo from the kid's session"
  [[ $user != "root" ]] || fail "the kid account cannot be root"
  getent passwd "$user" >/dev/null || fail "user '$user' does not exist"
}

# A report is about the named account, or the one account that has it on.
report_user() {
  [[ -n $user ]] || user=$(enabled_users | head -1)
  [[ -n $user ]] || fail "no account has browsing history on; name one with --user"
}

case "$command" in
  status)
    status
    ;;
  on)
    systemd_running || fail "browsing history needs a booted system"
    resolve_user on
    turn_on "$user"
    ;;
  off)
    resolve_user off
    turn_off "$user"
    ;;
  videos)
    report_user
    [[ ${positional[0]:-7} =~ ^[1-9][0-9]*$ ]] || fail "videos takes a number of days"
    report_videos "$user" "${positional[0]:-7}"
    ;;
  pages)
    report_user
    [[ ${positional[0]:-7} =~ ^[1-9][0-9]*$ && ${positional[1]:-100} =~ ^[1-9][0-9]*$ ]] || fail "pages takes a number of days and, optionally, a number of pages"
    report_pages "$user" "${positional[0]:-7}" "${positional[1]:-100}"
    ;;
  *)
    echo "Unknown command: $command" >&2
    usage >&2
    exit 1
    ;;
esac
