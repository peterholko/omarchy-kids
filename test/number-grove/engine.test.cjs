const test = require('node:test')
const assert = require('node:assert/strict')
const Facts = require('../../shell/plugins/number-grove/Facts.js')
const Game = require('../../shell/plugins/number-grove/GameEngine.js')
const question = {id: 'q1', text: '7 × 8', choices: [42, 48, 54, 56, 63, 72]}
function fresh(seed = 42, total = 10) { return Game.board(Game.create(5, 'practice', total, seed), question) }
function atAnswer(state, answer = 56) { return {...state, player: state.tiles.indexOf(answer)} }
function answer(state, correct = true) { return Game.verdict(Game.collect(atAnswer(state)), {ok: true, correct, answer: 56, reward_seconds: 30}) }

test('every grade generates recall facts with six distinct, bounded choices', () => {
  let seed = 29
  const random = () => ((seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0) / 4294967296)
  for (let grade = 1; grade <= 6; grade++) {
    const seen = new Set()
    for (let i = 0; i < 1500; i++) {
      const q = Facts.question(grade, random)
      const [left, op, right] = q.text.split(' '), a = Number(left), b = Number(right)
      const expected = op === '+' ? a + b : op === '−' ? a - b : op === '×' ? a * b : a / b
      assert.equal(q.answer, expected)
      assert(Number.isInteger(expected))
      assert.equal(q.choices.length, 6)
      assert.equal(new Set(q.choices).size, 6)
      assert(q.choices.includes(expected))
      assert(q.choices.every(n => Number.isInteger(n) && n >= 0 && n <= 144))
      if (grade >= 5) assert(['×', '÷'].includes(op))
      if (op === '+') assert(a <= 10 && b <= 10)
      if (op === '−') assert(a <= 20 && b <= 10)
      if (grade === 3 && op === '×') assert(a <= 10 && b <= 10)
      if (grade === 2 && op === '×') assert(a <= 5 && b <= 10)
      seen.add(op)
    }
    assert.equal(seen.size, grade === 1 || grade >= 5 ? 2 : grade === 2 ? 3 : 4)
  }
})

test('every seed is reachable and characters never spawn on a number', () => {
  for (let seed = 1; seed <= 400; seed++) {
    const s = fresh(seed)
    assert.equal(s.tiles[s.player], null)
    assert(s.bugs.every(b => s.tiles[b] === null && !s.stones.includes(b)))
    const visited = new Set([s.player]), pending = [s.player]
    while (pending.length) {
      const cell = pending.shift()
      for (const [dx, dy] of [[1,0], [-1,0], [0,1], [0,-1]]) {
        const next = Game.neighbour(cell, dx, dy)
        if (next >= 0 && !s.stones.includes(next) && !visited.has(next)) { visited.add(next); pending.push(next) }
      }
    }
    s.tiles.forEach((value, cell) => { if (value !== null) assert(visited.has(cell)) })
    assert.deepEqual(s, fresh(seed))
  }
})

test('movement respects edges and stones; collecting empty ground is harmless', () => {
  let s = fresh()
  assert.equal(Game.neighbour(6, 1, 0), -1)
  assert.equal(Game.neighbour(7, -1, 0), -1)
  assert.equal(Game.neighbour(0, 0, -1), -1)
  assert.equal(Game.neighbour(34, 0, 1), -1)
  assert.equal(Game.move(s, 1, 1), s)
  s = {...s, player: 1, stones: [0]}
  assert.equal(Game.move(s, -1, 0), s)
  const empty = Game.collect(fresh())
  assert.equal(empty.phase, 'play')
  assert.equal(empty.hearts, 3)
})

test('collision costs one heart and respawns safely with a shield', () => {
  let s = {...fresh(), player: 30, bugs: [31], shield: 0}
  s = Game.move(s, 1, 0)
  assert.equal(s.hearts, 2)
  assert(!s.bugs.includes(s.player))
  assert(s.shield > 0)
  s = {...s, player: 30}
  assert.equal(Game.move(s, 1, 0).hearts, 2)
  s = {...s, hearts: 1, shield: 0}
  assert.equal(Game.move(s, 1, 0).phase, 'results')
})

test('bugs stay in bounds and clear of stones and each other as difficulty increases', () => {
  let s = fresh()
  for (let i = 0; i < 10; i++) {
    s = answer(s)
    if (s.phase !== 'results') s = Game.board(s, question)
  }
  assert.equal(s.phase, 'results')
  assert.equal(s.correct, 10)
  assert(Game.interval(s) < Game.interval(fresh()))
  s = Game.board(s, question)
  assert.equal(s.bugs.length, 2)
  s.hearts = 1000
  for (let i = 0; i < 200; i++) {
    s = Game.tick(s)
    assert(s.bugs.every(b => b >= 0 && b < 35 && !s.stones.includes(b)))
    assert.equal(new Set(s.bugs).size, s.bugs.length)
  }
})

test('answers update one time, teach missed facts, and stop after the goal or three misses', () => {
  let s = answer(fresh())
  assert.equal(s.correct, 1)
  assert.equal(s.score, 100)
  assert.equal(s.earned, 30)
  assert.equal(Game.verdict(s, {ok: true, correct: true, reward_seconds: 9999}), s)
  s = answer(Game.board(s, question), false)
  assert.equal(s.hearts, 2)
  assert.equal(s.streak, 0)
  assert.match(s.message, /7 × 8 = 56/)
  s = answer(Game.board(s, question), false)
  s = answer(Game.board(s, question), false)
  assert.equal(s.phase, 'results')
  assert.equal(s.earned, 30)
  assert.equal(answer(fresh(42, 1)).phase, 'results')
})

test('stale, early, and failed requests never credit points or consume a heart', () => {
  const checking = Game.collect(atAnswer(fresh()))
  for (const error of ['too_fast', 'expired', 'no_such_question', 'unavailable', 'timeout']) {
    const s = Game.verdict(checking, {ok: false, error})
    assert.equal(s.earned, 0)
    assert.equal(s.answered, 0)
    assert.equal(s.hearts, 3)
    assert.equal(s.phase, error === 'too_fast' ? 'play' : ['expired', 'no_such_question'].includes(error) ? 'feedback' : 'error')
  }
  assert.equal(Game.tick(checking), checking)
  assert.equal(Game.move(checking, 1, 0), checking)
  for (const choices of [[], [1,1,2,3,4,5], [1,2,3,4,5,NaN], [1,2,3,4,5,145]]) {
    assert.equal(Game.board(fresh(), {...question, choices}).phase, 'error')
  }
})
