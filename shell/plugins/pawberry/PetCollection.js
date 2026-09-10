// Pure collection rules; arithmetic and persistence live in separate modules.
function empty() { return {version: 1, pets: [], accessories: [], outfits: {}, completed: 0} }
function copy(value) { return JSON.parse(JSON.stringify(value)) }
function knownUnique(values, allowed) {
  return Array.isArray(values) ? values.filter(function(id, index) {
    return typeof id === "string" && allowed.indexOf(id) !== -1 && values.indexOf(id) === index
  }) : []
}
function restore(raw, petIds, accessoryIds) {
  var data
  try { data = typeof raw === "string" ? JSON.parse(raw) : raw } catch (_) { return empty() }
  if (!data || data.version !== 1) return empty()
  var result = empty()
  result.pets = knownUnique(data.pets, petIds)
  result.accessories = knownUnique(data.accessories, accessoryIds)
  result.completed = typeof data.completed === "number" && isFinite(data.completed) ? Math.max(0, Math.floor(data.completed)) : 0
  if (data.outfits && typeof data.outfits === "object") result.pets.forEach(function(id) {
    if (result.accessories.indexOf(data.outfits[id]) !== -1) result.outfits[id] = data.outfits[id]
  })
  return result
}
function shuffle(values, random) {
  var result = values.slice(), rng = random || Math.random
  for (var i = result.length - 1; i > 0; i--) {
    var j = Math.floor(rng() * (i + 1)), item = result[i]
    result[i] = result[j]; result[j] = item
  }
  return result
}
function guests(state, petIds, count, random) {
  // Meet every new friend before return guests fill the remaining rooms.
  var unseen = petIds.filter(function(id) { return state.pets.indexOf(id) === -1 })
  var known = petIds.filter(function(id) { return state.pets.indexOf(id) !== -1 })
  return shuffle(unseen, random).concat(shuffle(known, random)).slice(0, count)
}
function award(state, petId, accessoryIds, random) {
  var next = copy(state), isNew = next.pets.indexOf(petId) === -1
  if (isNew) next.pets.push(petId)
  next.completed++
  var available = accessoryIds.filter(function(id) { return next.accessories.indexOf(id) === -1 })
  var accessoryId = available.length ? available[Math.floor((random || Math.random)() * available.length)] : ""
  if (accessoryId) next.accessories.push(accessoryId)
  return {collection: next, petId: petId, newPet: isNew, accessoryId: accessoryId}
}
function equip(state, petId, accessoryId) {
  if (state.pets.indexOf(petId) === -1 || (accessoryId && state.accessories.indexOf(accessoryId) === -1)) return state
  var next = copy(state)
  if (accessoryId) next.outfits[petId] = accessoryId
  else delete next.outfits[petId]
  return next
}
if (typeof module !== "undefined") module.exports = {empty: empty, restore: restore, guests: guests, award: award, equip: equip}
