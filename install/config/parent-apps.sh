# A child install (kids mode) starts with the app list on: denylist mode,
# seeded with the apps an eleven-year-old opens only with supervision
# (LocalSend, Moonlight, OBS Studio) and the terminal's own entries, developer
# tools, and disks. apply hides those entries, closes the programs that are
# neither shared nor never-closed, and installs the pacman hook that re-applies
# the list after updates. A parent's later off is kept: apply reads the
# settings file first.
if [[ ${OMARCHY_INSTALL_PROFILE:-default} == "child" ]]; then
  omarchy-kids-apps apply --quiet
fi
