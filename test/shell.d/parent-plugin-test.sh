#!/bin/bash
#
# omarchy-kids-plugin clones optional parent features from git (or copies a
# local folder) into a root-owned store. It is not the shell plugin installer.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
export OMARCHY_PATH="$ROOT"

require_command jq
require_command git

plugin_cmd="$ROOT/bin/omarchy-kids-plugin"
fixture="$ROOT/test/shell.d/fixtures/parent-plugin"

grep -q '^# omarchy:summary=Install optional parent features' "$plugin_cmd" ||
  fail "omarchy-kids-plugin carries a summary"
grep -q '^# omarchy:hidden=true' "$plugin_cmd" || fail "omarchy-kids-plugin is hidden plumbing"
grep -q '^# omarchy:requires-sudo=true' "$plugin_cmd" || fail "omarchy-kids-plugin requires sudo"
pass "omarchy-kids-plugin carries command metadata"

help_output=$(bash "$plugin_cmd" --help)
[[ $help_output == *"omarchy-kids plugin add"* && $help_output == *"<git-url|"* ]] ||
  fail "omarchy-kids-plugin --help prints usage without elevating" "$help_output"
[[ $help_output != *peterholko* && $help_output != *omarchy-kids-llm* ]] ||
  fail "omarchy-kids-plugin --help does not name a first-party llm plugin" "$help_output"
pass "omarchy-kids-plugin answers --help before asking for a password"

parent_help=$(OMARCHY_PATH="$ROOT" bash "$ROOT/bin/omarchy-kids" --help)
[[ $parent_help == *"omarchy-kids plugin add <git-url>"* ]] ||
  fail "omarchy-kids --help mentions installing optional parent plugins" "$parent_help"
[[ $parent_help != *"plugin add llm"* && $parent_help != *omarchy-kids-llm* ]] ||
  fail "omarchy-kids --help does not name an llm plugin" "$parent_help"
pass "omarchy-kids treats parent plugins as git add-ons"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
kid_home="$tmp/kid-home"
mkdir -p "$kid_home"
plugin_bindir="$tmp/plugin-bin"
plugin_store="$tmp/plugin-store"
stub_bin="$tmp/stub-bin"
mkdir -p "$plugin_bindir" "$plugin_store" "$stub_bin"

