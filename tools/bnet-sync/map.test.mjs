import { test } from 'node:test'
import assert from 'node:assert/strict'
import { LuaTable, toLua } from './lua.mjs'
import { gearValues, statValues, professions, updateStats, updateProfessions, GEAR, nameKey, slugOf, guildSlug, monthKey } from './map.mjs'

const item = (slot, level, quality, inv = slot) => ({ slot: { type: slot }, level: { value: level }, quality: { type: quality }, inventory_type: { type: inv } })

test('gearValues mirrors Stats.ReadGear', () => {
  const v = gearValues({ equipped_items: [
    item('HEAD', 30, 'RARE'), item('SHIRT', 1, 'COMMON', 'BODY'), item('CHEST', 20, 'UNCOMMON'),
    item('MAIN_HAND', 40, 'EPIC', 'TWOHWEAPON'), item('TABARD', 1, 'COMMON'),
  ] })
  assert.equal(v[GEAR.COUNT], 3) // shirt and tabard do not count
  assert.equal(v[GEAR.ILVL], 300) // (30 + 20 + 40) / 3 * 10
  assert.equal(v[GEAR.RARE], 1)
  assert.equal(v[GEAR.UNCOMMON], 1)
  assert.equal(v[GEAR.EPIC], 1)
  assert.equal(v[GEAR.EMPTY], 13) // 17 slots - 3 items - off hand taken by the two-hander
  assert.equal(v[9900100 + 17], 7)
  assert.equal(v[9900100 + 1], 4)
  assert.deepEqual(gearValues({ equipped_items: [] }), {})
})

test('gearValues counts an empty off hand next to a one-hander', () => {
  const v = gearValues({ equipped_items: [item('MAIN_HAND', 10, 'COMMON', 'WEAPON')] })
  assert.equal(v[GEAR.EMPTY], 16)
  assert.equal(v[9900100 + 17], undefined)
})

test('statValues flattens categories and drops zeros', () => {
  const v = statValues({ categories: [{ statistics: [{ id: 60, quantity: 18 }], sub_categories: [
    { statistics: [{ id: 95, quantity: 0 }, { id: 931, quantity: 16 }] }] }] })
  assert.deepEqual(v, { 60: 18, 931: 16 })
})

test('professions takes rank and max of known skill lines', () => {
  const list = professions({ primaries: [{ profession: { id: 186 }, tiers: [{ skill_points: 79, max_skill_points: 150 }] }],
    secondaries: [{ profession: { id: 185 }, tiers: [{ skill_points: 6, max_skill_points: 75 }] }, { profession: { id: 999 }, tiers: [] }] })
  assert.deepEqual(list, [{ skillLine: 186, rank: 79, max: 150 }, { skillLine: 185, rank: 6, max: 75 }])
})

const TS = Math.floor(new Date(2026, 10, 8, 12).getTime() / 1000)

test('updateStats keeps stored values the API lacks and replaces gear', () => {
  const member = toLua({ name: 'Eoy Goldcog', stats: { ts: TS - 100, src: 'self', v: { 328: 5000, 60: 10, [GEAR.ILVL]: 100, [GEAR.EPIC]: 2 }, months: {} } })
  assert.equal(updateStats(member, { 60: 18 }, { [GEAR.ILVL]: 280, [GEAR.COUNT]: 14 }, TS), true)
  const rec = member.get('stats')
  assert.equal(rec.get('ts'), TS)
  assert.equal(rec.get('src'), 'seen')
  const v = rec.get('v')
  assert.equal(v.get(328), 5000) // gold kept
  assert.equal(v.get(60), 18)
  assert.equal(v.get(GEAR.ILVL), 280)
  assert.equal(v.get(GEAR.EPIC), undefined) // old gear dropped
  assert.ok(rec.get('months').get(monthKey(TS)) instanceof LuaTable)
})

test('updateStats leaves newer stored values alone but adds a missing month snapshot', () => {
  const member = toLua({ name: 'X', stats: { ts: TS + 100, src: 'self', v: { 60: 30 }, months: { '2026-09': { ts: 1, v: {} } } } })
  updateStats(member, { 60: 18 }, {}, TS)
  const rec = member.get('stats')
  assert.equal(rec.get('ts'), TS + 100)
  assert.equal(rec.get('v').get(60), 30)
  assert.equal(rec.get('months').get(monthKey(TS)).get('v').get(60), 18)
  assert.equal(updateStats(member, { 60: 18 }, {}, TS), false)
})

test('updateStats creates a record for a member without one', () => {
  const member = toLua({ name: 'New One', profs: {} })
  updateStats(member, { 98: 5 }, {}, TS)
  assert.equal(member.get('stats').get('v').get(98), 5)
})

test('updateStats prunes to three months', () => {
  const member = toLua({ name: 'X', stats: { ts: 1, src: 'seen', v: {}, months: {
    '2026-07': { ts: 1, v: {} }, '2026-08': { ts: 1, v: {} }, '2026-09': { ts: 1, v: {} } } } })
  updateStats(member, { 60: 1 }, {}, TS)
  assert.deepEqual(member.get('stats').get('months').keys().sort(), ['2026-08', '2026-09', monthKey(TS)].sort())
})

test('updateProfessions keeps recipes, respects newer records and replaces note guesses', () => {
  const member = toLua({ name: 'X', profs: {
    186: { rank: 50, max: 75, ts: TS - 10, src: 'self', recipes: [3304] },
    164: { rank: 99, max: 150, ts: TS + 10, src: 'self' },
    185: { ts: 1, src: 'note' },
  } })
  updateProfessions(member, [{ skillLine: 186, rank: 79, max: 150 }, { skillLine: 164, rank: 54, max: 75 }, { skillLine: 185, rank: 6, max: 75 }], TS)
  const profs = member.get('profs')
  assert.equal(profs.get(186).get('rank'), 79)
  assert.equal(profs.get(186).get('src'), 'relay')
  assert.deepEqual(profs.get(186).get('recipes').arr, [3304])
  assert.equal(profs.get(164).get('rank'), 99)
  assert.equal(profs.get(185).get('rank'), 6)
  assert.equal(profs.get(185).get('ts'), TS)
})

test('names and slugs', () => {
  assert.equal(nameKey('  Eoy   Goldcog '), 'eoy goldcog')
  assert.equal(slugOf('eoy goldcog'), 'eoy-goldcog')
  assert.equal(guildSlug('Murloc Mafia@CAMWOWEU5Realm7PvE'), 'murloc-mafia')
  // file keys are UTF-8 bytes read as latin1; API names are Unicode
  const fileKey = Buffer.from('parsival prachtprügel', 'utf8').toString('latin1')
  assert.equal(nameKey('Parsival Prachtprügel'), fileKey)
  assert.equal(slugOf(fileKey), 'parsival-prachtprügel')
})
