#!/bin/bash

source "$(dirname "$0")/base-test.sh"

# `omarchy-kids apps` is the child install's app list: a blocked app's
# desktop entry loses its world-read bit and its program its world-execute
# bit, root records and restores the modes, and a pacman hook re-applies the
# lists. The functions run extracted against a scratch system root owned by
# the test user; the real command runs as namespaced root where allowed.

apps="$ROOT/bin/omarchy-kids-apps"
parent="$ROOT/bin/omarchy-kids"
hook="$ROOT/default/parent/omarchy-kids-apps.hook"

grep -q '^# omarchy:summary=Choose which apps the kid can open, allowlist or denylist' "$apps" || fail "omarchy-kids-apps announces itself as a feature"
grep -q '^# omarchy:requires-sudo=true' "$apps" || fail "the app list runs as root"
[[ $(OMARCHY_PATH="$ROOT" bash "$parent" --help) == *"apps      Choose which apps the kid can open, allowlist or denylist"* ]] || fail "omarchy-kids lists the app list as a feature"
grep -Fq 'source "$OMARCHY_PATH/install/helpers/parent.sh"' "$apps" || fail "the app list reads parent.conf through the shared helper"
[[ -f $ROOT/default/parent/apps-never-close.list ]] || fail "the never-close list ships"
grep -qx 'Exec = /usr/bin/omarchy-kids-apps apply --quiet' "$hook" || fail "the hook re-applies the list quietly"
grep -qx 'When = PostTransaction' "$hook" && grep -qx 'Target = usr/share/applications/\*' "$hook" && grep -qx 'Target = usr/bin/\*' "$hook" || fail "the hook fires after transactions touching entries and programs"
[[ -f $ROOT/default/parent/apps-child.deny ]] || fail "the child install's starting deny list ships"
! grep -v '^#' "$ROOT/default/parent/apps-child.deny" | grep -v '^$' | grep -q '[^A-Za-z0-9._-]' || fail "the shipped deny list holds desktop ids only" "$(grep -v '^#' "$ROOT/default/parent/apps-child.deny")"
leaf="$ROOT/install/config/parent-apps.sh"
grep -qx '  omarchy-kids-apps apply --quiet' "$leaf" && grep -q 'OMARCHY_INSTALL_PROFILE:-default} == "child"' "$leaf" || fail "the install leaf applies the list on a child install only"
[[ $(grep -n -E 'config/(parent|parent-apps)\.sh' "$ROOT/install/config/all.sh" | tr '\n' ' ') == *'parent.sh'*'parent-apps.sh'* ]] || fail "the leaf runs after the parent posture"
pass "the app list ships as a feature command with its hook, never-close list, starting deny list, and install leaf"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export OMARCHY_PATH="$ROOT" OMARCHY_KIDS_SYSROOT="$tmp/root" OMARCHY_KIDS_CONF="$tmp/root/etc/omarchy/parent.conf" OMARCHY_KIDS_APPS_OWNER="$(id -un)"
mkdir -p "$tmp/root/etc/omarchy" "$tmp/root/usr/share/applications" "$tmp/root/usr/bin" "$tmp/root/opt/foo" "$tmp/root/usr/lib/foo"

