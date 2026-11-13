import { test } from 'node:test'
import assert from 'node:assert/strict'
import { LuaTable, toLua } from './lua.mjs'
import { gearValues, statValues, professions, updateStats, updateProfessions, nameBridge, apiLocale, wantNames, localize, BOOK_SKILLS, GEAR, nameKey, slugOf, guildSlug, monthKey, gearRecord, updateGear, enchantTexts, craftItems } from './map.mjs'

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

test("professions leaves out the profession's own spell, which the API lists among the recipes", () => {
  const list = professions({ primaries: [{ profession: { id: 186, name: 'Bergbau' }, tiers: [{ skill_points: 300, max_skill_points: 300,
    known_recipes: [{ id: 3324, name: 'Smelt Copper' }, { id: 1570, name: 'Mining' }, { id: 5487, name: 'Mining' }] }] }] })
  assert.deepEqual(list[0].recipes, [{ id: 3324, name: 'Smelt Copper' }])
  assert.ok(BOOK_SKILLS.has(186)) // smelting is a book Guildy shows
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
  db.get('recipeNames').get('names').set(2366, 'Kräuterkunde')
  const member = toLua({ name: 'X', profs: {} })
  updateProfessions(member, [{ skillLine: 182, rank: 300, max: 300, recipes: ['Kräuterkunde'] }], TS, nameBridge(db))
  assert.equal(member.get('profs').get(182).get('recipes'), undefined)
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

test('wantNames hands Guildy the names it could not translate, to look for in the game', () => {
  const db = toLua({ settings: {} })
  wantNames(db, ['Gürtel der Wacht', 'Grüner Eisenhelm'], 'deDE')
  const wanted = db.get('wantedNames')
  assert.equal(wanted.get('locale'), 'deDE')
  assert.deepEqual(wanted.get('names').arr.map(n => Buffer.from(n, 'latin1').toString('utf8')), ['Gürtel der Wacht', 'Grüner Eisenhelm'])
  wantNames(db, ['Große Kupferbombe', 'Gürtel der Wacht'], 'deDE', new Map([['Große Kupferbombe', 4370]]))
  const items = db.get('wantedNames').get('items') // the made item, whose use effect bears the same name
  assert.equal(items.get(Buffer.from('Große Kupferbombe', 'utf8').toString('latin1')), 4370)
  assert.equal(items.hash.size, 1)
  wantNames(db, [], 'deDE')
  assert.equal(db.get('wantedNames'), undefined) // nothing left to look for
})

const worn = (slot, id, level, quality, enchant) => ({ slot: { type: slot }, item: { id }, level: { value: level }, quality: { type: quality },
  enchantments: enchant ? [{ enchantment_id: enchant[0], display_string: enchant[1] }] : undefined })

test('gearRecord mirrors Core/Gear.lua', () => {
  const rec = gearRecord({ equipped_items: [worn('HEAD', 101, 50, 'RARE'), worn('SHIRT', 38, 1, 'COMMON'),
    worn('CHEST', 105, 48, 'UNCOMMON', [1887, 'Verzaubert: +4 Werte']), worn('MAIN_HAND', 116, 60, 'EPIC'), worn('TABARD', 119, 1, 'COMMON'),
    worn('AMMO', 5, 1, 'COMMON')] },
  { race: { id: 4 }, gender: { type: 'FEMALE' } }, 1800000000)
  assert.deepEqual(rec, { ts: 1800000000, src: 'api', race: 4, sex: 3, items: {
    1: { id: 101, e: 0, s: 0, l: 50, q: 3 }, 4: { id: 38, e: 0, s: 0, l: 1, q: 1 }, 5: { id: 105, e: 1887, s: 0, l: 48, q: 2 },
    16: { id: 116, e: 0, s: 0, l: 60, q: 4 }, 19: { id: 119, e: 0, s: 0, l: 1, q: 1 } } })
  assert.equal(gearRecord({ equipped_items: [] }, { gender: { type: 'MALE' } }, 1).sex, 2)
  assert.equal(gearRecord({}, {}, 1), null)
  assert.equal(gearRecord(null, {}, 1), null)
})

test('gearRecord stores the stats the response lists per worn item, in the client keys', () => {
  const stat = (type, value, extra = {}) => ({ type: { type, name: type }, value, display: { display_string: `+${value} ${type}` }, ...extra })
  const tunic = { ...worn('CHEST', 7484, 39, 'UNCOMMON'), name: 'Waldläufertunika des Tigers',
    stats: [stat('STRENGTH', 13), stat('AGILITY', 13), stat('FIRE_RESISTANCE', 5), stat('STAMINA', 4, { is_negated: true })] }
  const ring = { ...worn('FINGER_1', 900, 40, 'RARE'), stats: [stat('INTELLECT', 3), stat('SPIRIT', 2), stat('ATTACK_POWER', 20), stat('STAMINA', 6)] }
  const plain = { ...worn('SHIRT', 38, 1, 'COMMON'), stats: [] }
  const rec = gearRecord({ equipped_items: [tunic, ring, plain, worn('HEAD', 101, 50, 'RARE')] }, {}, 1)
  assert.deepEqual(rec.items[5].st, { ITEM_MOD_STRENGTH_SHORT: 13, ITEM_MOD_AGILITY_SHORT: 13 })
  assert.deepEqual(rec.items[11].st, { ITEM_MOD_INTELLECT_SHORT: 3, ITEM_MOD_SPIRIT_SHORT: 2, ITEM_MOD_ATTACK_POWER_SHORT: 20,
    ITEM_MOD_STAMINA_SHORT: 6 })
  assert.deepEqual(rec.items[4].st, {}) // listed, none: known to have no stats
  assert.equal('st' in rec.items[1], false) // no list in the response: nothing known
})

test('updateGear writes only a newer record', () => {
  const guild = new LuaTable()
  const rec = gearRecord({ equipped_items: [worn('HEAD', 101, 50, 'RARE')] }, { race: { id: 4 } }, 100)
  assert.equal(updateGear(guild, 'au tsch', rec), true)
  const stored = guild.get('gear').get('au tsch')
  assert.equal(stored.get('src'), 'api')
  assert.equal(stored.get('items').get(1).get('id'), 101)
  assert.equal(updateGear(guild, 'au tsch', { ...rec, ts: 99 }), false)
  assert.equal(updateGear(guild, 'au tsch', { ...rec, ts: 100 }), false)
  assert.equal(updateGear(guild, 'au tsch', { ...rec, ts: 101 }), true)
})

test('updateGear never writes a record without items over good gear', () => {
  const guild = new LuaTable()
  updateGear(guild, 'au tsch', gearRecord({ equipped_items: [worn('HEAD', 101, 50, 'RARE')] }, {}, 100))
  assert.equal(updateGear(guild, 'au tsch', gearRecord({ equipped_items: [] }, {}, 200)), false)
  assert.equal(guild.get('gear').get('au tsch').get('items').get(1).get('id'), 101)
  assert.equal(updateGear(guild, 'makira farron', gearRecord({ equipped_items: [] }, {}, 200)), false)
  assert.equal(guild.get('gear').get('makira farron'), undefined)
})

test('enchantTexts keeps the text after the prefix, in the client language only', () => {
  const equipment = { equipped_items: [worn('HANDS', 1, 40, 'RARE', [844, 'Verzaubert: Bergbau +2'])] }
  const db = toLua({ clientLocale: 'deDE' })
  enchantTexts(db, equipment, 'deDE')
  assert.equal(db.get('enchantText').get('locale'), 'deDE')
  assert.equal(db.get('enchantText').get('names').get(844), 'Bergbau +2')
  const other = toLua({ clientLocale: 'frFR', enchantText: { locale: 'frFR', names: { 1: 'x' } } })
  enchantTexts(other, equipment, 'deDE')
  assert.equal(other.get('enchantText').get('names').get(844), undefined)
  const stale = toLua({ clientLocale: 'deDE', enchantText: { locale: 'enUS', names: { 1: 'x' } } })
  enchantTexts(stale, equipment, 'deDE')
  assert.equal(stale.get('enchantText').get('names').get(1), undefined)
  assert.equal(stale.get('enchantText').get('names').get(844), 'Bergbau +2')
})

test('craftItems writes integer pairs up to the cap', () => {
  const db = new LuaTable()
  craftItems(db, [[1, 10], [2, 0], [3, 1.5], [0, 5], [4, 40]])
  const map = db.get('craftItems')
  assert.equal(map.get(1), 10)
  assert.equal(map.get(4), 40)
  assert.equal(map.has(2), false)
  assert.equal(map.has(3), false)
  const many = Array.from({ length: 3100 }, (_, i) => [100 + i, 7])
  craftItems(db, many)
  assert.equal(db.get('craftItems').keys().length, 3000)
})
