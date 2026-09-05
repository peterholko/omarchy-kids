# Kids mode, DNS filter: `sudo omarchy-kids dns`

Rev 1, 2026-09-01. Branch `kids/dns`, cut from `kids/child-profile`; lands after phase 0 as its own PR. DHH's list for `omarchy-kids` starts with "DNS whitelist"; Peter asked for both an allowlist and a denylist, with the app allowlist (`plans/kids-apps.md`) next and screen time (`plans/kids-screen-time.md`) last.

## What it does

A child install gets a resolver that answers from the parent's lists. In **denylist** mode every domain resolves except the ones the parent has denied; in **allowlist** mode nothing resolves except the domains the parent has allowed, plus a short system list the machine needs for updates and time. Either way the filter runs as root, the kid cannot talk past it on the usual ports, and the browsers are told not to bring their own resolver. It is off until a parent turns it on.

```
sudo omarchy-kids dns                        # status
sudo omarchy-kids dns denylist               # on: everything resolves except the deny list
sudo omarchy-kids dns allowlist              # on: only the allow list and the system list resolve
sudo omarchy-kids dns off
sudo omarchy-kids dns allow DOMAIN...        # add to the allow list (and drop from deny)
sudo omarchy-kids dns deny DOMAIN...         # add to the deny list (and drop from allow)
sudo omarchy-kids dns deny youtube.com/shorts  # an entry with a path: refused by the browser, not the resolver
sudo omarchy-kids dns remove DOMAIN...
sudo omarchy-kids dns list
sudo omarchy-kids dns log [N]                # the names that were refused, most often first
sudo omarchy-kids dns history [DAYS] [N]     # every site asked for, most often first, with when it was last seen
sudo omarchy-kids dns upstream auto|family   # who answers for allowed names
sudo omarchy-kids dns apply                  # after editing the lists by hand
```

## Decisions

