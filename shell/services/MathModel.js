// Math time (plans/kids-screen-time.md), the arithmetic app of a child
// install: pure logic shared by the QML view and the tests. Root's
// omarchy-kids-quiz owns the budget and checks the answers that earn time;
// a practice answer is checked here, against the answer the generator handed
// the app beside the question. Loadable by Node for the tests and by QML.

var GRADES = [1, 2, 3, 4, 5, 6, 7]
var PRACTICE_COUNT = 10

// The sheet: white paper and dark ink, the same on every theme. Blue marks
// the picked grade and the field, green a right answer, red a miss.
var PALETTE = {
  paper: "#ffffff",
  ink: "#1c1c1e",
  inkSoft: "#6b6b73",
  rule: "#d9d9de",
  mark: "#2f6fed",
  good: "#1e8e3e",
  bad: "#c62828"
}

// omarchy-kids-quiz prints status.json: {"enabled":true,"school":false,
// "budget":540,"level":"grade5",...}. Gated means the kid has to earn time
// before the desktop is hers; school hours lift the gate whatever the budget.
function gateFromStatus(raw, childInstall) {
  var status = {}
  try {
    status = JSON.parse(String(raw || "")) || {}
  } catch (e) {
    status = {}
  }
  // Accept both the public status file and a fresh daemon status reply.
  var earn = status.earn || {}
  var enabled = status.enabled === true || (status.ok === true && status.remaining_seconds !== undefined)
  var school = status.mode === "school" || status.school === true || status.phase === "school"
  var earning = status.earning !== false && earn.enabled !== false && status.philosophy !== "together"
    && (earn.room_seconds === undefined || Number(earn.room_seconds) > 0)
  var budget = Number(status.budget !== undefined ? status.budget : status.remaining_seconds) || 0
  if (budget < 0) budget = 0
  var rate = Number(status.rate || earn.set_minutes / earn.questions_per_set) || 6
  var questions = Number(status.questions || earn.questions_per_set) || 5
  var sessionMinutes = Number(status.sessionMinutes || earn.set_minutes) || rate * questions
  return {
    enabled: enabled,
    school: school,
    budget: budget,
    gated: !!childInstall && enabled && !school && !status.paused && status.phase !== "paused" && status.phase !== "bedtime" && earning && budget <= 0,
    earning: earning && !school,
    earnedToday: Number(status.earnedToday) || 0,
    usedToday: Number(status.usedToday) || 0,
    rate: rate,
    questions: questions,
    sessionMinutes: sessionMinutes,
    creditSeconds: Number(status.creditSeconds) || Math.floor(sessionMinutes * 60 / questions),
    cap: Number(status.cap) || 0,
    level: levelName(levelNumber(status.level || earn.level))
  }
}

// The lock service marks the zero-budget handoff. Launcher, menu, and panel
// summons carry no such mark and remain ordinary child-opened sessions.
function isForcedOpen(payloadJson) {
  var payload = {}
  try {
    payload = JSON.parse(String(payloadJson || "{}")) || {}
  } catch (e) {
    payload = {}
  }
  return payload.forced === true
}

// Levels are grade1 to grade7 on the root side; the app thinks in numbers.
function levelNumber(level) {
  var match = String(level || "").match(/^grade([1-7])$/)
  return match ? Number(match[1]) : 5
}

function levelName(grade) {
  var n = Number(grade)
  if (!(n >= 1 && n <= 7)) n = 5
  return "grade" + n
}

function gradeLabel(grade) {
  return "Grade " + levelNumber(levelName(grade))
}

function gradeBlurb(grade) {
  switch (levelNumber(levelName(grade))) {
    case 1: return "Bonds to 5 and 10, addition and subtraction within 10"
    case 2: return "Facts within 20, doubles and near doubles"
    case 3: return "Facts within 20; the 0, 1, 2, 5 and 10 tables"
    case 4: return "Multiplication and division facts through 10 × 10"
    case 5: return "Core tables, especially 3, 4, 6, 7, 8 and 9; familiar fractions"
    case 6: return "Core tables, fractions, decimals, percentages and divisibility"
    default: return "Core facts, signed tables and more fraction equivalents"
  }
}

