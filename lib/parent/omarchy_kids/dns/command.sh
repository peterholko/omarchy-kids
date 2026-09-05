#!/bin/bash

# omarchy:summary=Filter the web by domain, allowlist or denylist
# omarchy:args=<status|denylist|allowlist|off|allow|deny|remove|list|log|history|upstream|apply> [VALUE ...]
# omarchy:examples=sudo omarchy-kids dns denylist | sudo omarchy-kids dns deny tiktok.com | sudo omarchy-kids dns deny youtube.com/shorts | sudo omarchy-kids dns log
# omarchy:requires-sudo=true

# The web filter of a child install (plans/kids-dns.md), reached as
# `omarchy-kids dns ...`. dnsmasq answers on 127.0.0.1 from the parent's
# lists, behind systemd-resolved; NetworkManager keeps its own servers to
# itself; the firewall closes the ways around it; the browsers are told not
# to bring their own resolver. On from a child install's first boot: denylist
# mode with nothing in the list yet, answered by Cloudflare for Families, so
# malware and adult sites are dropped without a list to keep; `dns off`
# removes it, `dns upstream auto` hands lookups to the network's own servers.
#
# Runs as root; a bare invocation re-execs itself under sudo, whose prompt is
# the parent password itself, forwarding the caller's gum theme vars.

set -euo pipefail

