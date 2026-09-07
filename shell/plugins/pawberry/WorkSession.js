// A final answer is reachable only after every intermediate step was checked.
// Problems are supplied by WorkSteps; there are no Qt, backend or reward calls.
function clone(value) { return JSON.parse(JSON.stringify(value)) }
function create(problems) {
  if (!Array.isArray(problems) || problems.length === 0) throw new Error("A mission needs problems.")
  return {phase: "work", problems: clone(problems), problemIndex: 0, stepIndex: 0, board: clone(problems[0].board),
    ledger: [], attempts: 0, mistakes: 0, checked: 0, rooms: 0, paused: false, note: "", error: false}
}
function current(state) { return state.problems[state.problemIndex] }
function activeStep(state) { return current(state).steps[state.stepIndex] || null }
function submit(state, input) {
  if (state.phase !== "work" || state.paused) return state
  var next = clone(state), step = activeStep(next), raw = String(input).trim()
  if (!/^[0-9]{1,7}$/.test(raw)) { next.note = "Enter a whole number for this step."; next.error = true; return next }
  next.attempts++
  if (Number(raw) !== step.expected) {
    next.mistakes++; next.error = true
    next.note = "That step needs another look. Your checked work is safe."
    return next
  }
  for (var i = 0; i < step.effects.length; i++) {
    var change = step.effects[i]
    next.board[change.row][change.column] = change.value
  }
  next.ledger.push({title: step.title, expression: step.expression, value: Number(raw), kind: step.kind})
  next.checked++; next.stepIndex++; next.error = false
  next.note = "Step checked. A little more comfort for your pet!"
  if (step.kind === "final") { next.phase = "complete"; next.rooms++; next.note = "Every step checked. One very cozy pet!" }
  return next
}
function advance(state) {
  if (state.phase !== "complete" || state.paused) return state
  var next = clone(state)
  if (next.problemIndex + 1 === next.problems.length) next.phase = "results"
  else {
    next.problemIndex++; next.stepIndex = 0; next.board = clone(current(next).board)
    next.ledger = []; next.phase = "work"; next.note = "A new guest is ready to meet you."; next.error = false
  }
  return next
}
function pause(state, value) { var next = clone(state); next.paused = value; return next }
if (typeof module !== "undefined") module.exports = {create: create, current: current, activeStep: activeStep, submit: submit, advance: advance, pause: pause}
