// Long arithmetic as a sequence of required, independently checked steps.
// Place-value arrays run from ones upwards. Qt and the session are consumers.
var PLACES = ["ones", "tens", "hundreds", "thousands", "ten-thousands", "hundred-thousands", "millions"]
var SYMBOLS = { add: "+", subtract: "−", multiply: "×", divide: "÷" }
function length(value) { return String(value).length }
function digit(value, column) { return Math.floor(value / Math.pow(10, column)) % 10 }
function blanks(size) { return Array.from({length: size}, function() { return null }) }
function digits(value, size) { return blanks(size).map(function(_, i) { return i < length(value) ? digit(value, i) : null }) }
function effect(row, column, value) { return {row: row, column: column, value: value} }

function build(a, b, operation) {
  if (operation === "divide") return division(a, b)
  var small = operation === "multiply" && a >= 1 && a <= 9 && b >= 1 && b <= 9
  if (!Number.isInteger(a) || !Number.isInteger(b) || (!small && (a < 10 || b < 10)) || a > 999 || b > 999
      || !SYMBOLS[operation] || (operation === "subtract" && a < b)) throw new Error("Use two- or three-digit whole numbers and a nonnegative result.")
  var answer = operation === "add" ? a + b : operation === "subtract" ? a - b : a * b
  var columns = operation === "multiply" ? length(a) + length(b) : Math.max(length(a), length(b)) + 1
  var board = {top: digits(a, columns), bottom: digits(b, columns), regroup: blanks(columns), result: blanks(columns), sumCarry: blanks(columns)}
  var steps = [], partials = []
  function step(kind, title, expression, expected, hint, effects, column, row, multiplier) {
    steps.push({kind: kind, title: title, expression: expression, expected: expected, hint: hint,
      effects: effects || [], column: column === undefined ? -1 : column, row: row || "result",
      multiplier: multiplier === undefined ? -1 : multiplier})
  }
  function addRows(values, carryRow) {
    var carry = 0, count = Math.max.apply(null, values.map(length))
    for (var i = 0; i < count; i++) {
      var terms = values.map(function(value) { return digit(value, i) })
      var total = terms.reduce(function(sum, n) { return sum + n }, carry)
      var expression = terms.join(" + ") + (carry ? " + " + carry + " carried in" : "")
      step("add-column", "Add the " + PLACES[i] + " column", expression, total,
        "Add the digits in this column, including any carry. Enter the whole column total.",
        [effect("result", i, total % 10)], i)
      carry = Math.floor(total / 10)
      if (carry) {
        var effects = [effect(carryRow, i + 1, carry)]
        if (i === count - 1) effects.push(effect("result", i + 1, carry))
        step("add-carry", "Carry into the " + PLACES[i + 1], total + " " + PLACES[i] + " → how many " + PLACES[i + 1] + "?", carry,
          "Every group of 10 in this column becomes 1 in the column to its left.", effects, i + 1, carryRow)
      }
    }
  }
  if (operation === "add") addRows([a, b], "sumCarry")
  if (operation === "subtract") {
    var top = digits(a, columns).map(function(value) { return value || 0 })
    for (var i = 0; i < Math.max(length(a), length(b)); i++) {
      if (top[i] < digit(b, i)) {
        var donor = i + 1
        while (top[donor] === 0) donor++
        var old = top[donor]
        top[donor]--
        step("borrow-give", "Trade one " + PLACES[donor].replace(/s$/, ""), old + " − 1", top[donor],
          "This column gives one group to the column on its right. Enter the digit left after trading.",
          [effect("regroup", donor, top[donor])], donor, "top")
        for (var k = donor - 1; k >= i; k--) {
          var before = top[k]
          top[k] += 10
          step("borrow-receive", "Regroup the " + PLACES[k], before + " + 10", top[k],
            "One group from the left becomes 10 here. Record this new amount above the crossed-out digit.",
            [effect("regroup", k, top[k])], k, "top")
          if (k > i) {
            top[k]--
            step("borrow-pass", "Pass one group to the right", "10 − 1", top[k],
              "Keep 9 here and trade the other group into 10 for the next column. Record what remains here.",
              [effect("regroup", k, top[k])], k, "top")
          }
        }
      }
      var result = top[i] - digit(b, i)
      step("subtract-column", "Subtract the " + PLACES[i] + " column", top[i] + " − " + digit(b, i), result,
        "Use the regrouped amount above this column when there is one. Subtract bottom from top.",
        [effect("result", i, result)], i)
    }
  }
  if (operation === "multiply") {
    for (var j = 0; j < length(b); j++) {
      var row = "partial" + j, carryRow = "carry" + j, carry = 0, multiplier = digit(b, j)
      board[row] = blanks(columns); board[carryRow] = blanks(columns)
      partials.push(a * multiplier * Math.pow(10, j))
      for (var p = 0; p < j; p++) {
        step("placeholder", "Line up the " + PLACES[j] + " row", "Placeholder in the " + PLACES[p] + " column", 0,
          "A tens row starts one place left, and a hundreds row starts two places left. Fill each empty place on the right with zero.",
          [effect(row, p, 0)], p, row, j)
      }
      for (var i = 0; i < length(a); i++) {
        var product = digit(a, i) * multiplier + carry
        step("multiply-column", "Multiply the " + PLACES[i] + " digit", digit(a, i) + " × " + multiplier + (carry ? " + " + carry + " carried in" : ""), product,
          "Multiply first, then add the carry. Enter the whole total; its last digit goes in this partial-product row.",
          [effect(row, i + j, product % 10)], i + j, row, j)
        carry = Math.floor(product / 10)
        if (carry) {
          var effects = [effect(carryRow, i + 1, carry)]
          if (i === length(a) - 1) effects.push(effect(row, i + j + 1, carry))
          step("multiply-carry", "Record the carry", product + " → carry how many groups of 10?", carry,
            "The last digit stays in this row. Carry the remaining groups of 10 into the next multiplication.",
            effects, i + 1, carryRow, j)
        }
      }
      step("partial-product", "Complete the " + PLACES[j] + " row", a + " × " + (multiplier * Math.pow(10, j)), partials[j],
        "Read the entire row you just built, including its place-value zeros. This is one partial product.", [], -1, row, j)
    }
    addRows(partials, "sumCarry")
  }
  step("final", "One last answer for your guest!", a + " " + SYMBOLS[operation] + " " + b, answer,
    "Read your completed answer row from left to right. Now enter the whole answer.", [], -1)
  return {a: a, b: b, operation: operation, symbol: SYMBOLS[operation], answer: answer, columns: columns,
    partials: partials, steps: steps, board: board}
}