entry() {
  local id="$1" name="$2" exec_line="$3" extra="${4:-}"
  printf '[Desktop Entry]\nType=Application\nName=%s\nExec=%s\n%s\n' "$name" "$exec_line" "$extra" >"$tmp/root/usr/share/applications/$id.desktop"
  chmod 644 "$tmp/root/usr/share/applications/$id.desktop"
}
program() {
  printf '#!/bin/bash\n' >"$tmp/root/$1"
  chmod 755 "$tmp/root/$1"
}
for p in usr/bin/chromium usr/bin/steam usr/bin/libreoffice usr/bin/nautilus usr/bin/alacritty usr/bin/kdenlive opt/foo/foo usr/lib/foo/helper; do program "$p"; done
ln -s libreoffice "$tmp/root/usr/bin/soffice"
entry chromium "Chromium" "/usr/bin/chromium %U"
entry steam "Steam" "steam %U"
entry libreoffice-writer "LibreOffice Writer" "libreoffice --writer %U"
entry libreoffice-calc "LibreOffice Calc" "soffice --calc %U"
entry org.gnome.Nautilus "Files" "nautilus --new-window %U" $'[Desktop Action new-window]\nName=New Window\nExec=nautilus --new-window'
entry Alacritty "Alacritty" "alacritty"
entry org.kde.kdenlive "Kdenlive" "env QT_QPA_PLATFORM=xcb \"/usr/bin/kdenlive\" %f"
entry foo "Foo" "/opt/foo/foo"
entry helper "Helper" "/usr/lib/foo/helper"
entry hidden-tool "Hidden Tool" "chromium --app" "NoDisplay=true"
printf '[Desktop Entry]\nType=Link\nName=A Link\nURL=https://example.com\n' >"$tmp/root/usr/share/applications/a-link.desktop"
entry not-here "Not Here" "/home/kid/bin/thing"

eval "$(sed -n '/^SYSROOT=/,/^# --- end apps ---$/p' "$apps")"

[[ $(apps_mode) == denylist ]] || fail "the app list is on, denylist, by default"
document_key
grep -qx 'apps=denylist' "$PARENT_CONF" || fail "parent.conf documents denylist as the default"
conf_set apps sideways
[[ $(apps_mode 2>/dev/null) == denylist ]] || fail "an unknown mode falls back to the default, denylist"
: >"$PARENT_CONF"
ensure_lists
list_has "$DENY_FILE" foot && list_has "$DENY_FILE" org.gnome.DiskUtility && list_has "$DENY_FILE" com.obsproject.Studio || fail "a fresh deny list starts from the shipped child list" "$(<"$DENY_FILE")"
seed=$(read_list "$SEED_DENY" | grep -c .)
[[ $(list_count "$DENY_FILE") == "$seed" ]] || fail "the seed is copied once, comments aside"
ensure_lists
[[ $(list_count "$DENY_FILE") == "$seed" ]] || fail "an existing deny list is left alone"
pass "a child install starts with the list on and the shipped deny list"

entry_displayable "$SYSROOT/usr/share/applications/chromium.desktop" || fail "an application entry is displayable"
! entry_displayable "$SYSROOT/usr/share/applications/hidden-tool.desktop" || fail "NoDisplay hides an entry from the list"
! entry_displayable "$SYSROOT/usr/share/applications/a-link.desktop" || fail "a link entry is not an app"
[[ $(entry_field "$SYSROOT/usr/share/applications/org.gnome.Nautilus.desktop" Exec) == "nautilus --new-window %U" ]] || fail "entry_field reads the main group, not an action"
[[ $(entry_program "$SYSROOT/usr/share/applications/chromium.desktop") == "$SYSROOT/usr/bin/chromium" ]] || fail "an absolute Exec resolves"
[[ $(entry_program "$SYSROOT/usr/share/applications/steam.desktop") == "$SYSROOT/usr/bin/steam" ]] || fail "a bare program name resolves in the program directories"
[[ $(entry_program "$SYSROOT/usr/share/applications/libreoffice-calc.desktop") == "$SYSROOT/usr/bin/libreoffice" ]] || fail "a symlink resolves to the real program"
[[ $(entry_program "$SYSROOT/usr/share/applications/org.kde.kdenlive.desktop") == "$SYSROOT/usr/bin/kdenlive" ]] || fail "env and VAR=value words and quotes are stepped over"
[[ $(entry_program "$SYSROOT/usr/share/applications/foo.desktop") == "$SYSROOT/opt/foo/foo" ]] || fail "a program under /opt resolves"
[[ $(entry_program "$SYSROOT/usr/share/applications/helper.desktop") == "$SYSROOT/usr/lib/foo/helper" ]] || fail "a program under /usr/lib resolves"
[[ -z $(entry_program "$SYSROOT/usr/share/applications/Alacritty.desktop") ]] || fail "the terminal is never closed"
[[ -z $(entry_program "$SYSROOT/usr/share/applications/not-here.desktop") ]] || fail "a program outside the package directories is left alone"
[[ $(scan_entries | cut -f1 | tr '\n' ' ') == "Alacritty chromium org.gnome.Nautilus foo helper org.kde.kdenlive libreoffice-calc libreoffice-writer not-here steam " ]] || fail "the scan lists displayable entries by name" "$(scan_entries | cut -f1,2)"
pass "desktop entries are read, resolved to their programs, and the never-close list holds"