usage() {
  cat <<USAGE
Usage: omarchy-kids dns [status]
       omarchy-kids dns <denylist|allowlist|off>
       omarchy-kids dns <allow|deny|remove> DOMAIN...
       omarchy-kids dns list
       omarchy-kids dns log [N]
       omarchy-kids dns history [DAYS] [N]
       omarchy-kids dns upstream [auto|family]
       omarchy-kids dns apply

denylist  Everything resolves except the domains in the deny list.
allowlist Nothing resolves except the allow list and the short system list
          the machine needs for updates and time; a denied name still wins.
allow, deny, remove
          Move domains between /etc/omarchy/parent/dns.allow and dns.deny;
          apply picks up a hand edit of those files. A site is many domains:
          log shows the names a page asked for and was refused, most often
          first, so you can allow them. An entry with a path, such as
          youtube.com/shorts, is refused (or allowed) by the browser instead
          of the resolver, which cannot see paths: Chromium and Firefox
          honor it by policy, under either mode.
history   The sites the laptop asked for in the last DAYS days (default 1),
          most often first, with when each was last seen: the resolver logs
          every lookup to the journal, which the kid cannot read or clear.
          Sites, not pages. Tell your kid the log is there.
upstream  Who answers for allowed names: family (default), Cloudflare for
          Families, which also drops malware and adult sites, or auto, the
          machine's own DNS servers. A sign-in page that blocks outside DNS
          needs auto until the parent is signed in.
apply     Write everything from the settings and the lists; the install runs
          it, so a child install filters from its first boot (denylist, family).
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

# Every system path hangs off SYSROOT so the shell test can run the functions
# against a scratch tree; the settings file comes from the shared helper.
SYSROOT="${OMARCHY_KIDS_SYSROOT:-}"
source "$OMARCHY_PATH/lib/parent/omarchy_kids/core/parent.sh"

PARENT_ETC="$SYSROOT/etc/omarchy/parent"
ALLOW_FILE="$PARENT_ETC/dns.allow"
DENY_FILE="$PARENT_ETC/dns.deny"
DNSMASQ_CONF="$PARENT_ETC/dnsmasq.conf"
RUN_DIR="$SYSROOT/run/omarchy-kids/dns"
RESOLV_FILE="$RUN_DIR/resolv.conf"
UNIT=omarchy-kids-dns.service
UNIT_DIR="$SYSROOT/etc/systemd/system"
UNIT_SOURCE="$OMARCHY_PATH/default/parent/$UNIT"
NM_CONF="$SYSROOT/etc/NetworkManager/conf.d/50-omarchy-kids-dns.conf"
DISPATCHER="$SYSROOT/etc/NetworkManager/dispatcher.d/50-omarchy-kids-dns"
RESOLVED_CONF="$SYSROOT/etc/systemd/resolved.conf.d/50-omarchy-kids-dns.conf"
UFW_DIR="$SYSROOT/etc/ufw"
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
SYSTEM_ALLOW="$OMARCHY_PATH/default/parent/dns-system.list"
SYSTEM_DENY="$OMARCHY_PATH/default/parent/dns-system.deny"
PUBLIC_RESOLVERS="$OMARCHY_PATH/default/parent/dns-public-resolvers.list"
CANARY=use-application-dns.net
FIREWALL_BEGIN='# BEGIN OMARCHY PARENT DNS'
FIREWALL_END='# END OMARCHY PARENT DNS'
# Chromium's URLBlocklist and URLAllowlist take host/path patterns: a bare
# host covers its subdomains and a path is a prefix, so youtube.com/shorts
# covers m.youtube.com/shorts/anything. Firefox's WebsiteFilter takes match
# patterns, so each entry becomes *://host/path* and *://*.host/path*.
chromium_policy_json() {
  OMARCHY_BLOCK="$(page_entries "$DENY_FILE")" OMARCHY_ALLOW="$(page_entries "$ALLOW_FILE")" python3 - <<'PY'
import json, os
block = [e for e in os.environ.get("OMARCHY_BLOCK", "").split("\n") if e]
allow = [e for e in os.environ.get("OMARCHY_ALLOW", "").split("\n") if e]
policy = {"DnsOverHttpsMode": "off"}
if block: policy["URLBlocklist"] = block
if allow: policy["URLAllowlist"] = allow
print(json.dumps(policy, indent=2))
PY
}

firefox_patterns() {
  local entry host path
  while IFS= read -r entry; do
    [[ -n $entry ]] || continue
    host=${entry%%/*}
    path=/${entry#*/}
    printf '*://%s%s*\n*://*.%s%s*\n' "$host" "$path" "$host" "$path"
  done
}

require_child_install() {
  omarchy-profile-child || fail "this is not a child install; the web filter only applies to the kids mode profile"
}

# The install chroot sees the live system's /run; only a booted system outside
# a chroot can run the resolver.
systemd_running() {
  [[ -d /run/systemd/system ]] && ! systemd-detect-virt --quiet --chroot 2>/dev/null
}

# --- lists ---

# A list file: one domain per line, # comments, case folded.
read_list() {
  [[ -f $1 ]] || return 0
  sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1" | grep -v '^$' | tr 'A-Z' 'a-z'
}

# What a parent types is often a URL: keep the host, drop www.
normalize_domain() {
  local d
  d=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
  d=${d#*://}
  d=${d%%/*}
  d=${d%%:*}
  d=${d#www.}
  d=${d%.}
  printf '%s\n' "$d"
}

valid_domain() {
  [[ $1 =~ ^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]
}

# A list entry is a domain, or a domain with a path (youtube.com/shorts). The
# host is folded like a domain; the path keeps its case, minus a trailing
# slash and any query, since browsers match paths as typed.
normalize_entry() {
  local raw="$1" host path=""
  raw=${raw#*://}
  raw=${raw%%\?*}
  raw=${raw%%#*}
  if [[ $raw == */* ]]; then
    host=${raw%%/*}
    path=/${raw#*/}
    path=${path%/}
    [[ $path == "/" ]] && path=""
  else
    host=$raw
  fi
  host=$(normalize_domain "$host")
  printf '%s%s\n' "$host" "$path"
}

valid_entry() {
  local entry="$1" host path=""
  if [[ $entry == */* ]]; then
    host=${entry%%/*}
    path=/${entry#*/}
    [[ $path =~ ^/[A-Za-z0-9._~%/-]+$ ]] || return 1
  else
    host=$entry
  fi
  valid_domain "$host"
}

# The entries of a list that name a path: the browser's, not the resolver's.
page_entries() {
  read_list "$1" | grep '/' || true
}

domain_entries() {
  read_list "$1" | grep -v '/' || true
}

list_header() {
  local file="$1" verb="$2"
  cat >"$file" <<HEADER
# Omarchy kids mode: domains the parent ${verb}s, one per line, # for comments.
# Edit and run \`sudo omarchy-kids dns apply\`, or let
# \`sudo omarchy-kids dns ${verb} DOMAIN\` write here for you.
HEADER
  chmod 644 "$file"
}

ensure_lists() {
  mkdir -p "$PARENT_ETC"
  [[ -f $ALLOW_FILE ]] || list_header "$ALLOW_FILE" allow
  [[ -f $DENY_FILE ]] || list_header "$DENY_FILE" deny
}

list_has() {
  read_list "$1" | grep -qx "$2"
}

list_add() {
  local file="$1" name="$2"
  ensure_lists
  list_has "$file" "$name" || printf '%s\n' "$name" >>"$file"
}

list_drop() {
  local file="$1" name="$2" stage pattern
  [[ -f $file ]] || return 0
  pattern=${name//./\\.}
  stage=$(mktemp)
  grep -iv "^[[:space:]]*$pattern[[:space:]]*\(#.*\)\?$" "$file" >"$stage" || true
  install -m644 "$stage" "$file"
  rm -f "$stage"
}

list_count() {
  read_list "$1" | grep -c . || true
}

# --- the resolver ---

dns_mode() {
  local mode
  mode=$(conf_get dns denylist)
  case "$mode" in
    off|denylist|allowlist) printf '%s\n' "$mode" ;;
    *)
      echo "Warning: dns=$mode in $PARENT_CONF is not off, denylist, or allowlist; treating it as denylist." >&2
      echo denylist
      ;;
  esac
}

dns_upstream() {
  local upstream
  upstream=$(conf_get dns_upstream family)
  case "$upstream" in
    auto|family) printf '%s\n' "$upstream" ;;
    *)
      echo "Warning: dns_upstream=$upstream in $PARENT_CONF is not auto or family; treating it as family." >&2
      echo family
      ;;
  esac
}

