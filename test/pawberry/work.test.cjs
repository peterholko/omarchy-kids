const test = require('node:test')
const assert = require('node:assert/strict')
const Steps = require('../../shell/plugins/pawberry/WorkSteps.js')
const Session = require('../../shell/plugins/pawberry/WorkSession.js')
function value(digits) { return digits.reduce((sum, n, i) => sum + (n || 0) * 10 ** i, 0) }
function solve(problem) {
  let state = Session.create([problem])
  while (state.phase === 'work') state = Session.submit(state, String(Session.activeStep(state).expected))
  return state
}
function rng(seed) { return () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed / 4294967296 } }

test('addition requires each column and every carry before the final answer', () => {
  const p = Steps.build(99, 99, 'add')
  assert.deepEqual(p.steps.map(s => [s.kind, s.expected]), [
    ['add-column', 18], ['add-carry', 1], ['add-column', 19], ['add-carry', 1], ['final', 198]
  ])
  assert.equal(value(solve(p).board.result), 198)
  assert.equal(value(solve(Steps.build(999, 999, 'add')).board.result), 1998)
})

test('borrowing across zeros records each traded and received amount', () => {
  const p = Steps.build(300, 156, 'subtract')
  assert.deepEqual(p.steps.map(s => [s.kind, s.expected]), [
    ['borrow-give', 2], ['borrow-receive', 10], ['borrow-pass', 9], ['borrow-receive', 10],
    ['subtract-column', 4], ['subtract-column', 4], ['subtract-column', 1], ['final', 144]
  ])
  const solved = solve(p)
  assert.equal(value(solved.board.result), 144)
  assert.equal(value(solved.board.top.map((n, i) => solved.board.regroup[i] ?? n)), 300, 'regrouping conserves the minuend')
  for (const [a,b] of [[402,178], [200,199], [100,100], [30,17], [91,19], [900,101]])
    assert.equal(value(solve(Steps.build(a,b,'subtract')).board.result), a-b)
})

test('long multiplication checks carries, placeholders, full partial products and their sum', () => {
  const p = Steps.build(47, 26, 'multiply')
  assert.deepEqual(p.steps.filter(s => s.kind === 'partial-product').map(s => s.expected), [282, 940])
  assert.deepEqual(p.steps.filter(s => s.kind === 'multiply-carry').map(s => s.expected), [4,2,1])
  assert.equal(p.steps.filter(s => s.kind === 'placeholder').length, 1)
  assert.equal(value(solve(p).board.result), 1222)
  const zero = Steps.build(203, 104, 'multiply')
  assert.deepEqual(zero.steps.filter(s => s.kind === 'partial-product').map(s => s.expected), [812,0,20300])
  assert.equal(zero.steps.filter(s => s.kind === 'placeholder').length, 3)
  assert.equal(value(solve(zero).board.result), 21112)
  const largest = Steps.build(999,999,'multiply')
  assert(largest.steps.some(s => s.kind === 'add-carry' && s.expected === 2))
  assert.equal(value(solve(largest).board.result), 998001)
})

test('an early final answer or wrong intermediate cannot reveal or skip work', () => {
  const p = Steps.build(302,178,'subtract')
  const original = Session.create([p]), snapshot = JSON.stringify(original)
  let s = Session.submit(original, String(p.answer))
  assert.equal(s.stepIndex, 0); assert.equal(s.rooms, 0); assert.equal(s.ledger.length, 0)
  assert.deepEqual(s.board, original.board); assert.equal(s.mistakes, 1)
  assert.equal(JSON.stringify(original), snapshot, 'submissions do not mutate prior state')
  for (const invalid of ['', '2 4', '1.5', '-1', '1e2', '2\n4', '12345678']) {
    const rejected = Session.submit(s, invalid)
    assert.equal(rejected.stepIndex, 0); assert.deepEqual(rejected.board, s.board)
  }
  while (Session.activeStep(s).kind !== 'final') {
    const before = s.stepIndex
    s = Session.submit(s, String(Session.activeStep(s).expected))
    assert.equal(s.stepIndex, before + 1)
    assert.equal(s.phase, 'work'); assert.equal(s.rooms, 0)
  }
  s = Session.submit(s, String(p.answer + 1))
  assert.equal(s.phase, 'work'); assert.equal(s.mistakes, 2)
  s = Session.submit(s, '000124')
  assert.equal(s.phase, 'complete'); assert.equal(s.rooms, 1); assert.equal(s.mistakes, 2)
  assert.equal(s.ledger.length, p.steps.length)
  assert.equal(Session.submit(s, '124'), s, 'completion cannot be credited twice')
})

