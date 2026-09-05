#!/bin/bash

source "$(dirname "$0")/base-test.sh"

# `omarchy-kids dns` is the child install's web filter: dnsmasq behind
# systemd-resolved answering from the parent's lists, the firewall closing the
# ways around it, the browsers told not to bring their own resolver. The
# functions run extracted against a scratch system root with nmcli and ufw
# stubbed; the real command runs as namespaced root where the kernel allows.

dns="$ROOT/lib/parent/omarchy_kids/dns/command.sh"
parent="$ROOT/bin/omarchy-kids"
unit="$ROOT/default/parent/omarchy-kids-dns.service"

grep -q '^# omarchy:summary=Filter the web by domain, allowlist or denylist' "$dns" || fail "omarchy-kids-dns announces itself as a feature"
grep -q '^# omarchy:requires-sudo=true' "$dns" || fail "the web filter runs as root"
[[ $(OMARCHY_PATH="$ROOT" bash "$parent" --help) == *"dns       Filter the web by domain, allowlist or denylist"* ]] || fail "omarchy-kids lists the web filter as a feature"
grep -Fq 'source "$OMARCHY_PATH/lib/parent/omarchy_kids/core/parent.sh"' "$dns" || fail "the web filter reads parent.conf through the shared helper"
grep -q 'dnsmasq ufw networkmanager' "$ROOT/packaging/modules.PKGBUILD" || fail "DNS owns its optional dependencies"
for f in dns-system.list dns-system.deny dns-public-resolvers.list; do
  [[ -f $ROOT/default/parent/$f ]] || fail "default/parent/$f ships"
done
grep -qx 'ExecStart=/usr/bin/dnsmasq --keep-in-foreground --pid-file= --conf-file=/etc/omarchy/parent/dnsmasq.conf' "$unit" || fail "the unit runs dnsmasq on the generated config"
grep -qx 'ExecStartPre=/usr/bin/omarchy-kids-dns upstreams' "$unit" || fail "the unit writes the upstreams before starting"
grep -qx 'RuntimeDirectory=omarchy-kids/dns' "$unit" || fail "the unit owns the runtime directory"
grep -qx 'Restart=always' "$unit" || fail "the resolver comes back on its own"
pass "the web filter ships as a feature command with its unit and lists"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export OMARCHY_PATH="$ROOT" OMARCHY_KIDS_SYSROOT="$tmp/root" OMARCHY_KIDS_CONF="$tmp/root/etc/omarchy/parent.conf" CALLS="$tmp/calls"
mkdir -p "$tmp/root/etc/omarchy" "$tmp/bin"
: >"$CALLS"

cat >"$tmp/bin/nmcli" <<'SH'
#!/bin/bash
case "$*" in
  "-t -f DEVICE,STATE device status") printf 'wlan0:connected\nlo:unmanaged\neth0:disconnected\n' ;;
  "-t -f DEVICE device status") printf 'wlan0\nlo\neth0\n' ;;
  "-g IP4.DNS,IP6.DNS device show wlan0") printf '1.1.1.1 | 127.0.0.1 | 192.168.1.1\n2606:4700:4700::1111 | ::1\n' ;;
  *) printf 'nmcli %s\n' "$*" >>"$CALLS" ;;
