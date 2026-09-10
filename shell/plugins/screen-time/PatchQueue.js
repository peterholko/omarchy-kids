// Keep rapid edits to different days or earning fields in the next request.
// Arrays are complete selections; objects are partial configuration patches.
function merge(current, incoming) {
  var result = Object.assign({}, current || {})
  Object.keys(incoming).forEach(function(key) {
    var value = incoming[key]
    result[key] = value && typeof value === "object" && !Array.isArray(value)
      ? merge(result[key], value) : value
  })
  return result
}
if (typeof module !== "undefined") module.exports = {merge: merge}