# dnsmasq matches the longest domain suffix, so address=/#/ loses to every
# server=/domain/#, and a denied subdomain beats the allowed domain above it.
# A name denied outright is emitted as denied only, whatever the allow or
# system list says.
dnsmasq_conf() {
  local mode="$1" upstream="$2" name denied server
  cat <<CONF
# Written by \`omarchy-kids dns\` from /etc/omarchy/parent.conf (dns=$mode,
# dns_upstream=$upstream), /etc/omarchy/parent/dns.allow, and dns.deny. Edit
# those and run \`sudo omarchy-kids dns apply\`; this file is overwritten.
port=53
listen-address=127.0.0.1
bind-interfaces
user=dnsmasq
cache-size=2000
domain-needed
bogus-priv
stop-dns-rebind
rebind-localhost-ok
log-queries
log-facility=-
CONF
  if [[ $upstream == "family" ]]; then
    echo "# Allowed names are answered by Cloudflare for Families."
    echo "no-resolv"
    for server in 1.1.1.3 1.0.0.3 2606:4700:4700::1113 2606:4700:4700::1003; do
      printf 'server=%s\n' "$server"
    done
  else
    echo "# Allowed names are answered by the machine's own servers, from NetworkManager."
    echo "resolv-file=/run/omarchy-kids/dns/resolv.conf"
  fi
  denied=$({ read_list "$SYSTEM_DENY"; domain_entries "$DENY_FILE"; } | sort -u)
  echo "# Refused under both modes: public resolvers by name, Firefox's DoH canary, and the deny list."
  while read -r name; do
    [[ -n $name ]] && printf 'address=/%s/\n' "$name"
  done <<<"$denied"
  if [[ $mode == "allowlist" ]]; then
    echo "# Allowlist: nothing else resolves."
    echo "address=/#/"
    while read -r name; do
      [[ -n $name ]] || continue
      grep -qx "$name" <<<"$denied" && continue
      printf 'server=/%s/#\n' "$name"
    done < <({ read_list "$SYSTEM_ALLOW"; domain_entries "$ALLOW_FILE"; } | sort -u)
  fi
}

