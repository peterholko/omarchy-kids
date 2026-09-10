const test = require('node:test')
const assert = require('node:assert/strict')
const Catalog = require('../../shell/plugins/pawberry/PetCatalog.js')
const Collection = require('../../shell/plugins/pawberry/PetCollection.js')
const Steps = require('../../shell/plugins/pawberry/WorkSteps.js')
const Session = require('../../shell/plugins/pawberry/WorkSession.js')
function rng(seed) { return () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed / 4294967296 } }

test('the original three pets keep their IDs and gain twenty distinct friends and accessories', () => {
  assert.deepEqual(Catalog.petIds.slice(0, 3), ['peaches', 'biscuit', 'bluebell'])
  assert.equal(Catalog.pets.length, 23)
  assert.equal(new Set(Catalog.petIds).size, 23)
  assert.equal(new Set(Catalog.pets.map(p => p.kind)).size, 23)
  assert.equal(new Set(Catalog.accessoryIds).size, 20)
  assert.deepEqual(Catalog.pets.slice(3).map(p => p.tile), Array.from({length: 20}, (_, i) => i))
  for (const pet of Catalog.pets.slice(3)) {
    const [x, y, width, height] = pet.portrait
    assert(x >= 0 && y >= 0 && width > 0 && height > 0)
    assert(x + width <= 1254 && y + height <= 1254, pet.name + ' must crop inside the bundled atlas')
    for (const anchor of [pet.head, pet.neck]) assert(anchor.every(value => value > 0 && value < 1))
  }
  for (const accessory of Catalog.accessories) {
    assert(['bow', 'hat', 'crown', 'flower', 'star', 'scarf'].includes(accessory.shape))
    assert(['head', 'neck'].includes(accessory.slot))
  }
})

test('all pets and accessories are reachable before repeats, and full collections keep working', () => {
  const random = rng(82277)
  let collection = Collection.empty(), count = 0
  for (let visit = 0; visit < 12; visit++) {
    const guests = Collection.guests(collection, Catalog.petIds, 3, random)
    assert.equal(new Set(guests).size, 3, 'no duplicate guest in a visit')
    for (const id of guests) {
      const before = JSON.stringify(collection), result = Collection.award(collection, id, Catalog.accessoryIds, random)
      assert.equal(JSON.stringify(collection), before, 'earning does not mutate earlier state')
      if (count < 23) assert(result.newPet, 'meet every pet before repeat visits')
      assert.equal(Boolean(result.accessoryId), count < 20, 'no duplicate accessories before the wardrobe is full')
      collection = result.collection; count++
      assert.equal(collection.completed, count)
      assert.equal(collection.pets.length, Math.min(count, 23))
      assert.equal(collection.accessories.length, Math.min(count, 20))
    }
  }
})

test('only owned accessories can be equipped; outfits are independent, removable and reusable', () => {
  let collection = Collection.award(Collection.empty(), 'peaches', Catalog.accessoryIds, () => 0).collection
  collection = Collection.award(collection, 'mochi', Catalog.accessoryIds, () => 0).collection
  assert.equal(Collection.equip(collection, 'bubbles', 'berry-bow'), collection)
  assert.equal(Collection.equip(collection, 'peaches', 'gold-crown'), collection)
  const before = JSON.stringify(collection)
  let dressed = Collection.equip(collection, 'peaches', 'berry-bow')
  dressed = Collection.equip(dressed, 'mochi', 'berry-bow')
  assert.equal(JSON.stringify(collection), before)
  assert.deepEqual(dressed.outfits, {peaches: 'berry-bow', mochi: 'berry-bow'})
  dressed = Collection.equip(dressed, 'peaches', 'sky-bow')
  dressed = Collection.equip(dressed, 'mochi', '')
  assert.deepEqual(dressed.outfits, {peaches: 'sky-bow'})
  assert.equal(dressed.accessories.length, 2, 'dressing never consumes a collectible')
})

test('saved collection round trips without losing rewards and rejects invalid references', () => {
  const read = raw => Collection.restore(raw, Catalog.petIds, Catalog.accessoryIds)
  let collection = Collection.award(Collection.empty(), 'peaches', Catalog.accessoryIds, () => 0).collection
  collection = Collection.equip(collection, 'peaches', 'berry-bow')
  assert.deepEqual(read(JSON.stringify(collection)), collection)
  for (const invalid of ['', '{broken', null, [], {version: 99}]) assert.deepEqual(read(invalid), Collection.empty())
  assert.deepEqual(read({version: 1, pets: ['peaches', 'peaches', 'bad', 7], accessories: ['berry-bow', 'bad', 'berry-bow'],
    outfits: {peaches: 'gold-crown', bad: 'berry-bow'}, completed: -10}),
    {version: 1, pets: ['peaches'], accessories: ['berry-bow'], outfits: {}, completed: 0})
})

test('finishing the required working is the only transition eligible for a reward', () => {
  let session = Session.create([Steps.build(300, 156, 'subtract')]), collection = Collection.empty()
  function submit(answer) {
    const next = Session.submit(session, answer)
    if (session.phase === 'work' && next.phase === 'complete') collection = Collection.award(collection, 'mochi', Catalog.accessoryIds, () => 0).collection
    session = next
  }
  submit('144'); submit(''); submit('wrong')
  assert.equal(collection.completed, 0)
  while (Session.activeStep(session).kind !== 'final') {
    submit(String(Session.activeStep(session).expected))
    assert.equal(collection.completed, 0)
  }
  session = Session.pause(session, true); submit('144')
  assert.equal(collection.completed, 0)
  session = Session.pause(session, false); submit('145')
  assert.equal(collection.completed, 0)
  submit('144'); submit('144'); submit('144')
  assert.equal(collection.completed, 1)
  assert.deepEqual(collection.pets, ['mochi'])
  assert.deepEqual(collection.accessories, ['berry-bow'])
})