[[ $(resolve_app steam) == steam && $(resolve_app STEAM) == steam ]] || fail "an id resolves, case aside"
[[ $(resolve_app "libreoffice writer") == libreoffice-writer && $(resolve_app Files) == org.gnome.Nautilus ]] || fail "a launcher name resolves to its id"
[[ $(resolve_app kdenlive) == org.kde.kdenlive ]] || fail "a unique part of a name resolves"
! (resolve_app libreoffice >/dev/null 2>&1) || fail "an ambiguous word is refused"
! (resolve_app nothing-like-it >/dev/null 2>&1) || fail "an unknown word is refused"
pass "apps are named as the launcher shows them"

document_key
conf_set apps denylist
ensure_lists
list_add "$DENY_FILE" steam
list_add "$DENY_FILE" libreoffice-calc
apply_lists
mode() { file_mode "$SYSROOT/$1"; }
[[ $(mode usr/share/applications/steam.desktop) == 640 && $(mode usr/bin/steam) == 750 ]] || fail "a denied app hides and its program closes" "$(mode usr/share/applications/steam.desktop) $(mode usr/bin/steam)"
[[ $(mode usr/share/applications/libreoffice-calc.desktop) == 640 && $(mode usr/bin/libreoffice) == 755 ]] || fail "a program shared with an allowed app stays open"
[[ $(mode usr/share/applications/chromium.desktop) == 644 && $(mode usr/bin/chromium) == 755 ]] || fail "an allowed app is untouched"
[[ $(grep -c . "$RESTORE_FILE") == 3 ]] || fail "the original modes are recorded once each" "$(<"$RESTORE_FILE")"
[[ $(show_list) == *"LibreOffice Calc"*"hidden, program shared with LibreOffice Writer"* ]] || fail "list explains a shared program" "$(show_list)"
[[ $(show_list) == *"Steam"*"steam"*"blocked"* ]] || fail "list shows the verdict"
[[ $(status) == "Apps: denylist, 2 of 10 apps blocked (0 allowed, $((seed + 2)) denied in the lists)."* ]] || fail "status counts the blocked apps" "$(status)"
CHANGED=0
apply_lists
(( CHANGED == 0 )) || fail "a rerun changes nothing"
chmod 755 "$SYSROOT/usr/bin/steam"
apply_lists
[[ $(mode usr/bin/steam) == 750 ]] || fail "apply closes a program a package upgrade reopened"
list_add "$DENY_FILE" libreoffice-writer
apply_lists
[[ $(mode usr/bin/libreoffice) == 750 ]] || fail "a program closes once every app that uses it is blocked"
list_drop "$DENY_FILE" libreoffice-writer
list_drop "$DENY_FILE" steam
apply_lists
[[ $(mode usr/share/applications/steam.desktop) == 644 && $(mode usr/bin/steam) == 755 && $(mode usr/bin/libreoffice) == 755 ]] || fail "a change of mind restores the recorded modes"
[[ $(grep -c . "$RESTORE_FILE") == 1 ]] || fail "restored files leave the record"
pass "denylist hides and closes what the parent denies, shared programs excepted, and restores on a change of mind"