write_dnsmasq_conf() {
  local stage
  mkdir -p "$PARENT_ETC"
  stage=$(mktemp)
  dnsmasq_conf "$(dns_mode)" "$(dns_upstream)" >"$stage"
  install -m644 "$stage" "$DNSMASQ_CONF"
  rm -f "$stage"
}

# The servers NetworkManager knows for the connected devices, loopback
# dropped: with dns=none it no longer publishes them itself. Empty is fine:
# the install chroot has no NetworkManager, and first boot may have no
# network yet. grep-on-empty would exit 1 under pipefail and abort apply.
nm_upstreams() {
  local dev state
  while IFS=: read -r dev state; do
    [[ -n $dev && $state == "connected" ]] || continue
    nmcli -g IP4.DNS,IP6.DNS device show "$dev" 2>/dev/null | tr '|' '\n' || true
  done < <(nmcli -t -f DEVICE,STATE device status 2>/dev/null || true) |
    tr -d ' ' |
    awk 'NF && $0 != "::1" && $0 !~ /^127\./ && !seen[$0]++'
}

write_upstreams() {
  mkdir -p "$RUN_DIR"
  {
    echo "# Written by omarchy-kids-dns upstreams from NetworkManager; dnsmasq polls this file."
    nm_upstreams | sed 's/^/nameserver /'
  } >"$RESOLV_FILE.tmp"
  mv -f "$RESOLV_FILE.tmp" "$RESOLV_FILE"
}

resolved_conf() {
  cat <<'CONF'
# Omarchy kids mode: every lookup goes to the DNS filter on 127.0.0.1 and
# nowhere else, and the fallback list is emptied so a stopped filter means no
# DNS rather than unfiltered DNS. Written by `omarchy-kids dns`.
[Resolve]
DNS=
DNS=127.0.0.1
FallbackDNS=
Domains=~.
DNSOverTLS=no
CONF
}

nm_conf() {
  cat <<'CONF'
# Omarchy kids mode: NetworkManager keeps its DNS servers to itself so
# systemd-resolved asks only the filter; omarchy-kids-dns upstreams reads
# them from NetworkManager for dnsmasq instead. Written by `omarchy-kids dns`.
[main]
dns=none
systemd-resolved=false
CONF
}

dispatcher_script() {
  cat <<'SH'
#!/bin/bash
# Omarchy kids mode: keep the DNS filter's upstream servers in step with the
# network. Written by `omarchy-kids dns`.
exec /usr/bin/omarchy-kids-dns upstreams
SH
}

install_text() {
  local mode="$1" target="$2" stage
  stage=$(mktemp)
  cat >"$stage"
  mkdir -p "$(dirname "$target")"
  install -m "$mode" "$stage" "$target"
  rm -f "$stage"
}

# --- the firewall ---

# A marked *filter block at the end of after.rules (after6.rules for IPv6),
# the way ufw-docker adds its own: DNS on 53 and 853 is refused from everyone
# but the dnsmasq user, and HTTPS to the public resolvers by address so DNS
# over HTTPS cannot reach them by number.
firewall_block() {
  local family="$1" proto port addr
  echo "$FIREWALL_BEGIN"
  echo '*filter'
  echo ':ufw-after-output - [0:0]'
  echo '-A ufw-after-output -m owner --uid-owner dnsmasq -p udp --dport 53 -j ACCEPT'
  echo '-A ufw-after-output -m owner --uid-owner dnsmasq -p tcp --dport 53 -j ACCEPT'
  for port in 53 853; do
    for proto in udp tcp; do
      echo "-A ufw-after-output -p $proto --dport $port -j REJECT"
    done
  done
  while read -r addr; do
    [[ -n $addr ]] || continue
    if [[ $family == 6 ]]; then
      [[ $addr == *:* ]] || continue
    else
      [[ $addr == *:* ]] && continue
    fi
    echo "-A ufw-after-output -p tcp --dport 443 -d $addr -j REJECT"
  done < <(read_list "$PUBLIC_RESOLVERS")
  echo 'COMMIT'
  echo "$FIREWALL_END"
}