// The daemon's answers, as JSON lines from omarchy-kids-time-client.
// `quiz` prints {ok, question: {id, text, reward_seconds}} or {ok: false,
// error}; `practice` prints {ok, text, answer}.
function parseQuestionJson(raw) {
  var payload
  try {
    payload = JSON.parse(String(raw || ""))
  } catch (e) {
    return { error: "no_daemon" }
  }
  if (!payload || payload.ok !== true) return { error: String((payload && payload.error) || "no_daemon") }
  if (payload.question && payload.question.text) {
    return { id: String(payload.question.id || ""), text: String(payload.question.text), answer: "", hint: String(payload.question.hint || "") }
  }
  if (payload.text) return { id: "", text: String(payload.text), answer: String(payload.answer), hint: String(payload.hint || "") }
  return { error: "no_question" }
}

// The client's own failures come as "no daemon: <reason>", and the app adds
// two of its own: a client that could not start, and one that never answered.
// An unfamiliar reason is shown, so a parent testing sees what went wrong.
function questionErrorText(question) {
  var error = question && question.error ? String(question.error) : "no_daemon"
  switch (error) {
    case "daily_cap_reached": return "You have earned today's limit. Practise instead, or come back tomorrow."
    case "school_mode_active": return "School Mode is on. Math practice is optional; earning resumes in Free Time."
    case "earning_disabled": return "Earning is switched off. Practise instead."
    case "not_managed": return "Screen time is not on for this account."
    case "daemon_timeout": return "Screen time did not answer. Press Enter to try again."
    case "failed_to_start": return "Could not start the screen-time client. Press Enter to try again."
    case "no_daemon": return "Could not get a question. Press Enter to try again."
    default: return "Could not get a question (" + error + "). Press Enter to try again."
  }
}

// `answer` prints the daemon's verdict: {ok, correct, answer, reward_seconds,
// remaining_seconds}, or {ok: false, error} for too_fast, expired, and the
// rest. A miss reveals the answer at once: an earning question has one try.
function parseVerdictJson(raw) {
  var payload
  try {
    payload = JSON.parse(String(raw || ""))
  } catch (e) {
    return { kind: "error" }
  }
  if (!payload) return { kind: "error" }
  if (payload.ok === true) {
    if (payload.correct === true) return { kind: "correct", credited: Number(payload.reward_seconds) || 0, budget: Number(payload.remaining_seconds) || 0 }
    return { kind: "wrong", expected: String(payload.answer) }
  }
  switch (payload.error) {
    case "school_mode_active": return { kind: "school" }
    case "not_a_number": return { kind: "invalid" }
    case "too_fast": return { kind: "too_fast", wait: Number(payload.wait_seconds) || 1 }
    case "expired":
    case "no_such_question": return { kind: "stale" }
    default: return { kind: "error" }
  }
}

// `question` prints "<id> <text>".
function parseQuestion(line) {
  var match = String(line || "").trim().match(/^(\d+)\s+(.+)$/)
  if (!match) return null
  return { id: match[1], text: match[2] }
}

// `practice` prints "<text>\t<answer>": the app checks these itself.
function parsePractice(line) {
  var parts = String(line || "").replace(/\r?\n$/, "").split("\t")
  if (parts.length < 2) return null
  var text = parts[0].trim()
  var answer = parts[1].trim()
  if (!text || parseNumber(answer) === null) return null
  return { text: text, answer: answer }
}

// Keep meaningful signs and punctuation. Invalid input must not turn into a
// different valid number just because some characters were stripped away.
function normalizeAnswer(text) {
  return String(text === undefined || text === null ? "" : text).trim().toLowerCase().replace(/−/g, "-")
}

function gcd(a, b) {
  a = Math.abs(a); b = Math.abs(b)
  while (b) { var next = a % b; a = b; b = next }
  return a || 1
}

