// Standalone practice facts. Rewards use questions owned by the time service.
function level(value) {
  var n = Math.floor(Number(value))
  return n >= 1 && n <= 6 ? n : 5
}

function hint(grade) {
  grade = level(grade)
  if (grade === 1) return "Addition and subtraction facts to 20"
  if (grade === 2) return "Small facts and the 2–5 times tables"
  if (grade === 3) return "All four operations · tables to 10"
  if (grade === 4) return "All four operations · tables to 12"
  return "Multiplication and division · tables to 12"
}

function shuffle(values, random) {
  var result = values.slice()
  for (var i = result.length - 1; i > 0; i--) {
    var j = Math.floor(random() * (i + 1))
    var value = result[i]; result[i] = result[j]; result[j] = value
  }
  return result
}

function choices(answer, random) {
  var nearby = []
  for (var i = Math.max(0, answer - 12); i <= Math.min(144, answer + 12); i++) {
    if (i !== answer) nearby.push(i)
  }
  return shuffle([answer].concat(shuffle(nearby, random).slice(0, 5)), random)
}

function question(grade, random) {
  grade = level(grade)
  random = random || Math.random
  var ops = grade === 1 ? ["+", "−"] : grade === 2 ? ["+", "−", "×"]
    : grade < 5 ? ["+", "−", "×", "÷"] : ["×", "÷"]
  var op = ops[Math.floor(random() * ops.length)]
  function pick(max) { return 2 + Math.floor(random() * (max - 1)) }
  var max = grade === 3 ? 10 : 12
  var a, b, answer
  if (op === "+" || op === "−") {
    a = pick(10); b = pick(10)
    if (op === "+") answer = a + b
    else { answer = b; a += b; b = a - answer }
  } else if (op === "×") {
    a = pick(grade === 2 ? 5 : max); b = pick(grade === 2 ? 10 : max)
    answer = a * b
  } else {
    b = pick(max); answer = pick(max); a = b * answer
  }
  return { text: a + " " + op + " " + b, answer: answer, choices: choices(answer, random) }
}

if (typeof module !== "undefined") module.exports = { level: level, hint: hint, question: question, choices: choices }
