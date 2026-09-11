// Shared by the view and Node tests. Missing policy means standalone play;
// an attached but unavailable service never grants an unlimited fallback.
var OPERATIONS = ["add", "subtract", "multiply", "divide"]
function available(status, operation) {
  return !status || !status.remaining || status.remaining[operation] !== 0
}
function choices(status) { return OPERATIONS.filter(function(op) { return available(status, op) }) }
function sizeFor(operation, size) { return operation === "divide" ? 2 : operation !== "multiply" && size === 1 ? 2 : size }
function nextKind(operation, status, random) {
  var allowed = choices(status)
  return operation !== "mixed" && available(status, operation) ? operation : allowed[Math.floor((random || Math.random)() * allowed.length)]
}
if (typeof module !== "undefined") module.exports = {available: available, choices: choices, sizeFor: sizeFor, nextKind: nextKind}
