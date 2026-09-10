#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
run_node_test <<'JS'
const check = require('node:assert/strict')
const model = requireFromRoot('shell/plugins/screen-time/school/ShellIntegration.js')
const patch = requireFromRoot('shell/plugins/screen-time/PatchQueue.js')
const config = {bar: {layout: {
  left: [{id:'custom.clock'}, {id:'omarchy.school-mode', schoolMenuRestore:{section:'left',index:1,entry:{id:'omarchy.menu',custom:42}}}],
  center: [], right: [{id:'omarchy.screen-time',custom:'keep'}, {id:'omarchy.school-mode.mode',type:'qml'}, {id:'other.widget'}]
}},disabledPlugins:['other.plugin','omarchy.menu']}
const restored = model.activateCombined(config,'omarchy.screen-time','/plugin/school/BarWidget.qml',true)
const once = JSON.stringify(config)
model.activateCombined(config,'omarchy.screen-time','/plugin/school/BarWidget.qml',true)
check.equal(JSON.stringify(config),once,'migration is repeatable')
check.deepEqual(config.bar.layout.right,[{id:'omarchy.screen-time',custom:'keep'},{id:'other.widget'}])
check.equal(config.bar.layout.left[1].id,'omarchy.screen-time.menu')
check(config.disabledPlugins.includes('other.plugin'))
model.deactivateCombined(config,'omarchy.screen-time',restored.restore)
check.deepEqual(config.bar.layout.left,[{id:'custom.clock'},{id:'omarchy.menu',custom:42}])
check.deepEqual(config.disabledPlugins,['other.plugin'])
check.deepEqual(patch.merge({budget_minutes:{mon:45},earn:{level:'grade1'}},
  {budget_minutes:{tue:60},earn:{level:'grade7',set_minutes:20}}),
  {budget_minutes:{mon:45,tue:60},earn:{level:'grade7',set_minutes:20}})
check.deepEqual(patch.merge({blocked_periods:[1,2]},{blocked_periods:[3]}),{blocked_periods:[3]})
JS
pass "combined controls preserve the bar, restore the menu and queue rapid settings edits"
