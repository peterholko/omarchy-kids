# Add the screen-time control only when its module is installed.
if omarchy-profile-child 2>/dev/null && omarchy-cmd-present omarchy-kids-time; then
  (
    source "$OMARCHY_PATH/bin/omarchy-shell-config"
    commit "$NORMALIZE
      | if any(.bar.layout[][]; (if type == \"object\" then .id else . end) == \"omarchy.screen-time\") then . else .bar.layout.right = [{\"id\": \"omarchy.screen-time\"}] + .bar.layout.right end"
  ) || echo "Could not put the screen-time pill on the bar; run: omarchy bar put omarchy.screen-time --section right" >&2
fi
