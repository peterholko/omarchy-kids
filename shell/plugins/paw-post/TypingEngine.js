// Pure typing state. Receives text and timestamps only from this game's window.
function clone(state) { return JSON.parse(JSON.stringify(state)) }
function shuffled(state, values) {
  var result = values.slice()
  for (var i = result.length - 1; i > 0; i--) {
    state.seed = (Math.imul(state.seed, 1664525) + 1013904223) >>> 0
    var j = Math.floor((state.seed / 4294967296) * (i + 1))
    var value = result[i]; result[i] = result[j]; result[j] = value
  }
  return result
}
function create(lesson, mode, prompts, seed) {
  var bank = Array.isArray(prompts) ? prompts.filter(function(text) {
    return typeof text === "string" && text.length > 0 && text.length <= 64 && /^[\x20-\x7e]+$/.test(text)
  }) : []
  var s = {lesson: lesson, mode: mode === "dash" ? "dash" : "cozy", bank: bank,
    seed: seed >>> 0, queue: [], target: "", typed: "", phase: "play", paused: false,
    delivered: 0, goal: 10, completedChars: 0, attempts: 0, correctKeys: 0, mistakes: 0,
    elapsed: 0, limit: 90000, started: false, lastAt: 0, streak: 0, bestStreak: 0,
    letterMistakes: 0, note: "The clock starts with your first letter.", error: false}
  if (!bank.length) { s.phase = "results"; s.note = "This route has no messages yet."; return s }
  return next(s)
}
function next(state) {
  if (state.paused || state.phase === "results") return state
  var s = clone(state)
  if (!s.queue.length) {
    s.queue = shuffled(s, s.bank)
    if (s.queue.length > 1 && s.queue[s.queue.length - 1] === s.target) {
      var first = s.queue[0]; s.queue[0] = s.queue[s.queue.length - 1]; s.queue[s.queue.length - 1] = first
    }
  }
  s.target = s.queue.pop(); s.typed = ""; s.letterMistakes = 0
  s.phase = "play"; s.lastAt = 0; s.error = false
  s.note = s.started ? "A new message for a friend. You've got this." : "Start typing whenever you're ready."
  return s
}
function advance(state, now) {
  if (state.phase !== "play" || state.paused) return state
  var s = clone(state)
  if (!Number.isFinite(now)) return state
  if (s.started && s.lastAt > 0) s.elapsed += Math.max(0, now - s.lastAt)
  s.lastAt = now
  if (s.mode === "dash" && s.elapsed >= s.limit) {
    s.elapsed = s.limit; s.phase = "results"; s.note = "Your sky dash is complete. Lovely delivering!"
  }
  return s
}
function type(state, character, now) {
  if (state.phase !== "play" || state.paused) return state
  var s = advance(state, now)
  if (s.phase !== "play") return s
  s = clone(s)
  if (typeof character !== "string" || character.length !== 1 || !/^[\x20-\x7e]$/.test(character)) {
    s.note = "Type one key at a time to practise."; return s
  }
  s.started = true; s.lastAt = now; s.attempts++
  var matches = s.typed.length < s.target.length && s.target[s.typed.length] === character
  if (matches) s.correctKeys++
  else { s.mistakes++; s.letterMistakes++; s.streak = 0 }
  if (s.typed.length < s.target.length) s.typed += character
  s.error = s.typed !== s.target.slice(0, s.typed.length)
  s.note = s.error ? "No rush. Backspace to fix the pink letters." : "Nice and steady. Every letter counts."
  if (s.typed === s.target) {
    s.delivered++; s.completedChars += s.target.length
    if (s.letterMistakes === 0) { s.streak++; s.bestStreak = Math.max(s.bestStreak, s.streak) }
    s.phase = s.mode === "cozy" && s.delivered >= s.goal ? "results" : "delivery"
    s.note = s.letterMistakes === 0 ? "A perfect delivery!" : "Delivered! Great job finding and fixing that."
  }
  return s
}
function backspace(state, now) {
  if (state.phase !== "play" || state.paused) return state
  var s = advance(state, now)
  if (s.phase !== "play") return s
  s = clone(s)
  s.typed = s.typed.slice(0, -1)
  s.error = s.typed !== s.target.slice(0, s.typed.length)
  s.note = s.error ? "Backspace to fix the pink letters." : "Ready when you are."
  return s
}
function pause(state, now) {
  if (state.phase === "results") return state
  var s = advance(state, now)
  if (s.phase === "results") return s
  s = clone(s); s.paused = !s.paused; s.lastAt = now
  return s
}
function accuracy(state) { return state.attempts ? Math.round(100 * state.correctKeys / state.attempts) : 100 }
function progress(state) {
  var count = 0
  while (count < state.typed.length && state.typed[count] === state.target[count]) count++
  return count
}
function wpm(state) {
  if (state.elapsed < 1000) return 0
  var partial = state.phase === "play" || (state.phase === "results" && state.mode === "dash") ? progress(state) : 0
  return Math.round((state.completedChars + partial) / 5 / (state.elapsed / 60000))
}
function badge(state) {
  if (state.delivered === 0) return {title: "First flight", detail: "You showed up and practised. Your next letter is waiting."}
  if (accuracy(state) >= 98) return {title: "Careful courier", detail: "Beautifully accurate typing. Keep that gentle rhythm."}
  if (state.bestStreak >= 3) return {title: "Trail of stars", detail: "Three perfect deliveries in a row. That's a lovely streak!"}
  return {title: "Kindness delivered", detail: "Every message you finished made someone's day."}
}
if (typeof module !== "undefined") module.exports = {create: create, next: next, type: type, backspace: backspace, advance: advance, pause: pause, accuracy: accuracy, progress: progress, wpm: wpm, badge: badge}
