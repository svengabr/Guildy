import { test } from 'node:test'
import assert from 'node:assert/strict'
import { LuaTable, toLua } from './lua.mjs'
import { gearValues, statValues, professions, updateStats, updateProfessions, nameBridge, apiLocale, wantNames, localize, GEAR, nameKey, slugOf, guildSlug, monthKey } from './map.mjs'

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

test('professions also gives the specialization and the recipe names', () => {
  const list = professions({ primaries: [
    { profession: { id: 202 }, specialization: { name: 'Goblin-Ingenieur' },
      tiers: [{ skill_points: 264, max_skill_points: 300, known_recipes: [{ id: 1, name: 'Sappeurladung' }, { id: 2, name: 'Goblin-Mörser' }] }] },
    { profession: { id: 164 }, tiers: [{ skill_points: 54, max_skill_points: 75 }] },
  ] })
  assert.deepEqual(list, [
    { skillLine: 202, rank: 264, max: 300, spec: 'Goblin-Ingenieur', recipes: [{ id: 1, name: 'Sappeurladung' }, { id: 2, name: 'Goblin-Mörser' }] },
    { skillLine: 164, rank: 54, max: 75, spec: null }, // a profession with specializations, none taken
  ])
})

// GuildyDB with the names Guildy saved in the client's language (bytes, like the file)
const bridgeDb = () => toLua({ recipeNames: { locale: 'deDE', names: {
  12760: Buffer.from('Sappeurladung', 'utf8').toString('latin1'),
  12716: Buffer.from('Goblin-Mörser', 'utf8').toString('latin1'),
  20222: Buffer.from('Goblin-Ingenieur', 'utf8').toString('latin1'),
  20219: Buffer.from('Gnomen-Ingenieur', 'utf8').toString('latin1'),
} } })

test('nameBridge translates names Guildy saved into spell IDs', () => {
  const bridge = nameBridge(bridgeDb())
  assert.equal(bridge.locale, 'deDE')
  assert.equal(apiLocale(bridge.locale), 'de_DE')
  assert.equal(apiLocale(undefined), 'en_US')
  assert.deepEqual(bridge.spells('Goblin-Mörser'), [12716])
  assert.equal(bridge.specId('Goblin-Ingenieur'), 20222)
  assert.equal(bridge.specId('Sappeurladung'), null) // a recipe is no specialization
  assert.equal(bridge.specId('Goblin Engineer'), 20222) // the English name works without a saved one
  assert.equal(nameBridge(toLua({})), null)
})

test('updateProfessions writes a complete book and the specialization', () => {
  const member = toLua({ name: 'Au Tsch', profs: {} })
  updateProfessions(member, [{ skillLine: 202, rank: 264, max: 300, spec: 'Goblin-Ingenieur',
    recipes: ['Sappeurladung', 'Goblin-Mörser'] }], TS, nameBridge(bridgeDb()))
  const rec = member.get('profs').get(202)
  assert.deepEqual(rec.get('recipes').arr, [12716, 12760])
  assert.equal(rec.get('spec').get('id'), 20222)
  assert.equal(rec.get('spec').get('src'), 'api')
  assert.equal(rec.get('spec').get('ts'), TS)
})

test('updateProfessions writes no book of which more than three recipes have no known name', () => {
  const member = toLua({ name: 'Au Tsch', profs: {} })
  updateProfessions(member, [{ skillLine: 202, rank: 264, max: 300,
    recipes: ['Sappeurladung', 'Unbekannt 1', 'Unbekannt 2', 'Unbekannt 3', 'Unbekannt 4'] }], TS, nameBridge(bridgeDb()))
  assert.equal(member.get('profs').get(202).get('recipes'), undefined)
})

test('updateProfessions writes a partial book for a member without one, marked with what it lacks', () => {
  const member = toLua({ name: 'Zera Tops', profs: {} })
  updateProfessions(member, [{ skillLine: 202, rank: 165, max: 225, recipes: ['Sappeurladung', 'Unbekannt'] }], TS, nameBridge(bridgeDb()))
  const rec = member.get('profs').get(202)
  assert.deepEqual(rec.get('recipes').arr, [12760])
  assert.equal(rec.get('partial'), 1)
})

test('updateProfessions never puts a partial book over an existing one', () => {
  const member = toLua({ name: 'X', profs: { 202: { rank: 264, max: 300, ts: TS, src: 'relay', recipes: [12716] } } })
  updateProfessions(member, [{ skillLine: 202, rank: 264, max: 300, recipes: ['Sappeurladung', 'Unbekannt'] }], TS, nameBridge(bridgeDb()))
  assert.deepEqual(member.get('profs').get(202).get('recipes').arr, [12716])
  assert.equal(member.get('profs').get(202).get('partial'), undefined)
})

