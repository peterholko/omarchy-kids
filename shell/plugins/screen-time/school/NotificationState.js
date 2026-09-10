function parseState(rawText) {
  var fallback = { managed: false, restoreDnd: false }
  var text = String(rawText || "").trim()
  if (!text) return fallback

  try {
    var parsed = JSON.parse(text)
    if (!parsed || parsed.version !== 1 || parsed.managed !== true)
      return fallback
    if (typeof parsed.restoreDnd !== "boolean") return fallback
    return { managed: true, restoreDnd: parsed.restoreDnd }
  } catch (error) {
    return fallback
  }
}

function stateText(managed, restoreDnd) {
  return JSON.stringify({
    version: 1,
    managed: managed === true,
    restoreDnd: restoreDnd === true
  }, null, 2) + "\n"
}

if (typeof module !== "undefined") {
  module.exports = {
    parseState: parseState,
    stateText: stateText
  }
}
