# A child install (kids mode) filters the web from its first boot: the web
# filter's defaults are denylist mode, with nothing in the list yet, answered
# by Cloudflare for Families, so malware and adult sites are dropped without a
# list to keep. apply writes the resolver config, the resolved and
# NetworkManager drop-ins, the firewall block, and the browser policies, and
# enables the resolver, which starts with the machine. A parent's later
# `sudo omarchy-kids dns off` is kept: apply reads the settings file first.
if [[ ${OMARCHY_INSTALL_PROFILE:-default} == "child" ]]; then
  omarchy-kids-dns apply
fi
