const test = require('node:test')
const assert = require('node:assert/strict')
const Game = require('../../shell/plugins/paw-post/TypingEngine.js')
const Lessons = require('../../shell/plugins/paw-post/Lessons.js')
function fresh(mode = 'cozy', words = ['cat']) { return Game.create('words', mode, words, 25) }
function deliver(s, start = 1000) {
  for (const [i, char] of Array.from(s.target).entries()) s = Game.type(s, char, start + i * 100)
  return s
}

test('all lessons use distinct printable prompts, with bounded home-row practice', () => {
  assert.equal(Lessons.get('unknown').id, 'words')
  for (const lesson of Lessons.LESSONS) {
    assert(lesson.prompts.length >= 20)
    assert.equal(new Set(lesson.prompts).size, lesson.prompts.length)
    assert(lesson.prompts.every(p => p.length <= 64 && /^[\x20-\x7e]+$/.test(p)))
  }
  assert(Lessons.get('home').prompts.every(p => /^[asdfjkl; ]+$/.test(p)))
  assert(Lessons.get('stories').prompts.every(p => /^[A-Z].*[.!?]$/.test(p)))
  assert.equal(Lessons.keyHint(' '), 'Space')
  assert.equal(Lessons.keyHint('A'), 'Shift + A')
})

test('a shuffled route covers its whole lesson before repeating, without boundary repeats', () => {
  const words = Lessons.get('words').prompts
  let s = fresh('cozy', words), seen = new Set([s.target])
  assert.deepEqual(s, fresh('cozy', words))
  for (let i = 1; i < words.length; i++) { s = Game.next(s); seen.add(s.target) }
  assert.equal(seen.size, words.length)
  const last = s.target
  s = Game.next(s)
  assert.notEqual(s.target, last)
  assert.equal(Game.create('words', 'cozy', [], 1).phase, 'results')
})

test('wrong letters remain visible and correction does not erase accuracy history', () => {
  let s = Game.type(fresh(), 'x', 1000)
  assert.equal(s.typed, 'x'); assert(s.error); assert.equal(s.delivered, 0)
  s = Game.backspace(s, 1200)
  assert.equal(s.typed, ''); assert(!s.error)
  s = deliver(s, 1500)
  assert.equal(s.delivered, 1); assert.equal(s.phase, 'delivery')
  assert.equal(Game.accuracy(s), 75)
  assert.equal(s.mistakes, 1)
  assert.equal(s.bestStreak, 0)
  assert.equal(Game.type(s, 'a', 2000), s)
})

test('mistakes in the middle need repair and cannot finish by filling the length', () => {
  let s = fresh()
  for (const [i, c] of ['c', 'x', 't'].entries()) s = Game.type(s, c, 1000 + i * 100)
  assert.equal(s.phase, 'play'); assert.equal(Game.progress(s), 1)
  s = Game.type(s, 'a', 1400)
  assert.equal(s.typed, 'cxt'); assert.equal(s.delivered, 0)
  s = Game.backspace(Game.backspace(s, 1500), 1600)
  s = Game.type(Game.type(s, 'a', 1700), 't', 1800)
  assert.equal(s.delivered, 1)
  assert.equal(s.mistakes, 2)
})

test('spaces, case and punctuation are real keystrokes; paste cannot complete a delivery', () => {
  let s = fresh('cozy', ['Hi, cat!'])
  const paste = Game.type(s, 'Hi, cat!', 1000)
  assert.equal(paste.typed, ''); assert.equal(paste.attempts, 0); assert(!paste.started)
  s = Game.type(s, 'h', 1000)
  assert(s.error)
  s = Game.backspace(s, 1100)
  s = deliver(s, 1200)
  assert.equal(s.delivered, 1)
  assert.equal(s.completedChars, 8)
})

test('cozy rounds finish after ten deliveries and keep their streak and stats', () => {
  let s = fresh(), time = 1000
  for (let i = 0; i < 10; i++) {
    s = deliver(s, time); time += 1500
    if (i < 9) s = Game.next(s)
  }
  assert.equal(s.phase, 'results'); assert.equal(s.delivered, 10)
  assert.equal(s.completedChars, 30); assert.equal(s.bestStreak, 10)
  assert.equal(Game.accuracy(s), 100)
  assert.equal(Game.badge(s).title, 'Careful courier')
  assert.equal(Game.next(s), s)
  assert.equal(Game.backspace(s, time), s)
})

test('the dash clock starts on the first keystroke, freezes on pause and ends at its deadline', () => {
  let s = Game.advance(fresh('dash'), 8000)
  assert.equal(s.elapsed, 0)
  s = Game.type(s, 'c', 10000)
  s = Game.advance(s, 12000)
  assert.equal(s.elapsed, 2000)
  s = Game.pause(s, 13000)
  assert.equal(s.elapsed, 3000); assert(s.paused)
  assert.equal(Game.advance(s, 99000), s)
  assert.equal(Game.type(s, 'a', 99000), s)
  s = Game.pause(s, 100000)
  s = Game.advance(s, 102000)
  assert.equal(s.elapsed, 5000)
  s = Game.type(s, 'a', 187000)
  assert.equal(s.phase, 'results'); assert.equal(s.elapsed, 90000)
  assert.equal(s.typed, 'c'); assert.equal(s.delivered, 0)
})

test('automatic delivery animation is excluded from active typing time', () => {
  let s = deliver(fresh(), 1000)
  assert.equal(s.elapsed, 200)
  assert.equal(Game.advance(s, 9000), s)
  s = Game.next(s)
  s = Game.type(s, 'c', 10000)
  assert.equal(s.elapsed, 200)
  s = Game.type(s, 'a', 11000)
  assert.equal(s.elapsed, 1200)
})

test('WPM counts completed text and the current correct prefix, never retyped characters', () => {
  let s = fresh('dash', ['hello'])
  s = Game.type(s, 'h', 1000)
  s = Game.type(s, 'e', 2000)
  s = Game.backspace(s, 3000)
  s = Game.type(s, 'e', 4000)
  s = Game.advance(s, 7000)
  assert.equal(Game.wpm(s), 4) // 2 characters / 5 / 0.1 minute
  s = Game.type(s, 'x', 7000)
  assert.equal(Game.wpm(s), 4)
  s = Game.advance(s, 91000)
  assert.equal(Game.wpm(s), 0) // rounded down over the completed 90-second dash
})