ufw_rules_file() {
  if [[ $1 == 6 ]]; then
    printf '%s\n' "$UFW_DIR/after6.rules"
  else
    printf '%s\n' "$UFW_DIR/after.rules"
  fi
}

strip_firewall_block() {
  sed "/^$FIREWALL_BEGIN\$/,/^$FIREWALL_END\$/d" "$1"
}

ufw_reload() {
  if ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw reload >/dev/null
  fi
}

install_firewall_block() {
  local family file stage
  for family in 4 6; do
    file=$(ufw_rules_file "$family")
    [[ -f $file ]] || continue
    stage=$(mktemp)
    {
      printf '%s\n' "$(strip_firewall_block "$file")"
      firewall_block "$family"
    } >"$stage"
    install -m640 "$stage" "$file"
    rm -f "$stage"
  done
  ufw_reload
}

remove_firewall_block() {
  local family file stage
  for family in 4 6; do
    file=$(ufw_rules_file "$family")
    [[ -f $file ]] && grep -q "^$FIREWALL_BEGIN\$" "$file" || continue
    stage=$(mktemp)
    printf '%s\n' "$(strip_firewall_block "$file")" >"$stage"
    install -m640 "$stage" "$file"
    rm -f "$stage"
  done
  ufw_reload
}

firewall_closed() {
  local file
  file=$(ufw_rules_file 4)
  [[ -f $file ]] && grep -q "^$FIREWALL_BEGIN\$" "$file"
}

# --- the browsers ---

# The Chromium family takes a managed policy per file; Firefox has one
# policies.json that omarchy-install-browser rewrites, so the key is merged in
# and `dns apply` puts it back after a browser install.
install_browser_policies() {
  local dir file stage
  local policy block exceptions
  policy=$(chromium_policy_json)
  for dir in "${CHROMIUM_POLICY_DIRS[@]}"; do
    [[ -d $dir ]] || continue
    printf '%s\n' "$policy" | install_text 644 "$dir/omarchy-kids-dns.json"
  done
  block=$(page_entries "$DENY_FILE" | firefox_patterns | jq -R . | jq -s .)
  exceptions=$(page_entries "$ALLOW_FILE" | firefox_patterns | jq -R . | jq -s .)
  local fragment
  fragment=$(jq -nc --argjson block "$block" --argjson exceptions "$exceptions" '{DNSOverHTTPS: {Enabled: false, Locked: true}} + (if ($block | length) > 0 then {WebsiteFilter: {Block: $block, Exceptions: $exceptions}} else {} end)')
  for file in "${FIREFOX_POLICY_FILES[@]}"; do
    [[ -f $file ]] || continue
    "$OMARCHY_PATH/bin/omarchy-kids-files" browser "$file" dns "$fragment"
  done
}

remove_browser_policies() {
  local dir file stage
  for dir in "${CHROMIUM_POLICY_DIRS[@]}"; do
    rm -f "$dir/omarchy-kids-dns.json"
  done
  for file in "${FIREFOX_POLICY_FILES[@]}"; do
    [[ -f $file ]] || continue
    "$OMARCHY_PATH/bin/omarchy-kids-files" browser "$file" dns '{}'
  done
}