cat >"$stub_bin/omarchy-profile-child" <<'SH'
#!/bin/bash
[[ ${STUB_PROFILE:-child} == child ]]
SH
chmod +x "$stub_bin"/* "$fixture/bin/omarchy-kids-fixture"

run_plugin() {
  OMARCHY_PATH="$ROOT" \
  OMARCHY_KIDS_PLUGIN_BINDIR="$plugin_bindir" \
  OMARCHY_KIDS_PLUGIN_STORE="$plugin_store" \
  OMARCHY_KIDS_PLUGIN_UNPRIVILEGED=1 \
  PATH="$stub_bin:$plugin_bindir:$ROOT/bin:$PATH" \
  bash "$plugin_cmd" "$@"
}

if STUB_PROFILE=default run_plugin add "$fixture" >/dev/null 2>&1; then
  fail "add refuses outside the child profile"
fi
pass "plugin add refuses outside the child profile"

if run_plugin add nosuch >/dev/null 2>&1; then
  fail "add refuses an unknown plugin id"
fi
pass "plugin add refuses an unknown id"

list_output=$(run_plugin list)
[[ $list_output == *$'core\tKids / Parent Password\tavailable'* ]] || fail "list offers the required core before optional modules are installed" "$list_output"
pass "plugin list is empty with no catalog and nothing installed"

run_plugin add "$fixture" --yes >/dev/null || fail "plugin add from a local folder succeeds"
[[ -L $plugin_bindir/omarchy-kids-fixture ]] || fail "add symlinks the plugin command"
[[ $(readlink "$plugin_bindir/omarchy-kids-fixture") == "$plugin_store/fixture/bin/omarchy-kids-fixture" ]] ||
  fail "the symlink points at the installed plugin copy"
[[ -f $plugin_store/fixture/manifest.json ]] || fail "add copies the plugin into the store"
list_output=$(run_plugin list)
[[ $list_output == *$'fixture\tFixture\tinstalled' ]] ||
  fail "list shows the installed plugin" "$list_output"
pass "plugin add from a folder puts the command on PATH"

run_plugin add "$fixture" --enable --yes >/dev/null || fail "plugin add --enable succeeds"
pass "plugin add --enable is idempotent"

run_plugin remove fixture >/dev/null || fail "plugin remove succeeds"
[[ ! -e $plugin_bindir/omarchy-kids-fixture ]] || fail "remove deletes the symlink"
[[ ! -e $plugin_store/fixture ]] || fail "remove deletes the installed copy"
pass "plugin remove takes the command off PATH"

# A plugin cannot take a built-in name or replace another command on PATH.
collision="$tmp/collision"
cp -a "$fixture" "$collision"
mv "$collision/bin/omarchy-kids-fixture" "$collision/bin/omarchy-kids-time"
jq '.bins = ["omarchy-kids-time"]' "$fixture/manifest.json" >"$collision/manifest.json"
if run_plugin add "$collision" --yes >/dev/null 2>&1; then
  fail "a plugin cannot shadow the built-in time command"
fi
[[ ! -e $plugin_store/fixture ]] || fail "a collision does not create an installed copy"
printf 'keep this command\n' >"$plugin_bindir/omarchy-kids-fixture"
if run_plugin add "$fixture" --yes >/dev/null 2>&1; then
  fail "a plugin cannot overwrite an existing command"
fi
[[ $(<"$plugin_bindir/omarchy-kids-fixture") == "keep this command" ]] || fail "the conflicting command is untouched"
rm "$plugin_bindir/omarchy-kids-fixture"
pass "plugin installation refuses built-in names and existing commands"

# External repositories keep their existing identities during this rename.
legacy="$tmp/legacy"
cp -a "$fixture" "$legacy"
mv "$legacy/bin/omarchy-kids-fixture" "$legacy/bin/omarchy-parent-fixture"
jq '.bins = ["omarchy-parent-fixture"]' "$fixture/manifest.json" >"$legacy/manifest.json"
output=$(run_plugin add "$legacy" --enable --yes)
[[ $output == *"fixture on"* ]] || fail "an existing external plugin can still be enabled"
output=$(OMARCHY_KIDS_PLUGIN_BINDIR="$plugin_bindir" PATH="$plugin_bindir:$ROOT/bin:$PATH" bash "$ROOT/bin/omarchy-kids" fixture on)
[[ $output == "fixture on" ]] || fail "the new kids command routes existing external plugins"
output=$(run_plugin remove fixture)
[[ $output == *"fixture off"* ]] || fail "an existing external plugin is disabled before removal"
pass "external plugins retain their original commands and remain reachable through kids"

git_src="$tmp/fixture-git"
mkdir -p "$git_src"
cp -a "$fixture"/. "$git_src"/
git -C "$git_src" init --quiet
git -C "$git_src" add -A
git -C "$git_src" -c user.email=test@omarchy -c user.name=test commit --quiet -m init
run_plugin add "file://$git_src" --yes >/dev/null || fail "plugin add from a git URL succeeds"
[[ -d $plugin_store/fixture/.git ]] || fail "a git add keeps the clone in the store"
[[ -L $plugin_bindir/omarchy-kids-fixture ]] || fail "a git add puts the command on PATH"
pass "plugin add clones a git URL into the store"

# The migration only restores the extracted LLM plugin for a child machine
# that had already turned the old in-tree recorder on.
migration="$ROOT/migrations/1788416500.sh"
migration_conf="$tmp/parent.conf"
migration_calls="$tmp/migration-calls"
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$MIGRATION_CALLS"
SH
cat >"$stub_bin/omarchy-kids" <<'SH'
#!/bin/bash
printf 'parent %s\n' "$*" >>"$MIGRATION_CALLS"
SH
chmod +x "$stub_bin/sudo" "$stub_bin/omarchy-kids"
printf 'llm=on\n' >"$migration_conf"

run_migration() {
  MIGRATION_CALLS="$migration_calls" \
  OMARCHY_KIDS_CONF="$migration_conf" \
  SUDO_USER= USER=kid PATH="$stub_bin:$PATH" \
  bash -euo pipefail "$migration" >/dev/null
}

: >"$migration_calls"
STUB_PROFILE=default run_migration
[[ ! -s $migration_calls ]] || fail "the LLM extraction migration skips a default install" "$(<"$migration_calls")"
STUB_PROFILE=child run_migration
if (( EUID == 0 )); then
  expected_migration_call="parent plugin add https://github.com/peterholko/omarchy-parent-llm.git --enable --yes --user kid"
else
  expected_migration_call="sudo omarchy-kids plugin add https://github.com/peterholko/omarchy-parent-llm.git --enable --yes --user kid"
fi
[[ $(<"$migration_calls") == "$expected_migration_call" ]] ||
  fail "the migration reinstalls the standalone plugin for an existing child setup" "$(<"$migration_calls")"
pass "the migration preserves an enabled LLM log through the plugin extraction"