function parseNumber(value) {
  var text = normalizeAnswer(value)
  if (text.length > 40) return null
  if (text === "yes" || text === "no") return text
  var percent = /%$/.test(text)
  if (percent) text = text.slice(0, -1).trim()
  var numerator, denominator = 1
  var mixed = text.match(/^([+-]?\d{1,7})\s+(\d{1,7})\/(\d{1,7})$/)
  var fraction = text.match(/^([+-]?\d{1,7})\/(\d{1,7})$/)
  var decimal = text.match(/^[+-]?(?:\d{1,7}(?:\.\d{0,7})?|\.\d{1,7})$/)
  if (mixed) {
    denominator = Number(mixed[3])
    numerator = Math.abs(Number(mixed[1])) * denominator + Number(mixed[2])
    if (mixed[1][0] === "-") numerator = -numerator
  } else if (fraction) {
    numerator = Number(fraction[1]); denominator = Number(fraction[2])
  } else if (decimal) {
    var places = text.indexOf(".") < 0 ? 0 : text.length - text.indexOf(".") - 1
    denominator = Math.pow(10, places)
    numerator = Number(text.replace(".", ""))
  } else return null
  if (percent) denominator *= 100
  if (!denominator || !Number.isSafeInteger(numerator) || !Number.isSafeInteger(denominator)) return null
  var divisor = gcd(numerator, denominator)
  return [numerator / divisor, denominator / divisor]
}

function sameAnswer(given, expected) {
  var a = parseNumber(given), b = parseNumber(expected)
  if (a === null || b === null) return false
  if (typeof a === "string" || typeof b === "string") return a === b
  return a[0] === b[0] && a[1] === b[1]
}

// Omacalc sets both its application name and desktop-file name to `omacalc`.
// Match the Wayland app id without confusing it with other calculators.
function isCalculatorAppId(value) {
  var appId = String(value || "").trim().toLowerCase()
  return appId === "omacalc" || appId === "omacalc.desktop"
}

// `answer` prints "correct <credit-seconds> <budget-seconds>", "wrong",
// "wrong <expected>", or "stale".
function parseAnswer(line) {
  var parts = String(line || "").trim().split(/\s+/)
  switch (parts[0]) {
    case "correct":
      return { kind: "correct", credited: Number(parts[1]) || 0, budget: Number(parts[2]) || 0 }
    case "wrong":
      return { kind: "wrong", expected: parts.length > 1 ? parts[1] : "" }
    case "stale":
      return { kind: "stale" }
    default:
      return { kind: "error" }
  }
}

// A practice answer, judged the way root judges an earning one: a first
// miss keeps the question, a second reveals the answer and moves on.
function judgePractice(answerText, expected, attempts) {
  var given = normalizeAnswer(answerText)
  if (parseNumber(given) === null) return { kind: "invalid" }
  if (sameAnswer(given, expected)) return { kind: "correct", credited: 0, budget: 0 }
  return { kind: "wrong", expected: (Number(attempts) || 0) + 1 >= 2 ? String(expected) : "" }
}

function minutes(seconds) {
  return Math.ceil((Number(seconds) || 0) / 60)
}

// Seconds as "30 min", "7 min 30 s", or "45 s".
function formatMinutes(seconds) {
  var s = Math.max(0, Math.round(Number(seconds) || 0))
  if (s % 60 === 0) return (s / 60) + " min"
  if (s < 60) return s + " s"
  return Math.floor(s / 60) + " min " + (s % 60) + " s"
}

// The banner under the field after an answer. A right answer is just that,
// in either mode; the screen time it earned is told at the end of the set.
function feedbackFor(result, mode) {
  if (!result) return ""
  switch (result.kind) {
    case "invalid":
      return "Use a number, decimal, fraction (1/2), percentage (50%), or yes/no."
    case "school":
      return "School Mode is on. Practice is optional."
    case "correct":
      return "Correct!"
    case "wrong":
      return result.expected ? "The answer is " + result.expected + "." : "Not quite. Try once more."
    case "stale":
      return "That one timed out. Here is a fresh one."
    case "too_fast":
      return "Too fast. Read it again and answer in a moment."
    default:
      return "Could not check that. Press Enter to try again."
  }
}