test('updateProfessions completes a partial book once every name is known', () => {
  const member = toLua({ name: 'Zera Tops', profs: {} })
  const book = [{ skillLine: 202, rank: 165, max: 225, recipes: ['Sappeurladung', 'Goblin-Mörser'] }]
  const db = bridgeDb()
  db.get('recipeNames').get('names').set(12716, null) // Goblin-Mörser not seen yet
  updateProfessions(member, book, TS, nameBridge(db))
  assert.equal(member.get('profs').get(202).get('partial'), 1)
  assert.equal(member.get('profs').get(202).get('ts'), TS) // a new record: newer than anything the guild holds
  updateProfessions(member, book, TS, nameBridge(bridgeDb())) // the next run knows it
  const rec = member.get('profs').get(202)
  assert.deepEqual(rec.get('recipes').arr, [12716, 12760])
  assert.equal(rec.get('partial'), undefined)
  assert.equal(rec.get('ts'), TS + 1) // news again for the guild
})

test('updateProfessions leaves a book read in the game after the login alone', () => {
  const member = toLua({ name: 'Au Tsch', profs: { 202: { rank: 265, max: 300, ts: TS + 50, src: 'link', recipes: [12760] } } })
  updateProfessions(member, [{ skillLine: 202, rank: 264, max: 300, recipes: ['Sappeurladung', 'Goblin-Mörser'] }], TS, nameBridge(bridgeDb()))
  assert.deepEqual(member.get('profs').get(202).get('recipes').arr, [12760])
})

test('updateProfessions fills a missing book of a record as new as the API', () => {
  const member = toLua({ name: 'Au Tsch', profs: { 202: { rank: 264, max: 300, ts: TS, src: 'relay' } } })
  updateProfessions(member, [{ skillLine: 202, rank: 264, max: 300, recipes: ['Sappeurladung'] }], TS, nameBridge(bridgeDb()))
  assert.deepEqual(member.get('profs').get(202).get('recipes').arr, [12760])
})

test('updateProfessions writes no recipe list for a gathering profession', () => {
  const db = bridgeDb()
  db.get('recipeNames').get('names').set(2575, 'Bergbau')
  const member = toLua({ name: 'X', profs: {} })
  updateProfessions(member, [{ skillLine: 186, rank: 300, max: 300, recipes: ['Bergbau'] }], TS, nameBridge(db))
  assert.equal(member.get('profs').get(186).get('recipes'), undefined)
})

test('updateProfessions follows the specialization rules of the game', () => {
  const bridge = nameBridge(bridgeDb())
  const member = toLua({ name: 'X', profs: { 202: { rank: 264, max: 300, ts: TS, src: 'relay', spec: { id: 20219, src: 'book', ts: TS + 99 } } } })
  updateProfessions(member, [{ skillLine: 202, rank: 264, max: 300, spec: 'Goblin-Ingenieur' }], TS, bridge)
  assert.equal(member.get('profs').get(202).get('spec').get('id'), 20222) // over a book, whatever its age
  member.get('profs').get(202).set('spec', toLua({ id: 20219, src: 'known', ts: TS + 1 }))
  updateProfessions(member, [{ skillLine: 202, rank: 264, max: 300, spec: 'Goblin-Ingenieur' }], TS, bridge)
  assert.equal(member.get('profs').get(202).get('spec').get('id'), 20219) // not over the game's newer word
  updateProfessions(member, [{ skillLine: 202, rank: 264, max: 300, spec: null }], TS + 2, bridge)
  assert.equal(member.get('profs').get(202).get('spec').get('id'), 0) // unlearned
  updateProfessions(member, [{ skillLine: 202, rank: 264, max: 300, spec: 'Etwas Fremdes' }], TS + 3, bridge)
  assert.equal(member.get('profs').get(202).get('spec').get('id'), 0) // an unknown name changes nothing
})

test('updateProfessions makes a record it completes news for the guild', () => {
  const member = toLua({ name: 'Au Tsch', profs: { 202: { rank: 264, max: 300, ts: TS, src: 'relay' } } })
  updateProfessions(member, [{ skillLine: 202, rank: 264, max: 300, spec: 'Goblin-Ingenieur', recipes: ['Sappeurladung'] }], TS, nameBridge(bridgeDb()))
  assert.equal(member.get('profs').get(202).get('ts'), TS + 1) // newer than what every other client holds
  updateProfessions(member, [{ skillLine: 202, rank: 264, max: 300, spec: 'Goblin-Ingenieur', recipes: ['Sappeurladung'] }], TS, nameBridge(bridgeDb()))
  assert.equal(member.get('profs').get(202).get('ts'), TS + 1) // a second run adds nothing
})

test('wantNames asks Guildy to save recipe names from the next login on', () => {
  const db = toLua({ settings: {} })
  wantNames(db)
  assert.equal(db.get('settings').get('recipeNames'), true)
})

test('localize gives the recipes the names of the client language, or nothing when one is missing', () => {
  const names = new Map([[1, 'Kräutergebackenes Ei'], [2, 'Magentafarbener Farbstoff']])
  assert.deepEqual(localize([{ id: 1, name: 'Herb Baked Egg' }, { id: 2, name: 'Magenta Dye' }], names),
    ['Kräutergebackenes Ei', 'Magentafarbener Farbstoff'])
  assert.equal(localize([{ id: 1, name: 'Herb Baked Egg' }, { id: 3, name: 'Basic Campfire' }], names), null)
  assert.equal(localize(undefined, names), null)
})
