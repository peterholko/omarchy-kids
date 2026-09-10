var STOCK_MENU_ID = "omarchy.menu"
var RESTORE_KEY = "schoolMenuRestore"

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function cloneJson(value) {
  return JSON.parse(JSON.stringify(value))
}

function entryId(entry) {
  return String(isObject(entry) ? entry.id || "" : entry || "")
}

function ensureConfigShape(config) {
  if (!isObject(config.bar)) config.bar = ({})
  if (!isObject(config.bar.layout)) config.bar.layout = ({})
  var sections = ["left", "center", "right"]
  for (var i = 0; i < sections.length; i++) {
    if (!Array.isArray(config.bar.layout[sections[i]]))
      config.bar.layout[sections[i]] = []
  }
  if (!Array.isArray(config.plugins)) config.plugins = []
}

function barLocation(config, id) {
  ensureConfigShape(config)
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var entries = config.bar.layout[sections[s]]
    for (var i = 0; i < entries.length; i++) {
      if (entryId(entries[i]) === id)
        return { section: sections[s], index: i, entry: entries[i] }
    }
  }
  return null
}

function removeBarEntries(config, id) {
  ensureConfigShape(config)
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    config.bar.layout[sections[s]] = config.bar.layout[sections[s]].filter(function(entry) {
      return entryId(entry) !== id
    })
  }
}

function normalizedRestore(value) {
  if (!isObject(value)) return null
  if (["left", "center", "right"].indexOf(String(value.section || "")) < 0) return null
  if (!isObject(value.entry) || entryId(value.entry) !== STOCK_MENU_ID) return null
  var numericIndex = Math.floor(Number(value.index))
  if (!isFinite(numericIndex) || numericIndex < 0) numericIndex = 0
  return {
    section: String(value.section),
    index: numericIndex,
    entry: cloneJson(value.entry)
  }
}

function restoreFromPluginEntry(config, pluginId) {
  var location = barLocation(config, pluginId)
  if (!location || !isObject(location.entry)) return null
  return normalizedRestore(location.entry[RESTORE_KEY])
}

function setStockMenuDisabled(config, disabled) {
  var current = Array.isArray(config.disabledPlugins) ? config.disabledPlugins : []
  var next = current.filter(function(id) { return String(id) !== STOCK_MENU_ID })
  if (disabled) next.push(STOCK_MENU_ID)
  if (next.length > 0) config.disabledPlugins = next
  else delete config.disabledPlugins
}

function managerEntry(managerId, managerPath) {
  return { id: managerId, type: "qml", source: managerPath }
}

function ensureManager(config, managerId, managerPath) {
  var existing = barLocation(config, managerId)
  if (existing) {
    config.bar.layout[existing.section][existing.index] = managerEntry(managerId, managerPath)
    return
  }

  var right = config.bar.layout.right
  var insertAt = 0
  for (var i = 0; i < right.length; i++) {
    if (entryId(right[i]) === "omarchy.tray") {
      insertAt = i + 1
      break
    }
  }
  right.splice(insertAt, 0, managerEntry(managerId, managerPath))
}

