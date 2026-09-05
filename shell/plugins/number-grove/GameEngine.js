// Pure game state: no shell, filesystem, network, or screen-time dependencies.
var COLUMNS = 7
var ROWS = 5
var HOME = 31

function copy(state) { return JSON.parse(JSON.stringify(state)) }
function random(state) {
  state.seed = (Math.imul(state.seed, 1664525) + 1013904223) >>> 0
  return state.seed / 4294967296
}
function shuffled(state, values) {
  var result = values.slice()
  for (var i = result.length - 1; i > 0; i--) {
    var j = Math.floor(random(state) * (i + 1))
    var value = result[i]; result[i] = result[j]; result[j] = value
  }
  return result
}
function create(grade, mode, total, seed) {
  return { grade: grade, mode: mode, total: Math.max(1, Math.min(50, total)), seed: seed >>> 0,
    phase: "waiting", answered: 0, correct: 0, hearts: 3, score: 0, streak: 0,
    earned: 0, player: HOME, bugs: [], stones: [], tiles: [], shield: 0,
    question: null, message: "Finding a fresh seed…", good: false }
}
function difficulty(state) { return Math.min(4, 1 + Math.floor(state.correct / 3)) }
function interval(state) { return 1600 - (difficulty(state) - 1) * 220 }

function board(state, question) {
  var s = copy(state)
  if (!question || typeof question.text !== "string" || !Array.isArray(question.choices)
      || question.choices.length !== 6 || question.choices.some(function(v) {
        return typeof v !== "number" || v < 0 || v > 144 || v % 1 !== 0
      }) || question.choices.some(function(v, i) { return question.choices.indexOf(v) !== i })) {
    s.phase = "error"; s.message = "The question could not be loaded. Try a new round."; return s
  }
  s.question = question; s.player = HOME; s.shield = 2
  s.stones = shuffled(s, [0, 6, 28, 34]).slice(0, 2)
  s.tiles = Array(COLUMNS * ROWS).fill(null)
  var free = []
  for (var i = 0; i < s.tiles.length; i++) if (i !== HOME && s.stones.indexOf(i) < 0) free.push(i)
  free = shuffled(s, free)
  for (i = 0; i < question.choices.length; i++) s.tiles[free[i]] = question.choices[i]
  var bugCells = []
  for (i = 0; i < COLUMNS * 3; i++) {
    if (s.tiles[i] === null && s.stones.indexOf(i) < 0) bugCells.push(i)
  }
  s.bugs = shuffled(s, bugCells).slice(0, 1 + Math.floor((difficulty(s) - 1) / 2))
  s.phase = "play"; s.message = "Walk to the answer, then press Space to collect it."; s.good = false
  return s
}
function neighbour(position, dx, dy) {
  var x = position % COLUMNS + dx, y = Math.floor(position / COLUMNS) + dy
  return x >= 0 && x < COLUMNS && y >= 0 && y < ROWS ? y * COLUMNS + x : -1
}
function bump(s) {
  if (s.shield > 0 || s.bugs.indexOf(s.player) < 0) return
  s.hearts--; s.streak = 0; s.shield = 3
  s.player = HOME
  // A bug may have crossed home. Choose another safe cell before continuing.
  for (var i = s.tiles.length - 1; s.bugs.indexOf(s.player) >= 0 && i >= 0; i--) {
    if (s.stones.indexOf(i) < 0 && s.bugs.indexOf(i) < 0) s.player = i
  }
  s.message = "A drift bug bumped you. You have a moment to get clear."
  if (s.hearts <= 0) s.phase = "results"
}
function move(state, dx, dy) {
  if (state.phase !== "play" || Math.abs(dx) + Math.abs(dy) !== 1) return state
  var s = copy(state), next = neighbour(s.player, dx, dy)
  if (next < 0 || s.stones.indexOf(next) >= 0) return state
  s.player = next; bump(s)
  return s
}
function tick(state) {
  if (state.phase !== "play") return state
  var s = copy(state)
  if (s.shield > 0) s.shield--
  for (var i = 0; i < s.bugs.length; i++) {
    var directions = shuffled(s, [[1, 0], [-1, 0], [0, 1], [0, -1]])
    for (var d = 0; d < directions.length; d++) {
      var next = neighbour(s.bugs[i], directions[d][0], directions[d][1])
      if (next >= 0 && s.stones.indexOf(next) < 0 && s.bugs.indexOf(next) < 0) {
        s.bugs[i] = next; break
      }
    }
  }
  bump(s)
  return s
}
function collect(state) {
  if (state.phase !== "play") return state
  var s = copy(state)
  if (s.tiles[s.player] === null) {
    s.message = "Find a numbered seed first."; return s
  }
  s.phase = "checking"; s.message = "Checking your answer…"
  return s
}
function verdict(state, result) {
  if (state.phase !== "checking") return state
  var s = copy(state)
  if (!result || result.ok !== true) {
    var error = result && result.error
    if (error === "too_fast") {
      s.phase = "play"; s.message = "Take a moment, then collect that seed again."
    } else if (error === "expired" || error === "no_such_question") {
      s.phase = "feedback"; s.message = "That question expired. Let's try a fresh one."; s.good = false
    } else {
      s.phase = "error"; s.message = "Rewards could not be confirmed. Try again or start a practice round."
    }
    return s
  }
  s.answered++; s.good = result.correct === true
  if (s.good) {
    s.correct++; s.streak++; s.score += 100 + Math.min(5, s.streak - 1) * 20
    s.earned += Math.max(0, Number(result.reward_seconds) || 0)
    s.message = "Correct! Another seed for your grove."
  } else {
    s.hearts--; s.streak = 0
    s.message = s.question.text + " = " + result.answer + ". Keep that fact for next time."
  }
  s.phase = s.answered >= s.total || s.hearts <= 0 ? "results" : "feedback"
  return s
}
function waiting(state) {
  var s = copy(state); s.phase = "waiting"; s.message = "Finding a fresh seed…"; return s
}
function failure(state, message) {
  var s = copy(state); s.phase = "error"; s.message = message; return s
}
if (typeof module !== "undefined") module.exports = {
  COLUMNS: COLUMNS, ROWS: ROWS, HOME: HOME, create: create, board: board, move: move,
  tick: tick, collect: collect, verdict: verdict, difficulty: difficulty, interval: interval,
  waiting: waiting, failure: failure, neighbour: neighbour
}