: >"$ALLOW_FILE"
conf_set apps allowlist
seed_allow_list >/dev/null
list_has "$ALLOW_FILE" chromium && list_has "$ALLOW_FILE" steam && ! list_has "$ALLOW_FILE" libreoffice-calc || fail "the seed takes every app installed today except the denied ones" "$(<"$ALLOW_FILE")"
apply_lists
entry newapp "New App" "/usr/bin/newapp"
program usr/bin/newapp
apply_lists
[[ $(mode usr/share/applications/newapp.desktop) == 640 && $(mode usr/bin/newapp) == 750 ]] || fail "under allowlist an app installed later stays hidden"
list_add "$ALLOW_FILE" newapp
apply_lists
[[ $(mode usr/share/applications/newapp.desktop) == 644 && $(mode usr/bin/newapp) == 755 ]] || fail "allowing the new app opens it"
rm "$SYSROOT/usr/share/applications/libreoffice-calc.desktop"
apply_lists
! grep -q 'libreoffice-calc.desktop' "$RESTORE_FILE" || fail "a vanished entry leaves the record"
pass "allowlist starts from today's apps and hides what comes later"

list_add "$DENY_FILE" chromium
apply_lists
[[ $(mode usr/bin/chromium) == 750 ]] || fail "a denied app closes under allowlist too"
conf_set apps off
apply_lists
[[ $(mode usr/share/applications/chromium.desktop) == 644 && $(mode usr/bin/chromium) == 755 && ! -e $RESTORE_FILE ]] || fail "off restores everything and drops the record"
pass "off puts every mode back"

conf_set apps denylist
apply_now
hook_in_place || fail "apply installs the hook while the list is on"
[[ $(mode usr/bin/chromium) == 750 ]] || fail "apply blocks what the lists say"
conf_set apps off
apply_now
! hook_in_place || fail "apply with off takes the hook out"
[[ $(mode usr/bin/chromium) == 755 ]] || fail "apply with off restores"
pass "apply keeps the hook in step with the mode"

# Behavioral half: the real command as namespaced root.
if ! unshare --user --map-root-user true 2>/dev/null; then
  pass "no unprivileged user namespace; skipping the omarchy-kids apps on/off probes"
  exit 0
fi
mkdir -p "$tmp/bin"
cat >"$tmp/bin/omarchy-profile-child" <<'SH'
#!/bin/bash
[[ ${STUB_PROFILE:-child} == child ]]
SH
chmod +x "$tmp/bin"/*
: >"$PARENT_CONF"
rm -f "$ALLOW_FILE" "$DENY_FILE"
run_apps() {
  PATH="$tmp/bin:$PATH" unshare --user --map-root-user bash "$apps" "$@"
}
run_apps denylist >"$tmp/out" || fail "apps denylist succeeds" "$(<"$tmp/out")"
grep -qx 'apps=denylist' "$PARENT_CONF" && [[ -f $HOOK_DIR/$HOOK ]] || fail "denylist records the mode and installs the hook"
run_apps deny Steam >/dev/null || fail "apps deny succeeds"
run_apps apply --quiet >/dev/null || fail "apply --quiet succeeds"
out=$(run_apps apply --quiet) || fail "apply --quiet exits 0 with nothing to change, so the pacman hook never reports a failure" "$out"
[[ -z $out ]] || fail "apply --quiet says nothing with nothing to change" "$out"
[[ $(mode usr/share/applications/steam.desktop) == 640 && $(mode usr/bin/steam) == 750 ]] || fail "deny hides and closes through the real command"
[[ $(run_apps list) == *"Steam"*"blocked"* ]] || fail "list reports through the real command"
if STUB_PROFILE=default run_apps status >/dev/null 2>&1; then
  fail "the app list refuses outside the child profile"
fi
run_apps off >/dev/null || fail "apps off succeeds"
[[ $(mode usr/share/applications/steam.desktop) == 644 && $(mode usr/bin/steam) == 755 && ! -e $HOOK_DIR/$HOOK ]] || fail "off restores the modes and removes the hook"
[[ -f $DENY_FILE ]] || fail "off keeps the lists"
pass "omarchy-kids apps switches on, blocks, and switches off through the real command"
