# Shared Kids setup initializes a new install to dns=off. Apply prepares its
# lists, or restores a parent's existing enabled filter during a rerun.
if [[ ${OMARCHY_INSTALL_PROFILE:-default} == "child" ]]; then
  omarchy-kids-dns apply
fi
