# Shared by omarchy-kids and its feature commands (omarchy-kids-*), so a
# feature can install a sudoers grant the same careful way, and read and
# document its own keys in the parent's settings file, without copying the
# code. Sourced after the caller has defined `fail`.

SUDOERS_DIR="${OMARCHY_SUDOERS_DIR:-/etc/sudoers.d}"
PARENT_CONF="${OMARCHY_KIDS_CONF:-/etc/omarchy/parent.conf}"

# Stage in the target directory itself, so the final rename is atomic and a
# stray stage file, whose name carries a dot, is one sudo ignores. visudo
# checks the stage before it can become live: a sudoers file that fails to
# parse locks sudo out. Identical content is left alone.
install_sudoers() {
  local name="$1" content="$2"
  local target="$SUDOERS_DIR/$name" stage

  if [[ -f $target ]] && [[ $(<"$target") == "$content" ]]; then
    return 0
  fi

  install -d -m 755 "$SUDOERS_DIR"
  stage=$(mktemp "$SUDOERS_DIR/.$name.XXXXXX")
  printf '%s\n' "$content" >"$stage"
  if ! visudo -cf "$stage" >/dev/null; then
    rm -f "$stage"
    fail "generated sudoers file $name does not parse; nothing was changed"
  fi
  chmod 440 "$stage"
  mv -f "$stage" "$target"
}

# The parent's settings: one key=value per line, world-readable, with every
# key documented in place by whichever command owns it (conf_document), so a
# parent reading the file sees every choice and its default. A hand edit
# takes effect at the owning command's next apply. The file outlives
# `omarchy-kids apply --remove` and every feature's off on purpose.
conf_init() {
  "$OMARCHY_PATH/bin/omarchy-kids-files" config "$PARENT_CONF" init
}

conf_get() {
  local key="$1" default="$2" value=""
  if [[ -f $PARENT_CONF ]]; then
    value=$(sed -n "s/^[[:space:]]*$key[[:space:]]*=[[:space:]]*//p" "$PARENT_CONF" | tail -1)
    value=${value%"${value##*[![:space:]]}"}
  fi
  printf '%s\n' "${value:-$default}"
}

conf_set() {
  "$OMARCHY_PATH/bin/omarchy-kids-files" config "$PARENT_CONF" set "$@"
}

# conf_document KEY DEFAULT COMMENT... appends a commented block and the
# default the first time a command sees the file, and leaves a key the parent
# has already set alone.
conf_document() {
  "$OMARCHY_PATH/bin/omarchy-kids-files" config "$PARENT_CONF" document "$@"
}
