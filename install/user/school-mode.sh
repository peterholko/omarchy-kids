# Add the school-mode control only when its module is installed.
if omarchy-profile-child 2>/dev/null && omarchy-cmd-present omarchy-parent-school; then
  (
    source "$OMARCHY_PATH/bin/omarchy-shell-config"
    commit "$NORMALIZE
      | if any(.bar.layout[][]; (if type == \"object\" then .id else . end) == \"omarchy.school-mode\") then . else .bar.layout.left = [{\"id\": \"omarchy.school-mode\"}] + .bar.layout.left end"
  ) || echo "Could not put the school-mode pill on the bar; run: omarchy bar put omarchy.school-mode --section left" >&2
fi