// Replace only the stock menu's bar slot. This plugin retains its own ID and
// does not claim Omarchy's IPC route. The restore record travels with the
// plugin's bar entry so shell reloads do not lose the user's original slot.
function activate(config, pluginId, managerId, managerPath, kidsModeEnabled) {
  ensureConfigShape(config)
  var pluginLocation = barLocation(config, pluginId)
  if (!pluginLocation) return { restore: null }

  var pluginEntry = isObject(pluginLocation.entry)
    ? cloneJson(pluginLocation.entry)
    : { id: pluginId }
  pluginEntry.id = pluginId

  var restore = normalizedRestore(pluginEntry[RESTORE_KEY])
  var stockLocation = barLocation(config, STOCK_MENU_ID)
  if (!restore && stockLocation) {
    var restoreIndex = stockLocation.index
    if (pluginLocation.section === stockLocation.section
        && pluginLocation.index < stockLocation.index)
      restoreIndex--
    restore = {
      section: stockLocation.section,
      index: Math.max(0, restoreIndex),
      entry: isObject(stockLocation.entry)
        ? cloneJson(stockLocation.entry)
        : { id: STOCK_MENU_ID }
    }
  }

  if (stockLocation) {
    removeBarEntries(config, pluginId)
    removeBarEntries(config, STOCK_MENU_ID)
    if (restore) pluginEntry[RESTORE_KEY] = cloneJson(restore)
    var destination = restore || {
      section: stockLocation.section,
      index: stockLocation.index,
      entry: { id: STOCK_MENU_ID }
    }
    var target = config.bar.layout[destination.section]
    target.splice(Math.min(destination.index, target.length), 0, pluginEntry)
  } else if (restore && isObject(pluginLocation.entry)) {
    pluginLocation.entry[RESTORE_KEY] = cloneJson(restore)
  }

  ensureManager(config, managerId, managerPath)
  setStockMenuDisabled(config, kidsModeEnabled === true)
  return { restore: restore }
}

function deactivate(config, managerId, restoreValue) {
  ensureConfigShape(config)
  removeBarEntries(config, managerId)
  setStockMenuDisabled(config, false)

  var restore = normalizedRestore(restoreValue)
  if (!restore) return

  removeBarEntries(config, STOCK_MENU_ID)
  var target = config.bar.layout[restore.section]
  target.splice(Math.min(restore.index, target.length), 0, cloneJson(restore.entry))
}

// The controls plugin owns one right-hand control and an internal replacement
// for the ordinary Omarchy menu button. Old school widgets collapse here on
// the first load; the saved stock-menu position survives shell restarts.
function activateCombined(config, pluginId, menuPath, schoolActive) {
  ensureConfigShape(config)
  var menuId = pluginId + ".menu"
  var location = barLocation(config, menuId) || barLocation(config, "omarchy.school-mode")
  var restore = location && isObject(location.entry) ? normalizedRestore(location.entry[RESTORE_KEY]) : null
  var stock = barLocation(config, STOCK_MENU_ID)
  if (!restore && stock) restore = { section: stock.section, index: stock.index,
    entry: isObject(stock.entry) ? cloneJson(stock.entry) : {id: STOCK_MENU_ID} }
  if (!restore) restore = { section: "left", index: 0, entry: {id: STOCK_MENU_ID} }
  removeBarEntries(config, STOCK_MENU_ID)
  removeBarEntries(config, "omarchy.school-mode")
  removeBarEntries(config, "omarchy.school-mode.mode")
  removeBarEntries(config, menuId)
  var entry = managerEntry(menuId, menuPath)
  entry[RESTORE_KEY] = cloneJson(restore)
  config.bar.layout[restore.section].splice(Math.min(restore.index, config.bar.layout[restore.section].length), 0, entry)
  if (!barLocation(config, pluginId)) config.bar.layout.right.push({id: pluginId})
  setStockMenuDisabled(config, schoolActive)
  return {restore: restore}
}

function deactivateCombined(config, pluginId, restore) {
  removeBarEntries(config, pluginId + ".menu")
  removeBarEntries(config, "omarchy.school-mode")
  deactivate(config, "omarchy.school-mode.mode", restore)
}

if (typeof module !== "undefined") {
  module.exports = {
    STOCK_MENU_ID: STOCK_MENU_ID,
    RESTORE_KEY: RESTORE_KEY,
    entryId: entryId,
    ensureConfigShape: ensureConfigShape,
    barLocation: barLocation,
    normalizedRestore: normalizedRestore,
    restoreFromPluginEntry: restoreFromPluginEntry,
    setStockMenuDisabled: setStockMenuDisabled,
    activateCombined: activateCombined,
    deactivateCombined: deactivateCombined,
    activate: activate,
    deactivate: deactivate
  }
}