browser_report() {
  local dir file names=() offs=()
  for dir in "${CHROMIUM_POLICY_DIRS[@]}"; do
    [[ -f $dir/omarchy-kids-dns.json ]] && names+=("${dir#"$SYSROOT"}")
  done
  for file in "${FIREFOX_POLICY_FILES[@]}"; do
    [[ -f $file ]] && grep -q '"DNSOverHTTPS"' "$file" && offs+=("${file#"$SYSROOT"}")
  done
  if (( ${#names[@]} + ${#offs[@]} == 0 )); then
    echo "Browsers: no DoH policy in place."
  else
    echo "Browsers: DNS over HTTPS switched off by policy in ${names[@]+"${names[@]}"} ${offs[@]+"${offs[@]}"}"
  fi
  local pages
  pages=$(page_entries "$DENY_FILE" | grep -c . || true)
  (( pages > 0 )) && echo "Pages refused by the browser: $pages (see: sudo omarchy-kids dns list)"
  return 0
}

# --- the log ---

# dnsmasq logs a refused name as "config NAME is NXDOMAIN"; tally the names
# a page asked for, the canary aside, most often first.
log_tally() {
  local n="$1"
  awk -v canary="$CANARY" '
    match($0, /config [^ ]+ is NXDOMAIN$/) {
      split(substr($0, RSTART, RLENGTH), w, " ")
      if (w[2] != canary) count[w[2]]++
    }
    END { for (name in count) printf "%d %s\n", count[name], name }
  ' | sort -k1,1nr -k2,2 | head -n "$n"
}

show_log() {
  local n="${1:-20}" tally
  [[ $n =~ ^[0-9]+$ ]] || fail "log takes a number of names to show"
  tally=$(journalctl -u "$UNIT" -o cat --no-pager 2>/dev/null | log_tally "$n")
  if [[ -z $tally ]]; then
    echo "Nothing refused yet."
    return 0
  fi
  echo "Refused names, most often first (allow one with: sudo omarchy-kids dns allow NAME):"
  printf '%s\n' "$tally" | awk '{ printf "  %5d  %s\n", $1, $2 }'
}

# Every name the machine asked for, from dnsmasq's query lines, grouped by
# site (the registrable domain, so www.youtube.com and m.youtube.com are one
# line, and co.uk-style suffixes keep three labels), most often first, with
# the last time each was seen.
history_tally() {
  local n="$1"
  awk -v n="$n" '
    match($0, /query\[[A-Z]+\] [^ ]+ from /) {
      split(substr($0, RSTART, RLENGTH), w, " ")
      name = w[2]
      m = split(name, l, ".")
      if (m <= 2) site = name
      else if (length(l[m]) == 2 && l[m-1] ~ /^(co|com|net|org|gov|edu|ac)$/) site = l[m-2] "." l[m-1] "." l[m]
      else site = l[m-1] "." l[m]
      count[site]++
      last[site] = $1
    }
    END { for (s in count) printf "%d\t%s\t%s\n", count[s], s, last[s] }
  ' | sort -t "$(printf '\t')" -k1,1nr -k2,2 | head -n "$n"
}

show_history() {
  local days="${1:-1}" n="${2:-40}" tally
  [[ $days =~ ^[1-9][0-9]*$ && $n =~ ^[1-9][0-9]*$ ]] || fail "history takes a number of days and, optionally, a number of sites to show"
  tally=$(journalctl -u "$UNIT" -o short-iso --no-pager --since "-${days}d" 2>/dev/null | history_tally "$n")
  if [[ -z $tally ]]; then
    echo "Nothing looked up in the last $days day(s); the filter logs while it is on."
    return 0
  fi
  echo "Sites asked for in the last $days day(s), most often first (lookups, site, last seen):"
  printf '%s\n' "$tally" | awk -F '\t' '{ seen = substr($3, 1, 16); sub(/T/, " ", seen); printf "  %6d  %-36s %s\n", $1, $2, seen }'
}

# --- status ---

print_list() {
  local file="$1" names
  names=$(read_list "$file")
  if [[ -z $names ]]; then
    echo "  (none)"
  else
    printf '%s\n' "$names" | sed 's/^/  /'
  fi
}

print_entries() {
  if [[ -z $1 ]]; then
    echo "  (none)"
  else
    printf '%s\n' "$1" | sed 's/^/  /'
  fi
}

show_lists() {
  echo "Mode: $(dns_mode); upstream: $(dns_upstream)"
  echo "Allowed domains ($ALLOW_FILE):"
  print_entries "$(domain_entries "$ALLOW_FILE")"
  echo "Denied domains ($DENY_FILE):"
  print_entries "$(domain_entries "$DENY_FILE")"
  if [[ -n $(page_entries "$DENY_FILE")$(page_entries "$ALLOW_FILE") ]]; then
    echo "Pages refused by the browser (dns.deny entries with a path):"
    print_entries "$(page_entries "$DENY_FILE")"
    echo "Pages the browser lets through anyway (dns.allow entries with a path):"
    print_entries "$(page_entries "$ALLOW_FILE")"
  fi
  if [[ $(dns_mode) == "allowlist" ]]; then
    echo "Always allowed for updates and time (the system list):"
    print_list "$SYSTEM_ALLOW"
  fi
  echo "Public resolvers refused by name: $(list_count "$SYSTEM_DENY")"
}

status() {
  local mode upstream servers
  mode=$(dns_mode)
  upstream=$(dns_upstream)
  if [[ $mode == "off" ]]; then
    echo "Web filter: off ($(list_count "$ALLOW_FILE") allowed, $(list_count "$DENY_FILE") denied in the lists). Turn it on with: sudo omarchy-kids dns denylist, or allowlist."
    return 0
  fi
  if [[ $upstream == "auto" ]]; then
    servers=$(nm_upstreams | tr '\n' ' ')
    servers=${servers% }
    echo "Web filter: $mode ($(list_count "$ALLOW_FILE") allowed, $(list_count "$DENY_FILE") denied), upstream auto (${servers:-no network})."
  else
    echo "Web filter: $mode ($(list_count "$ALLOW_FILE") allowed, $(list_count "$DENY_FILE") denied), upstream Cloudflare for Families."
  fi
  if systemctl is-active --quiet "$UNIT" 2>/dev/null; then
    echo "Resolver: running."
  else
    echo "Resolver: NOT running, so nothing resolves; see: systemctl status $UNIT"
  fi
  if resolvectl query "$CANARY" >/dev/null 2>&1; then
    echo "Answering: NOT the filter; $CANARY resolved. Try: sudo omarchy-kids dns apply"
  else
    echo "Answering: the filter ($CANARY is refused)."
  fi
  if firewall_closed; then
    echo "Firewall: other resolvers closed off."
  else
    echo "Firewall: OPEN to other resolvers; see: sudo omarchy-kids dns apply"
  fi
  browser_report
}

# --- switching ---

document_keys() {
  conf_document dns denylist \
    "dns: the web filter (sudo omarchy-kids dns)." \
    "  denylist   everything resolves except /etc/omarchy/parent/dns.deny (default)" \
    "  allowlist  only /etc/omarchy/parent/dns.allow and the system list resolve" \
    "  off        no filter"
  conf_document dns_upstream family \
    "dns_upstream: who answers for allowed names." \
    "  family  Cloudflare for Families (1.1.1.3), which also drops malware and adult sites (default)" \
    "  auto    the machine's own DNS servers, as omarchy-dns or DHCP set them"
}

install_generated() {
  ensure_lists
  write_dnsmasq_conf
  write_upstreams
  dispatcher_script | install_text 755 "$DISPATCHER"
  nm_conf | install_text 644 "$NM_CONF"
  resolved_conf | install_text 644 "$RESOLVED_CONF"
  mkdir -p "$UNIT_DIR"
  install -m 644 "$UNIT_SOURCE" "$UNIT_DIR/$UNIT"
}

start_resolver() {
  local dev
  systemctl daemon-reload
  systemctl enable "$UNIT" >/dev/null 2>&1 || true
  systemctl restart "$UNIT"
  nmcli general reload conf >/dev/null 2>&1 || true
  while IFS=: read -r dev; do
    [[ -n $dev ]] && resolvectl revert "$dev" >/dev/null 2>&1 || true
  done < <(nmcli -t -f DEVICE device status 2>/dev/null)
  systemctl reload-or-restart systemd-resolved.service
}

stop_resolver() {
  systemctl disable --now "$UNIT" >/dev/null 2>&1 || true
  rm -f "$UNIT_DIR/$UNIT" "$DNSMASQ_CONF" "$DISPATCHER" "$NM_CONF" "$RESOLVED_CONF"
  systemctl daemon-reload
  nmcli general reload conf >/dev/null 2>&1 || true
  systemctl reload-or-restart systemd-resolved.service
  nmcli general reload dns-full >/dev/null 2>&1 || true
}

turn_on() {
  local mode="$1"
  systemd_running || fail "the web filter needs a booted system"
  command -v dnsmasq >/dev/null || fail "dnsmasq is not installed; run: sudo omarchy-pkg-add dnsmasq"
  id dnsmasq >/dev/null 2>&1 || fail "the dnsmasq user is missing; reinstall dnsmasq"
  document_keys
  conf_set dns "$mode"
  install_generated
  start_resolver
  install_firewall_block
  install_browser_policies
  status
}

turn_off() {
  document_keys
  conf_set dns off
  stop_resolver
  remove_firewall_block
  remove_browser_policies
  echo "Web filter: off. The lists in $PARENT_ETC are kept."
}

apply() {
  document_keys
  if [[ $(dns_mode) == "off" ]]; then
    ensure_lists
    echo "Web filter: off; the lists are in place for when it is turned on."
    return 0
  fi
  install_generated
  firewall_closed || install_firewall_block
  install_browser_policies
  # The install chroot writes everything and leaves the start to the first
  # boot: the unit is enabled, and resolved and NetworkManager read their
  # drop-ins when they come up.
  if ! systemd_running; then
    systemctl enable "$UNIT" >/dev/null 2>&1 || true
    echo "Web filter: $(dns_mode), upstream $(dns_upstream); it starts with the machine."
    return 0
  fi
  systemctl daemon-reload
  systemctl enable "$UNIT" >/dev/null 2>&1 || true
  systemctl restart "$UNIT"
  status
}

apply_if_on() {
  [[ $(dns_mode) == "off" ]] && return 0
  write_dnsmasq_conf
  systemctl restart "$UNIT"
  install_browser_policies
}

edit_lists() {
  local verb="$1" raw name
  shift
  (($#)) || fail "$verb takes at least one domain, or a domain with a path such as youtube.com/shorts"
  local where
  for raw in "$@"; do
    name=$(normalize_entry "$raw")
    valid_entry "$name" || fail "'$raw' is not a domain name or a domain with a path (use example.com, or example.com/section)"
    where="by the resolver"
    [[ $name == */* ]] && where="by the browser"
    case "$verb" in
      allow)
        list_drop "$DENY_FILE" "$name"
        list_add "$ALLOW_FILE" "$name"
        echo "Allowed $name $where."
        ;;
      deny)
        list_drop "$ALLOW_FILE" "$name"
        list_add "$DENY_FILE" "$name"
        echo "Denied $name $where."
        ;;
      remove)
        list_drop "$ALLOW_FILE" "$name"
        list_drop "$DENY_FILE" "$name"
        echo "Removed $name from both lists."
        ;;
    esac
  done
  apply_if_on
}

# --- end filter ---

command="${1:-status}"
(($#)) && shift

case "$command" in
  upstreams)
    # Root plumbing for the unit and the NetworkManager dispatcher.
    write_upstreams
    exit 0
    ;;
esac

require_child_install

case "$command" in
  status)
    status
    ;;
  denylist|allowlist)
    turn_on "$command"
    ;;
  off)
    turn_off
    ;;
  allow|deny|remove)
    edit_lists "$command" "$@"
    ;;
  list)
    show_lists
    ;;
  log)
    show_log "${1:-20}"
    ;;
  history)
    show_history "${1:-1}" "${2:-40}"
    ;;
  upstream)
    case "${1:-}" in
      "")
        echo "Upstream: $(dns_upstream)"
        ;;
      auto|family)
        document_keys
        conf_set dns_upstream "$1"
        apply_if_on
        echo "Upstream: $1"
        ;;
      *)
        fail "upstream takes auto or family"
        ;;
    esac
    ;;
  apply)
    apply
    ;;
  *)
    echo "Unknown command: $command" >&2
    usage >&2
    exit 1
    ;;
esac
