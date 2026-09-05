echo "Drop the retired in-tree LLM prompt log; reinstall it from git if it was on"

# The recorder used to ship as /usr/bin/omarchy-parent-llm* and then as
# default/parent/plugins/llm. Both are gone. Machines that already turned it
# on would otherwise keep systemd units pointing at a missing collector.

omarchy-profile-child || exit 0

conf="${OMARCHY_KIDS_CONF:-/etc/omarchy/parent.conf}"
socket=/etc/systemd/system/omarchy-parent-llm.socket
if [[ -f $conf ]] && grep -q '^[[:space:]]*llm[[:space:]]*=[[:space:]]*on' "$conf"; then
  :
elif [[ -e $socket ]]; then
  :
else
  exit 0
fi

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

kid="${SUDO_USER:-$USER}"
as_root omarchy-kids plugin add https://github.com/peterholko/omarchy-parent-llm.git --enable --yes --user "$kid"