test('pause and phase gates preserve work, and all three visits must finish', () => {
  const problems = [Steps.build(12,23,'add'), Steps.build(40,18,'subtract'), Steps.build(12,30,'multiply')]
  let s = Session.create(problems)
  assert.equal(Session.advance(s), s)
  s = Session.pause(s, true)
  assert.equal(Session.submit(s,'5'), s)
  assert.equal(Session.advance(s), s)
  s = Session.pause(s,false)
  let checked = 0
  for (let i=0; i<3; i++) {
    while (s.phase === 'work') { s = Session.submit(s, String(Session.activeStep(s).expected)); checked++ }
    assert.equal(s.rooms, i+1); assert.equal(s.checked, checked)
    s = Session.advance(s)
    if (i<2) { assert.equal(s.stepIndex,0); assert.equal(s.ledger.length,0); assert(s.board.result.every(n => n === null)) }
  }
  assert.equal(s.phase,'results'); assert.equal(s.rooms,3); assert.equal(s.mistakes,0)
  assert.equal(Session.advance(s),s)
})

test('generated two- and three-digit work agrees with independent arithmetic', () => {
  const random = rng(63738)
  const kinds = new Set()
  for (const size of [2,3]) for (const op of ['add','subtract','multiply']) for (let i=0; i<160; i++) {
    const p = Steps.generate(op,size,random)
    assert.equal(String(p.a).length,size); assert.equal(String(p.b).length,size)
    const expected = op === 'add' ? p.a+p.b : op === 'subtract' ? p.a-p.b : p.a*p.b
    const s = solve(p)
    assert.equal(p.answer,expected); assert.equal(value(s.board.result),expected)
    assert.equal(p.steps.at(-1).kind,'final'); assert(p.steps.length>1)
    p.steps.forEach(step => { kinds.add(step.kind); assert(Number.isInteger(step.expected) && step.expected >= 0) })
    if (op === 'multiply') for (let j=0; j<size; j++) assert.equal(value(s.board['partial'+j]),p.a*(Math.floor(p.b/10**j)%10)*10**j)
    if (op === 'subtract') assert.equal(value(s.board.top.map((n,j) => s.board.regroup[j] ?? n)),p.a)
  }
  for (const kind of ['borrow-give','borrow-receive','borrow-pass','placeholder','multiply-carry','partial-product','add-carry']) assert(kinds.has(kind),kind)
})

test('problem construction rejects unsupported or invalid arithmetic', () => {
  for (const args of [[9,10,'add'],[10,1000,'add'],[42.5,10,'add'],[20,30,'subtract'],[40,20,'divide']]) assert.throws(() => Steps.build(...args))
  assert.throws(() => Steps.generate('add',4)); assert.throws(() => Session.create([]))
})

test('single-digit multiplication includes all 1–9 facts and checks the working', () => {
  for (let a = 1; a <= 9; a++) for (let b = 1; b <= 9; b++) {
    const p = Steps.build(a,b,'multiply'), solved = solve(p)
    assert.equal(value(solved.board.result), a*b)
    assert(p.steps.some(s => s.kind === 'multiply-column'))
    assert(p.steps.length > 1)
  }
  for (let i=0;i<200;i++) {
    const p = Steps.generate('multiply',1)
    assert(p.a >= 1 && p.a <= 9 && p.b >= 1 && p.b <= 9)
  }
  assert.throws(() => Steps.generate('add',1))
})

test('easy division uses exact two-digit table facts and verifies multiplication and subtraction', () => {
  for (let b=2;b<=9;b++) for (let q=2;q<=9;q++) if (b*q>=10) {
    const p = Steps.build(b*q,b,'divide'), solved = solve(p)
    assert.deepEqual(p.steps.map(s => s.expected), [q,b*q,0,q])
    assert.deepEqual(p.steps.map(s => s.kind), ['divide-groups','divide-product','divide-remainder','final'])
    assert.equal(value(solved.board.result), q)
    assert.equal(solved.board.remainder[0],0)
    let state = Session.create([p]); state = Session.submit(state,String(q))
    state = Session.submit(state,String(q))
    assert.equal(state.stepIndex,1,'the final answer cannot skip the multiplication check')
  }
  for (let i=0;i<200;i++) {
    const p = Steps.generate('divide',2)
    assert(p.a>=10 && p.a<=81 && p.b>=2 && p.b<=9 && p.answer<=9)
    assert.equal(p.a % p.b,0)
  }
  for (const [a,b] of [[7,2],[43,6],[99,3],[56,0]]) assert.throws(() => Steps.build(a,b,'divide'))
  assert.throws(() => Steps.generate('divide',3))
})

test('a spent operation is excluded from mixed play and the next guest', () => {
  const Practice = require('../../shell/plugins/pawberry/PracticePolicy.js')
  const status = {remaining:{add:0,subtract:0,multiply:null,divide:null}}
  assert.deepEqual(Practice.choices(status), ['multiply','divide'])
  for (let i=0;i<20;i++) assert(['multiply','divide'].includes(Practice.nextKind('add',status)))
  assert.equal(Practice.nextKind('subtract',{remaining:{subtract:1}}), 'subtract')
  assert.equal(Practice.sizeFor('add',1),2)
  assert.equal(Practice.sizeFor('multiply',1),1)
  assert.equal(Practice.sizeFor('divide',3),2)
  status.remaining.multiply = 0
  assert.deepEqual(Practice.choices(status), ['divide'])
  for (const operation of ['add','subtract','multiply','mixed']) {
    for (const random of [0,0.25,0.75,0.999]) assert.equal(Practice.nextKind(operation,status,() => random), 'divide')
  }
})