esac
SH
cat >"$tmp/bin/ufw" <<'SH'
#!/bin/bash
if [[ $1 == status ]]; then echo "Status: active"; else printf 'ufw %s\n' "$*" >>"$CALLS"; fi
SH
chmod +x "$tmp/bin"/*
PATH="$tmp/bin:$PATH"

# The paths and every function, minus the elevation and the dispatch.
eval "$(sed -n '/^SYSROOT=/,/^# --- end filter ---$/p' "$dns")"

[[ $(normalize_domain 'https://WWW.YouTube.com/watch?v=1') == youtube.com ]] || fail "a URL becomes its host without www"
[[ $(normalize_domain 'Example.org.') == example.org ]] || fail "a trailing dot and case are dropped"
[[ $(normalize_domain 'mail.google.com:443') == mail.google.com ]] || fail "a port is dropped"
valid_domain youtube.com && valid_domain a-b.example.co.uk || fail "plain domains are valid"
! valid_domain 'you tube.com' || fail "a space is refused"
! valid_domain localhost || fail "a single label is refused"
! valid_domain '-bad.com' || fail "a leading dash is refused"
! valid_domain 'x.com/' || fail "a path is refused"
pass "domains are normalized and checked before they land in a list"

[[ $(normalize_entry 'https://www.YouTube.com/shorts/') == youtube.com/shorts ]] || fail "a page entry keeps its path without the trailing slash" "$(normalize_entry 'https://www.YouTube.com/shorts/')"
[[ $(normalize_entry 'youtube.com/shorts/abc?feature=x') == youtube.com/shorts/abc ]] || fail "a query is dropped from a page entry"
[[ $(normalize_entry 'TikTok.com') == tiktok.com && $(normalize_entry 'https://x.com/') == x.com ]] || fail "a bare domain still normalizes to a domain"
valid_entry youtube.com/shorts && valid_entry example.co.uk/a/b-c_d || fail "page entries are valid"
! valid_entry 'youtube.com/sh orts' || fail "a space in a path is refused"
! valid_entry '/shorts' || fail "a path without a host is refused"
pass "page entries keep a path for the browser"

ensure_lists
grep -q '^# Omarchy kids mode' "$ALLOW_FILE" && grep -q 'dns deny DOMAIN' "$DENY_FILE" || fail "the lists start with a comment header"
list_add "$ALLOW_FILE" youtube.com
list_add "$ALLOW_FILE" youtube.com
[[ $(grep -c '^youtube.com$' "$ALLOW_FILE") == 1 ]] || fail "a name lands once"
list_has "$ALLOW_FILE" youtube.com || fail "list_has finds the name"
printf 'Khan.Academy.ORG  # school\n' >>"$ALLOW_FILE"
list_has "$ALLOW_FILE" khan.academy.org || fail "list_has folds case and ignores comments"
list_drop "$ALLOW_FILE" youtube.com
! list_has "$ALLOW_FILE" youtube.com || fail "list_drop removes the name"
list_has "$ALLOW_FILE" khan.academy.org && grep -q '^# Omarchy' "$ALLOW_FILE" || fail "list_drop keeps the rest and the header"
[[ $(list_count "$ALLOW_FILE") == 1 && $(list_count "$DENY_FILE") == 0 ]] || fail "list_count counts names, not comments"
pass "the lists take a name once and give it back"

printf 'tiktok.com\n# a comment\nMAIL.google.com\n' >"$DENY_FILE"
printf 'google.com\ngithub.com\n' >"$ALLOW_FILE"
conf="$(dnsmasq_conf denylist auto)"$'\n'
[[ $conf == *$'\naddress=/tiktok.com/\n'* && $conf == *$'\naddress=/mail.google.com/\n'* ]] || fail "denylist refuses the deny list" "$conf"
[[ $conf == *$'\naddress=/use-application-dns.net/\n'* && $conf == *$'\naddress=/dns.google/\n'* ]] || fail "the canary and the public resolvers are refused under both modes"
[[ $conf != *'address=/#/'* && $conf != *'server=/'* ]] || fail "denylist forwards everything else"
[[ $conf == *$'\nresolv-file=/run/omarchy-kids/dns/resolv.conf\n'* && $conf == *$'\nuser=dnsmasq\n'* && $conf == *$'\nlisten-address=127.0.0.1\n'* && $conf == *$'\nlog-queries\n'* ]] || fail "dnsmasq listens on loopback as its own user, polls the upstream file, and logs"
conf="$(dnsmasq_conf allowlist auto)"$'\n'
[[ $conf == *$'\naddress=/#/\n'* ]] || fail "allowlist refuses everything by default"
[[ $conf == *$'\nserver=/google.com/#\n'* && $conf == *$'\nserver=/omarchy.org/#\n'* && $conf == *$'\nserver=/archlinux.org/#\n'* ]] || fail "allowlist forwards the allow list and the system list"
[[ $conf == *$'\naddress=/mail.google.com/\n'* ]] || fail "a denied subdomain still wins inside an allowed domain"
printf 'github.com\n' >>"$DENY_FILE"
conf="$(dnsmasq_conf allowlist auto)"$'\n'
[[ $conf != *'server=/github.com/#'* && $conf == *$'\naddress=/github.com/\n'* ]] || fail "a denied name beats the system list"
conf="$(dnsmasq_conf allowlist family)"$'\n'
[[ $conf == *$'\nno-resolv\n'* && $conf == *$'\nserver=1.1.1.3\n'* && $conf == *$'\nserver=2606:4700:4700::1113\n'* && $conf != *resolv-file* ]] || fail "upstream family asks Cloudflare for Families"
pass "dnsmasq.conf renders both modes with deny winning"

printf 'youtube.com/shorts\n' >>"$DENY_FILE"
printf 'youtube.com/kids\n' >>"$ALLOW_FILE"
conf="$(dnsmasq_conf allowlist auto)"$'\n'
[[ $conf != *"shorts"* && $conf != *"youtube.com/kids"* ]] || fail "page entries stay out of the resolver's config" "$conf"
[[ $(page_entries "$DENY_FILE") == youtube.com/shorts && $(domain_entries "$DENY_FILE" | grep -c .) -ge 2 ]] || fail "entries split into pages and domains"
[[ $(chromium_policy_json) == *'"URLBlocklist": ['*'"youtube.com/shorts"'* && $(chromium_policy_json) == *'"URLAllowlist": ['*'"youtube.com/kids"'* && $(chromium_policy_json) == *'"DnsOverHttpsMode": "off"'* ]] || fail "the Chromium policy carries the page entries" "$(chromium_policy_json)"
[[ $(printf 'youtube.com/shorts\n' | firefox_patterns | tr '\n' ' ') == '*://youtube.com/shorts* *://*.youtube.com/shorts* ' ]] || fail "Firefox gets match patterns for host and subdomains" "$(printf 'youtube.com/shorts\n' | firefox_patterns)"
[[ $(show_lists) == *"Pages refused by the browser"*"  youtube.com/shorts"* ]] || fail "list shows the pages apart from the domains" "$(show_lists)"
pass "a page entry goes to the browsers, not the resolver"

write_upstreams
[[ $(grep '^nameserver' "$RESOLV_FILE") == $'nameserver 1.1.1.1\nnameserver 192.168.1.1\nnameserver 2606:4700:4700::1111' ]] || fail "upstreams come from the connected devices with loopback dropped" "$(<"$RESOLV_FILE")"
[[ $(resolved_conf) == *$'\nDNS=\nDNS=127.0.0.1\nFallbackDNS=\nDomains=~.\nDNSOverTLS=no'* ]] || fail "resolved is pointed at the filter alone with no fallback"
[[ $(nm_conf) == *$'\ndns=none\nsystemd-resolved=false'* ]] || fail "NetworkManager stops publishing its servers"
[[ $(dispatcher_script) == *'exec /usr/bin/omarchy-kids-dns upstreams'* ]] || fail "the dispatcher refreshes the upstreams"
pass "the upstreams, resolved, and NetworkManager drop-ins render"

cat >"$tmp/bin/nmcli" <<'SH'
#!/bin/bash
echo "Error: Could not create NMClient object: Could not connect: No such file or directory" >&2
exit 1
SH
chmod +x "$tmp/bin/nmcli"
write_upstreams || fail "write_upstreams succeeds with no NetworkManager"
! grep -q '^nameserver' "$RESOLV_FILE" || fail "no nameserver lines when there is no network yet" "$(<"$RESOLV_FILE")"
grep -q 'Written by omarchy-kids-dns' "$RESOLV_FILE" || fail "the resolv file is still written with no network"
pass "no NetworkManager yet still writes an empty upstreams file"

cat >"$tmp/bin/nmcli" <<'SH'
#!/bin/bash
case "$*" in
  "-t -f DEVICE,STATE device status") printf 'wlan0:connected\nlo:unmanaged\neth0:disconnected\n' ;;
  "-t -f DEVICE device status") printf 'wlan0\nlo\neth0\n' ;;
  "-g IP4.DNS,IP6.DNS device show wlan0") printf '1.1.1.1 | 127.0.0.1 | 192.168.1.1\n2606:4700:4700::1111 | ::1\n' ;;
  *) printf 'nmcli %s\n' "$*" >>"$CALLS" ;;
esac
SH
chmod +x "$tmp/bin/nmcli"

mkdir -p "$UFW_DIR"
original=$'*filter\n:ufw-after-output - [0:0]\n-A ufw-after-output -j RETURN\nCOMMIT'
printf '%s\n' "$original" >"$UFW_DIR/after.rules"
printf '%s\n' "$original" >"$UFW_DIR/after6.rules"
install_firewall_block
[[ $(grep -c '^# BEGIN OMARCHY PARENT DNS$' "$UFW_DIR/after.rules") == 1 ]] || fail "the block lands once"
grep -qx -- '-A ufw-after-output -m owner --uid-owner dnsmasq -p udp --dport 53 -j ACCEPT' "$UFW_DIR/after.rules" || fail "dnsmasq may still reach port 53"
grep -qx -- '-A ufw-after-output -p tcp --dport 853 -j REJECT' "$UFW_DIR/after.rules" || fail "DNS over TLS is refused"
grep -qx -- '-A ufw-after-output -p tcp --dport 443 -d 1.1.1.1 -j REJECT' "$UFW_DIR/after.rules" || fail "HTTPS to a public resolver is refused"
grep -qx -- '-A ufw-after-output -p tcp --dport 443 -d 45.90.28.0/24 -j REJECT' "$UFW_DIR/after.rules" || fail "a resolver range is refused"
! grep -q '2606:4700' "$UFW_DIR/after.rules" || fail "IPv6 addresses stay out of after.rules"
grep -qx -- '-A ufw-after-output -p tcp --dport 443 -d 2606:4700:4700::1111 -j REJECT' "$UFW_DIR/after6.rules" || fail "IPv6 resolvers go to after6.rules"
[[ $(head -n 4 "$UFW_DIR/after.rules") == "$original" ]] || fail "the original rules lead the file"
install_firewall_block
[[ $(grep -c '^# BEGIN OMARCHY PARENT DNS$' "$UFW_DIR/after.rules") == 1 ]] || fail "a rerun replaces the block rather than adding one"
firewall_closed || fail "firewall_closed sees the block"
remove_firewall_block
[[ $(<"$UFW_DIR/after.rules") == "$original" && $(<"$UFW_DIR/after6.rules") == "$original" ]] || fail "removing the block leaves the original rules" "$(<"$UFW_DIR/after.rules")"
! firewall_closed || fail "firewall_closed sees the block gone"
[[ $(grep -c '^ufw reload$' "$CALLS") == 3 ]] || fail "each change reloads ufw" "calls: $(<"$CALLS")"
pass "the firewall block closes the ways around the filter and comes out clean"

tally=$(printf '%s\n' 'dnsmasq: config tiktok.com is NXDOMAIN' 'dnsmasq: forwarded youtube.com to 1.1.1.1' 'dnsmasq: config tiktok.com is NXDOMAIN' 'dnsmasq: config use-application-dns.net is NXDOMAIN' 'dnsmasq: config x.com is NXDOMAIN' | log_tally 10)
[[ $tally == $'2 tiktok.com\n1 x.com' ]] || fail "the log tally counts refused names, canary aside" "$tally"
[[ $(printf 'dnsmasq: config a.com is NXDOMAIN\ndnsmasq: config b.com is NXDOMAIN\n' | log_tally 1) == "1 a.com" ]] || fail "the tally honors the limit"
pass "the log tallies what was refused"

history=$(printf '%s\n' \
  '2026-09-01T09:00:01-0700 host dnsmasq[1]: query[A] www.youtube.com from 127.0.0.1' \
  '2026-09-01T09:00:02-0700 host dnsmasq[1]: query[AAAA] www.youtube.com from 127.0.0.1' \
  '2026-09-01T09:05:00-0700 host dnsmasq[1]: forwarded www.youtube.com to 1.1.1.1' \
  '2026-09-01T09:06:00-0700 host dnsmasq[1]: query[A] m.youtube.com from 127.0.0.1' \
  '2026-09-01T09:07:00-0700 host dnsmasq[1]: query[A] i.ytimg.com from 127.0.0.1' \
  '2026-09-01T10:00:00-0700 host dnsmasq[1]: query[A] news.bbc.co.uk from 127.0.0.1' \
  '2026-09-01T11:00:00-0700 host dnsmasq[1]: query[A] tiktok.com from 127.0.0.1' \
  '2026-09-01T11:00:00-0700 host dnsmasq[1]: config tiktok.com is NXDOMAIN' \
  | history_tally 10)
[[ $tally != "" ]] || true
[[ $(printf '%s\n' "$history" | cut -f1,2 | tr '\t' ' ' | tr '\n' ';') == "3 youtube.com;1 bbc.co.uk;1 tiktok.com;1 ytimg.com;" ]] || fail "history groups lookups by site, most often first" "$history"
[[ $(printf '%s\n' "$history" | head -n 1 | cut -f3) == "2026-09-01T09:06:00-0700" ]] || fail "history keeps the last time a site was seen"
[[ $(printf '2026-09-01T09:00:01-0700 host dnsmasq[1]: query[A] a.com from 127.0.0.1\n2026-09-01T09:00:01-0700 host dnsmasq[1]: query[A] b.com from 127.0.0.1\n' | history_tally 1 | cut -f2) == a.com ]] || fail "history honors the limit"
! (show_history x >/dev/null 2>&1) || fail "history refuses a day count that is not a number"
! (show_history 1 0 >/dev/null 2>&1) || fail "history refuses a zero site count"
grep -q '^# omarchy:args=.*history' "$dns" || fail "history is in the command's metadata"
pass "history tallies every site the laptop asked for"

mkdir -p "$SYSROOT/etc/chromium/policies/managed" "$SYSROOT/usr/lib/firefox/distribution"
printf '{"policies":{"Preferences":{"apz.overscroll.enabled":{"Value":true}}}}\n' >"$SYSROOT/usr/lib/firefox/distribution/policies.json"
install_browser_policies
grep -q '"DnsOverHttpsMode": "off"' "$SYSROOT/etc/chromium/policies/managed/omarchy-kids-dns.json" || fail "Chromium gets DoH switched off by policy" "$(cat "$SYSROOT/etc/chromium/policies/managed/omarchy-kids-dns.json")"
[[ ! -e $SYSROOT/etc/brave/policies/managed/omarchy-kids-dns.json ]] || fail "a browser that is not installed gets no policy directory"
if command -v jq >/dev/null; then
  [[ $(jq -c '.policies.DNSOverHTTPS' "$SYSROOT/usr/lib/firefox/distribution/policies.json") == '{"Enabled":false,"Locked":true}' ]] || fail "Firefox gets DoH locked off in its policies"
  [[ $(jq -c '.policies.Preferences' "$SYSROOT/usr/lib/firefox/distribution/policies.json") == '{"apz.overscroll.enabled":{"Value":true}}' ]] || fail "the Firefox merge keeps the shipped preferences"
fi
[[ $(browser_report) == *"/etc/chromium/policies/managed"* ]] || fail "the status names the browsers covered"
grep -q '"youtube.com/shorts"' "$SYSROOT/etc/chromium/policies/managed/omarchy-kids-dns.json" || fail "the installed Chromium policy refuses the page"
if command -v jq >/dev/null; then
  [[ $(jq -c '.policies.WebsiteFilter.Block' "$SYSROOT/usr/lib/firefox/distribution/policies.json") == '["*://youtube.com/shorts*","*://*.youtube.com/shorts*"]' ]] || fail "Firefox refuses the page by WebsiteFilter" "$(jq -c '.policies.WebsiteFilter' "$SYSROOT/usr/lib/firefox/distribution/policies.json")"
fi
[[ $(browser_report) == *"Pages refused by the browser: 1"* ]] || fail "the status counts the refused pages"
remove_browser_policies
[[ ! -e $SYSROOT/etc/chromium/policies/managed/omarchy-kids-dns.json ]] || fail "off removes the Chromium policy"
if command -v jq >/dev/null; then
  [[ $(jq -c '.policies | keys' "$SYSROOT/usr/lib/firefox/distribution/policies.json") == '["Preferences"]' ]] || fail "off takes the Firefox keys back out"
fi
pass "the browsers are told not to bring their own resolver, and told again on off"

document_keys
grep -qx 'dns=denylist' "$PARENT_CONF" && grep -qx 'dns_upstream=family' "$PARENT_CONF" || fail "the keys are documented in parent.conf with their defaults: on, through Cloudflare for Families"
grep -q '^# dns: the web filter' "$PARENT_CONF" || fail "the key is explained above itself"
[[ $(dns_mode) == denylist && $(dns_upstream) == family ]] || fail "the defaults read back"
conf_set dns maybe
[[ $(dns_mode 2>/dev/null) == denylist ]] || fail "an unknown mode falls back to the default, denylist"
conf_set dns allowlist
conf_set dns_upstream family
[[ $(dns_mode) == allowlist && $(dns_upstream) == family ]] || fail "the set values read back"
pass "parent.conf carries the web filter's keys"

# The install leaf: a child install runs apply inside the chroot, where nothing
# can start, so apply writes everything, enables the unit, and stops short of
# restarting; the defaults it reads make the filter on, through Cloudflare for
# Families, from the first boot.
leaf="$ROOT/install/config/parent-dns.sh"
grep -qx '  omarchy-kids-dns apply' "$leaf" && grep -q 'OMARCHY_INSTALL_PROFILE:-default} == "child"' "$leaf" || fail "the install leaf runs apply on a child install only"
[[ $(grep -n -E 'config/(firewall|parent-dns)\.sh' "$ROOT/install/config/all.sh" | tr '\n' ' ') == *'firewall.sh'*'parent-dns.sh'* ]] || fail "the leaf runs after the firewall is set up"
printf '#!/bin/bash\nprintf "systemctl %%s\\n" "$*" >>"$CALLS"\n' >"$tmp/bin/systemctl"
chmod +x "$tmp/bin/systemctl"
cat >"$tmp/bin/nmcli" <<'SH'
#!/bin/bash
echo "Error: Could not create NMClient object: Could not connect: No such file or directory" >&2
exit 1
SH
chmod +x "$tmp/bin/nmcli"
systemd_running() { false; }
: >"$PARENT_CONF"
: >"$CALLS"
rm -rf "$SYSROOT/etc/omarchy/parent" "$UNIT_DIR"
printf '%s\n' "$original" >"$UFW_DIR/after.rules"
printf '%s\n' "$original" >"$UFW_DIR/after6.rules"
out=$(apply) || fail "apply succeeds in the install chroot" "$out"
grep -qx 'dns=denylist' "$PARENT_CONF" && grep -qx 'dns_upstream=family' "$PARENT_CONF" || fail "apply documents the defaults in parent.conf"
[[ -f $DNSMASQ_CONF && -x $DISPATCHER && -f $NM_CONF && -f $RESOLVED_CONF && -f $UNIT_DIR/$UNIT && -f $ALLOW_FILE && -f $DENY_FILE ]] || fail "apply writes the resolver, the drop-ins, the unit, and the lists"
grep -qx 'no-resolv' "$DNSMASQ_CONF" && grep -qx 'server=1.1.1.3' "$DNSMASQ_CONF" || fail "a fresh install answers through Cloudflare for Families" "$(<"$DNSMASQ_CONF")"
firewall_closed || fail "apply closes the firewall"
grep -qx "systemctl enable $UNIT" "$CALLS" || fail "apply enables the resolver for the first boot" "$(<"$CALLS")"
! grep -q 'systemctl restart\|systemctl daemon-reload' "$CALLS" || fail "apply starts nothing inside the chroot" "$(<"$CALLS")"
[[ $out == "Web filter: denylist, upstream family; it starts with the machine." ]] || fail "apply says the filter starts with the machine" "$out"
unset -f systemd_running
cat >"$tmp/bin/nmcli" <<'SH'
#!/bin/bash
case "$*" in
  "-t -f DEVICE,STATE device status") printf 'wlan0:connected\nlo:unmanaged\neth0:disconnected\n' ;;
  "-t -f DEVICE device status") printf 'wlan0\nlo\neth0\n' ;;
  "-g IP4.DNS,IP6.DNS device show wlan0") printf '1.1.1.1 | 127.0.0.1 | 192.168.1.1\n2606:4700:4700::1111 | ::1\n' ;;
  *) printf 'nmcli %s\n' "$*" >>"$CALLS" ;;
esac
SH
chmod +x "$tmp/bin/nmcli"
pass "a child install's apply lands the filter, on through Cloudflare for Families, for the first boot"

# Behavioral half: the real command as namespaced root.
if ! unshare --user --map-root-user true 2>/dev/null; then
  pass "no unprivileged user namespace; skipping the omarchy-kids dns on/off probes"
  exit 0
fi
if ! systemd-detect-virt --quiet --chroot 2>/dev/null; then :; fi
[[ -d /run/systemd/system ]] || { pass "no running systemd; skipping the omarchy-kids dns on/off probes"; exit 0; }

for stub in systemctl resolvectl journalctl dnsmasq; do
  printf '#!/bin/bash\nprintf "%s %%s\\n" "$*" >>"$CALLS"\n' "$stub" >"$tmp/bin/$stub"
done
cat >"$tmp/bin/resolvectl" <<'SH'
#!/bin/bash
printf 'resolvectl %s\n' "$*" >>"$CALLS"
[[ $1 == query ]] && exit 1
exit 0
SH
cat >"$tmp/bin/id" <<'SH'
#!/bin/bash
[[ $1 == dnsmasq ]] && { echo "uid=976(dnsmasq) gid=976(dnsmasq)"; exit 0; }
exec /usr/bin/id "$@"
SH
cat >"$tmp/bin/omarchy-profile-child" <<'SH'
#!/bin/bash
[[ ${STUB_PROFILE:-child} == child ]]
SH
chmod +x "$tmp/bin"/*
rm -rf "$SYSROOT/etc/omarchy/parent" "$SYSROOT/run"
: >"$PARENT_CONF"
printf '%s\n' "$original" >"$UFW_DIR/after.rules"

run_dns() {
  PATH="$tmp/bin:$PATH" unshare --user --map-root-user bash "$dns" "$@"
}

: >"$CALLS"
run_dns denylist >"$tmp/out" || fail "dns denylist succeeds" "$(<"$tmp/out")"
grep -qx 'dns=denylist' "$PARENT_CONF" || fail "denylist records the mode"
[[ -f $DNSMASQ_CONF && -f $DISPATCHER && -x $DISPATCHER && -f $NM_CONF && -f $RESOLVED_CONF && -f $UNIT_DIR/$UNIT ]] || fail "denylist writes the resolver, dispatcher, and drop-ins"
grep -q "^systemctl restart $UNIT$" "$CALLS" && grep -q '^systemctl reload-or-restart systemd-resolved.service$' "$CALLS" || fail "denylist starts the resolver and reloads resolved" "$(<"$CALLS")"
grep -q '^resolvectl revert wlan0$' "$CALLS" || fail "denylist forgets the per-link servers"
firewall_closed || fail "denylist closes the firewall"
[[ $(<"$tmp/out") == *"Web filter: denylist"* && $(<"$tmp/out") == *"Answering: the filter"* ]] || fail "denylist ends with the status" "$(<"$tmp/out")"
pass "omarchy-kids dns denylist installs the filter"

run_dns deny TikTok.com >/dev/null || fail "dns deny succeeds"
grep -qx 'tiktok.com' "$DENY_FILE" && grep -q '^address=/tiktok.com/$' "$DNSMASQ_CONF" || fail "deny lands in the list and the resolver config"
run_dns allow https://www.khanacademy.org/math >/dev/null || fail "dns allow succeeds"
grep -qx 'khanacademy.org' "$ALLOW_FILE" || fail "allow normalizes the URL into the list"
if run_dns allow 'not a domain' >/dev/null 2>&1; then
  fail "allow refuses what is not a domain"
fi
[[ $(run_dns list) == *$'Denied'*$'  tiktok.com'* ]] || fail "list shows the deny list"
if STUB_PROFILE=default run_dns status >/dev/null 2>&1; then
  fail "the web filter refuses outside the child profile"
fi
pass "omarchy-kids dns edits the lists through the running filter"

: >"$CALLS"
run_dns off >/dev/null || fail "dns off succeeds"
grep -qx 'dns=off' "$PARENT_CONF" || fail "off records the mode"
[[ ! -e $DNSMASQ_CONF && ! -e $DISPATCHER && ! -e $NM_CONF && ! -e $RESOLVED_CONF && ! -e $UNIT_DIR/$UNIT ]] || fail "off removes what on wrote"
[[ -f $ALLOW_FILE && -f $DENY_FILE ]] || fail "off keeps the lists"
grep -q "^systemctl disable --now $UNIT$" "$CALLS" && grep -q '^nmcli general reload dns-full$' "$CALLS" || fail "off stops the resolver and hands DNS back to NetworkManager" "$(<"$CALLS")"
! firewall_closed || fail "off reopens the firewall"
pass "omarchy-kids dns off is the reverse of on"