function feedback(result) {
  return feedbackFor(result, "earn")
}

// After an answer: keep asking while still gated, and always after a stale,
// retired, or errored question. A wrong first attempt keeps the question.
function needsNewQuestion(result, gated) {
  if (!result) return true
  if (result.kind === "wrong" && !result.expected) return false
  return gated || result.kind !== "correct"
}

function remainingLabel(seconds) {
  var m = minutes(seconds)
  if (m <= 0) return "No time left"
  return m + " min left"
}

// A session is `total` questions; a question counts once it is answered
// right or retired after two misses. A stale one is replaced and not counted.
function questionDone(result) {
  if (!result) return false
  return result.kind === "correct" || (result.kind === "wrong" && !!result.expected)
}

function progressLabel(answered, total) {
  var n = Math.min(answered + 1, total)
  return "Question " + n + " of " + total
}

function streakLabel(streak) {
  var n = Number(streak) || 0
  return n >= 2 ? n + " in a row" : ""
}

function formatDuration(seconds) {
  var s = Math.max(0, Math.round(Number(seconds) || 0))
  var m = Math.floor(s / 60)
  if (m === 0) return s + " s"
  return m + " min " + (s % 60) + " s"
}

// What the results screen says once the set is done.
function resultsSummary(right, total, seconds, earnedMinutes, budgetSeconds) {
  var line = "You got " + right + " of " + total + " right in " + formatDuration(seconds) + "."
  if (earnedMinutes > 0) line += " +" + earnedMinutes + " min."
  else line += " No minutes this time."
  line += " " + minutes(budgetSeconds) + " min banked."
  return line
}

// The results screen, one line per fact: the score always, the best run when
// there was one, and, when the set was earning, the screen time it gained
// and what is banked now. Never how long it took: a clock is stress.
function sessionSummary(mode, right, total, earnedSeconds, budgetSeconds, bestStreak) {
  var lines = [right + " of " + total + " right"]
  if ((Number(bestStreak) || 0) >= 2) lines.push("Best run: " + bestStreak + " in a row")
  if (mode === "earn") {
    lines.push(earnedSeconds > 0 ? "+" + formatMinutes(earnedSeconds) + " of screen time earned" : "No screen time earned this time")
    lines.push(minutes(budgetSeconds) + " min banked")
  }
  return lines
}

if (typeof module !== "undefined") {
  module.exports = {
    GRADES: GRADES,
    PRACTICE_COUNT: PRACTICE_COUNT,
    PALETTE: PALETTE,
    gateFromStatus: gateFromStatus,
    isForcedOpen: isForcedOpen,
    levelNumber: levelNumber,
    levelName: levelName,
    gradeLabel: gradeLabel,
    gradeBlurb: gradeBlurb,
    parseQuestion: parseQuestion,
    parsePractice: parsePractice,
    parseQuestionJson: parseQuestionJson,
    questionErrorText: questionErrorText,
    parseVerdictJson: parseVerdictJson,
    normalizeAnswer: normalizeAnswer,
    parseNumber: parseNumber,
    sameAnswer: sameAnswer,
    isCalculatorAppId: isCalculatorAppId,
    parseAnswer: parseAnswer,
    judgePractice: judgePractice,
    feedbackFor: feedbackFor,
    feedback: feedback,
    needsNewQuestion: needsNewQuestion,
    remainingLabel: remainingLabel,
    questionDone: questionDone,
    progressLabel: progressLabel,
    streakLabel: streakLabel,
    formatDuration: formatDuration,
    formatMinutes: formatMinutes,
    resultsSummary: resultsSummary,
    sessionSummary: sessionSummary,
    minutes: minutes
  }
}