function generate(operation, size, random) {
  if (operation === "divide") {
    if (size !== 2) throw new Error("Division uses two-digit / one-digit table facts.")
    var rng = random || Math.random, pairs = []
    for (var divisor = 2; divisor <= 9; divisor++)
      for (var quotient = 2; quotient <= 9; quotient++)
        if (divisor * quotient >= 10) pairs.push([divisor * quotient, divisor])
    var pair = pairs[Math.floor(rng() * pairs.length)]
    return division(pair[0], pair[1])
  }
  if (["add", "subtract", "multiply"].indexOf(operation) < 0 || ([2, 3].indexOf(size) < 0 && !(operation === "multiply" && size === 1))) throw new Error("Choose an operation and two or three digits.")
  var rng = random || Math.random, low = Math.pow(10, size - 1), range = low * 9
  var a = low + Math.floor(rng() * range), b = low + Math.floor(rng() * range)
  if (operation === "subtract" && a < b) { var swap = a; a = b; b = swap }
  return build(a, b, operation)
}

function division(a, b) {
  if (!Number.isInteger(a) || !Number.isInteger(b) || a < 10 || a > 99 || b < 2 || b > 9 || a % b !== 0 || a / b > 9)
    throw new Error("Use an exact two-digit / one-digit table fact with a one-digit answer.")
  var quotient = a / b
  var board = {top: digits(a, 2), bottom: digits(b, 2), result: blanks(2), product: [null], remainder: [null]}
  function checked(kind, title, expression, expected, hint, effects, row) {
    return {kind: kind, title: title, expression: expression, expected: expected, hint: hint,
      effects: effects || [], column: -1, row: row || "result", multiplier: -1}
  }
  return {a: a, b: b, operation: "divide", symbol: "÷", answer: quotient, columns: 2, partials: [], board: board, steps: [
    checked("divide-groups", "How many equal groups?", b + " × ? = " + a, quotient,
      "Think of the " + b + " times table. How many groups make " + a + "?", [effect("result", 0, quotient)]),
    checked("divide-product", "Check with multiplication", quotient + " × " + b, a,
      "Multiply the number of groups by the size of each group.", [effect("product", 0, a)], "product"),
    checked("divide-remainder", "Check what is left", a + " − " + a, 0,
      "Subtract what you shared. These table facts share equally, with nothing left over.", [effect("remainder", 0, 0)], "remainder"),
    checked("final", "One last answer for your guest!", a + " ÷ " + b, quotient,
      "Enter the number of equal groups. Your multiplication and subtraction checked the answer.")
  ]}
}

if (typeof module !== "undefined") module.exports = {build: build, generate: generate, PLACES: PLACES}