- **On by default, through Cloudflare for Families.** Peter decided (2026-09-02) that a child install should filter from its first boot. The defaults are `dns=denylist` with an empty list and `dns_upstream=family`, so malware and adult sites are dropped with no list to keep, and the deny list is there for the parent's own additions. The install leaf `install/config/parent-dns.sh` runs `omarchy-kids-dns apply` on a child install; in the chroot, apply writes everything, enables the unit, and leaves the start to the first boot. The one trade-off is a network whose sign-in page blocks outside DNS: nothing loads until the parent switches `upstream auto`, which the manual and the help say. A parent who wants no filter runs `dns off`, and apply keeps that choice.
- **Two modes, both lists always kept.** Switching between allowlist and denylist keeps both files; a denied name wins inside an allowed domain (`allow google.com`, `deny mail.google.com`), and a denied name wins over the system list, so a parent can shut `github.com` even though updates would like it.
- **dnsmasq behind systemd-resolved, not instead of it.** Omarchy fronts DNS with resolved (nss-resolve, the 127.0.0.53 stub, Docker's extra stub) and `omarchy-dns` writes `resolved.conf` and the NetworkManager profiles. The filter keeps all of that and slips dnsmasq in behind resolved on 127.0.0.1:53: a resolved drop-in makes 127.0.0.1 the only server and disables the fallback list, and a NetworkManager drop-in (`dns=none`, `systemd-resolved=false`) stops NetworkManager from handing resolved the per-link servers it would otherwise query in parallel. dnsmasq learns its upstreams from NetworkManager through a dispatcher script, so `omarchy-dns Cloudflare` and DHCP-provided servers both still steer where allowed names are looked up.
- **`upstream family`** points dnsmasq at Cloudflare for Families (1.1.1.3, 1.0.0.3) instead of the machine's servers, which adds Cloudflare's malware and adult-content blocking under either mode without a list to maintain. It is the default; `auto` hands lookups to the machine's own servers.
- **The kid cannot go around it on the wire.** A ufw block (in `after.rules`, the way ufw-docker adds its own) rejects outgoing DNS on 53 and DNS-over-TLS on 853 from everything but the `dnsmasq` user, and rejects HTTPS to the well-known public resolvers so DNS-over-HTTPS to them fails too. The Chromium family gets a managed policy (`DnsOverHttpsMode: off`); Firefox's canary domain `use-application-dns.net` answers NXDOMAIN, which switches its default DoH off, and its policies file gets `DNSOverHTTPS` locked off when it exists. The known resolver hostnames (`dns.google`, `cloudflare-dns.com`, ...) are denied under both modes.
- **Fail closed.** With the fallback list emptied, a stopped dnsmasq means no DNS rather than unfiltered DNS. The unit restarts it, and `dns` status says when it is down.
- **Lists are files a parent can edit.** `/etc/omarchy/parent/dns.allow` and `dns.deny`, one domain per line, `#` comments, beside `/etc/omarchy/parent.conf` where `dns=` and `dns_upstream=` live. The command edits them for you and `apply` picks up a hand edit.
- **Pages go to the browser.** Peter asked (2026-09-02) to block YouTube Shorts. The resolver cannot: Shorts are `youtube.com/shorts/...`, the same host as the rest, and HTTPS hides the path. Chromium's managed `URLBlocklist` and `URLAllowlist` match host/path prefixes, and Firefox's `WebsiteFilter` takes match patterns, and the filter already writes both policies. So a list entry with a path (`youtube.com/shorts`) is a page: `dnsmasq.conf` skips it, the Chromium policy carries it as a blocklist (deny) or allowlist (allow) entry, and Firefox gets `*://host/path*` and `*://*.host/path*`. It holds under either mode and only while the filter is on, and it is a trim, not a wall: the same short opened as an ordinary `watch` URL is not caught.
- **Visited sites are visible too, openly.** Peter asked (2026-09-01) for a log of every site his daughter visits. dnsmasq's query log already holds it, so `dns history` tallies the last DAYS days by site (registrable domain, three labels under co.uk-style suffixes) with a last-seen time; it is sites, not pages, and only while the filter is on. DHH's boundary applies: a preteen config, not a panopticon for teenagers. So the manual tells the parent to tell the kid the log exists, and nothing here hides it; a maintainer who wants it out of the upstream PR can drop the one subcommand.
- **Blocked names are visible.** dnsmasq logs to the journal; `dns log` tallies the refused names so a parent building an allowlist can see what the kid's page needed (a site is many domains: YouTube is `youtube.com`, `googlevideo.com`, `ytimg.com`, `ggpht.com`, `google.com`).
- **`dnsmasq` ships on child installs** through `install/omarchy-child.packages`, which the ISO already vendors and mirrors; "Me" installs do not get it.

## Naming

| What | Name |
| --- | --- |
| Command | `bin/omarchy-kids-dns`, reached as `sudo omarchy-kids dns ...` |
| Settings | `dns=off\|allowlist\|denylist`, `dns_upstream=auto\|family` in `/etc/omarchy/parent.conf` |
| Lists | `/etc/omarchy/parent/dns.allow`, `/etc/omarchy/parent/dns.deny` |
| Shipped lists | `default/parent/dns-system.list` (always resolves under allowlist), `default/parent/dns-system.deny` (public resolvers, denied under both), `default/parent/dns-public-resolvers.list` (addresses closed on 443) |
| Generated resolver config | `/etc/omarchy/parent/dnsmasq.conf` |
| Unit | `default/parent/omarchy-kids-dns.service` → `/etc/systemd/system/` |
| Upstreams | `/run/omarchy-kids/dns/resolv.conf`, written by `omarchy-kids-dns upstreams` from the NetworkManager dispatcher `/etc/NetworkManager/dispatcher.d/50-omarchy-kids-dns` and by the unit at start |
| NetworkManager drop-in | `/etc/NetworkManager/conf.d/50-omarchy-kids-dns.conf` |
| resolved drop-in | `/etc/systemd/resolved.conf.d/50-omarchy-kids-dns.conf` |
| Firewall | `# BEGIN OMARCHY PARENT DNS` ... `# END OMARCHY PARENT DNS` in `/etc/ufw/after.rules` and `after6.rules` |
| Browser policy | `omarchy-kids-dns.json` in each present Chromium-family managed policy directory; `DNSOverHTTPS` merged into each present Firefox `policies.json` |
| Test override | `OMARCHY_KIDS_SYSROOT` prefixes every system path above (and `OMARCHY_KIDS_CONF` the settings file) |

## Design

### The command

`bin/omarchy-kids-dns`: `# omarchy:summary=Filter the web by domain, allowlist or denylist`, `requires-sudo`, self-elevating like `omarchy-kids-time`, sourcing `install/helpers/parent.sh` for the settings helpers. Child installs only; needs a booted system (`systemd_running`) and the `dnsmasq` binary and user, and says how to get them if missing.

Domains are normalized before they land in a list: lowercased, a scheme and a path stripped (`https://www.youtube.com/watch` becomes `youtube.com`), a leading `www.` dropped, and refused unless they are labels of letters, digits, and dashes with at least one dot. `allow` and `deny` move a name between the lists; `remove` drops it from both; a change under an active mode regenerates and restarts the resolver.

### Generated `dnsmasq.conf`

```
port=53
listen-address=127.0.0.1
bind-interfaces
user=dnsmasq
resolv-file=/run/omarchy-kids/dns/resolv.conf     # or, under upstream family: no-resolv + server=1.1.1.3 ...
cache-size=2000
domain-needed
bogus-priv
stop-dns-rebind
rebind-localhost-ok
log-queries
log-facility=-
address=/use-application-dns.net/                    # Firefox's canary: NXDOMAIN turns its DoH off
address=/dns.google/ ... (dns-system.deny)
address=/#/                                          # allowlist mode only: everything else is NXDOMAIN
server=/omarchy.org/# ... (dns-system.list)          # allowlist mode only
server=/allowed.example/#                            # allowlist mode only, from dns.allow
address=/denied.example/                             # both modes, from dns.deny
```

dnsmasq matches the longest domain suffix, so `address=/#/` loses to every `server=/domain/#`, and a denied subdomain beats the allowed domain above it. A name that is both denied and in the allow or system list is emitted as denied only. The file carries a header saying it is written by the command and which files to edit instead.

### Upstreams

`omarchy-kids-dns upstreams` (root only, not in the usage) lists connected devices with `nmcli -t -f DEVICE,STATE device status`, reads `IP4.DNS` and `IP6.DNS` for each, drops loopback addresses, and writes `nameserver` lines to `/run/omarchy-kids/dns/resolv.conf`, which dnsmasq polls. The dispatcher runs it on every NetworkManager event; the unit runs it before starting. With no network it writes an empty file and allowed names fail until the network is back.

### resolved and NetworkManager

```
# /etc/systemd/resolved.conf.d/50-omarchy-kids-dns.conf
[Resolve]
DNS=
DNS=127.0.0.1
FallbackDNS=
Domains=~.
DNSOverTLS=no

# /etc/NetworkManager/conf.d/50-omarchy-kids-dns.conf
[main]
dns=none
systemd-resolved=false
```

Drop-ins override `resolved.conf`, which `omarchy-dns` keeps writing, so the DNS toggle still records the parent's provider and the dispatcher still honors it. After writing, `on` runs `nmcli general reload conf`, `resolvectl revert` on every device so per-link servers already published are forgotten, and reloads resolved; `off` removes both files, reloads, and asks NetworkManager for `reload dns-full` so the per-link servers come back.

### Firewall

Appended to `/etc/ufw/after.rules` (IPv4 addresses) and `after6.rules` (IPv6) as a marked `*filter` block, removed by deleting between the markers, followed by `ufw reload` when ufw is active:

```
# BEGIN OMARCHY PARENT DNS
*filter
:ufw-after-output - [0:0]
-A ufw-after-output -m owner --uid-owner dnsmasq -p udp --dport 53 -j ACCEPT
-A ufw-after-output -m owner --uid-owner dnsmasq -p tcp --dport 53 -j ACCEPT
-A ufw-after-output -p udp --dport 53 -j REJECT
-A ufw-after-output -p tcp --dport 53 -j REJECT
-A ufw-after-output -p udp --dport 853 -j REJECT
-A ufw-after-output -p tcp --dport 853 -j REJECT
-A ufw-after-output -p tcp --dport 443 -d 1.1.1.1 -j REJECT
...
COMMIT
# END OMARCHY PARENT DNS
```

Loopback is accepted in `before.rules`, so resolved reaching dnsmasq and Docker containers reaching resolved's extra stub are unaffected; containers resolve through the filter too. Root's own `dig @8.8.8.8` is refused as well; `resolvectl query` is the way to ask.

### Browsers

`{"DnsOverHttpsMode": "off"}` as `omarchy-kids-dns.json` in whichever of `/etc/chromium/policies/managed`, `/etc/opt/chrome/policies/managed`, `/etc/brave/policies/managed`, `/etc/opt/edge/policies/managed` exist. For each existing `/usr/lib/firefox/distribution/policies.json` and `/opt/zen-browser/distribution/policies.json`, `jq` sets `.policies.DNSOverHTTPS = {Enabled: false, Locked: true}`; `omarchy-install-browser` rewrites that file from `default/firefox/policies.json`, so the manual says to run `dns apply` after installing a browser, and the canary covers the gap.

### Status and log

Status prints the mode and counts, the upstream, whether the unit is active, whether `resolvectl query use-application-dns.net` comes back NXDOMAIN (the filter is the one answering), whether the firewall block is in place, and which browser policies landed. `dns log [N]` reads `journalctl -u omarchy-kids-dns -o cat`, keeps the `config NAME is NXDOMAIN` lines, drops the canary, and prints the N most frequent names with counts and the `allow` command that would open them.

### Sequences

`on MODE`: checks; `conf_document`/`conf_set`; create the lists if missing; write `dnsmasq.conf`; install the unit; write upstreams; install the dispatcher; write the two drop-ins; `daemon-reload`, `enable --now` (restart if running); NetworkManager and resolved reloads with the reverts; firewall; browsers; status. `off`: `conf_set dns off`; stop and disable; remove the unit, `dnsmasq.conf`, dispatcher, drop-ins (the lists stay); reloads; remove the firewall blocks; remove the browser policy file and the Firefox key; status. `apply`: regenerate everything that is generated, under the current mode, without touching what a hand edit would not change.

### Tests

`test/shell.d/parent-dns-test.sh`. Extracted functions against `OMARCHY_KIDS_SYSROOT` and a scratch `OMARCHY_KIDS_CONF`: domain normalization and refusal; list moves; `dnsmasq.conf` for both modes, with deny beating allow and the system list, and for `upstream family`; upstreams from canned `nmcli` output with loopback dropped; the firewall block text and its removal leaving the surrounding rules intact; the log tally from canned journal lines; the Firefox merge when `jq` is present. The unit file shape and the feature metadata. Then a fake-root half (`unshare`, Linux only) driving `on`, `allow`, `off` through the real command with `systemctl`, `nmcli`, `resolvectl`, `ufw`, `journalctl`, `id`, and `dnsmasq` stubbed, checking every file lands and leaves.

### Manual

`manual/48-security.md`, a "Web filter" subsection under Child installs: what the two modes do, that a site is many domains and `dns log` shows them, the `family` upstream, the lists, and what it does not stop (a VPN or proxy app the parent installed, a browser extension that tunnels, an address typed as numbers, a live USB).

## What it does not stop

Anything that carries traffic without resolving names on this machine: a VPN or a proxy (installs ask the parent; extensions inside the browser do not), a URL typed as an IP address, a resolver on a port other than 53, 853, or the listed 443 endpoints, Tor's built-in bootstrap. The app allowlist and the parent password around installs are the other half; the manual says so.
