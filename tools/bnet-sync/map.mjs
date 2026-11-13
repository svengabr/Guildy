// Battle.net profile API responses (WoW Forever, profile-forever-*) to Guildy's GuildyDB records.
// Mirrors Core/Stats.lua (StatRec, gear IDs, Stats.Update) and Core/Professions.lua (ProfRec, Merge)
// so the written records look exactly like ones read in the game ("seen" stats, "relay" professions).
import { LuaTable, toLua } from './lua.mjs'

export const GEAR = { ILVL: 9900001, EPIC: 9900002, RARE: 9900003, UNCOMMON: 9900004, COUNT: 9900005,
  COMMON: 9900006, POOR: 9900007, EMPTY: 9900008, LEGENDARY: 9900009 }
export const GEAR_BASE = 9900000
const GEAR_SLOT_BASE = 9900100
const SLOT_TWO_HANDED = 7
const GEAR_SLOTS = [1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]
const SLOT_IDS = { HEAD: 1, NECK: 2, SHOULDER: 3, SHIRT: 4, CHEST: 5, WAIST: 6, LEGS: 7, FEET: 8, WRIST: 9,
  HANDS: 10, FINGER_1: 11, FINGER_2: 12, TRINKET_1: 13, TRINKET_2: 14, BACK: 15, MAIN_HAND: 16, OFF_HAND: 17,
  RANGED: 18, TABARD: 19 }
const QUALITY = { POOR: 0, COMMON: 1, UNCOMMON: 2, RARE: 3, EPIC: 4, LEGENDARY: 5, ARTIFACT: 5, HEIRLOOM: 5 }
const QUALITY_IDS = { 0: 'POOR', 1: 'COMMON', 2: 'UNCOMMON', 3: 'RARE', 4: 'EPIC', 5: 'LEGENDARY' }
const MONTHS_KEPT = 3
const MAX_VALUES = 500
export const SKILL_LINES = new Set([171, 164, 333, 202, 182, 165, 186, 393, 197, 185, 129, 356])
const MAX_SKILL = 450
// Professions with specializations on Forever (Core/Specs.lua) and those whose books Guildy shows
const SPEC_SKILLS = new Set([202, 164, 165])
export const BOOK_SKILLS = new Set([171, 164, 333, 202, 165, 186, 197, 185, 129])
// The professions' English names: the API lists the profession's own spell among its recipes (Mining's
// ranks among the smelting), which no book in the game contains
const EN_PROFESSIONS = { 171: 'Alchemy', 164: 'Blacksmithing', 333: 'Enchanting', 202: 'Engineering', 182: 'Herbalism',
  165: 'Leatherworking', 186: 'Mining', 393: 'Skinning', 197: 'Tailoring', 185: 'Cooking', 129: 'First Aid', 356: 'Fishing' }
const SPEC_IDS = new Set([20219, 20222, 17039, 17040, 17041, 9787, 9788, 10656, 10658, 10660])
// The API's English names, for a client that never saved its own (Core/Specs.lua)
const EN_SPECS = { 'Gnomish Engineer': 20219, 'Goblin Engineer': 20222, Weaponsmith: 9787, Armorsmith: 9788,
  'Master Swordsmith': 17039, 'Master Hammersmith': 17040, 'Master Axesmith': 17041,
  'Dragonscale Leatherworking': 10656, 'Elemental Leatherworking': 10658, 'Tribal Leatherworking': 10660 }
const SPEC_RANK = { known: 3, api: 2, book: 1 }

// The API's stat types as the client's GetItemStats keys. Others (resistances above all) are left out:
// Guildy's upgrades count every ITEM_MOD_* key, so a guessed key would count where the client's does not.
export const STAT_KEYS = { STRENGTH: 'ITEM_MOD_STRENGTH_SHORT', AGILITY: 'ITEM_MOD_AGILITY_SHORT',
  STAMINA: 'ITEM_MOD_STAMINA_SHORT', INTELLECT: 'ITEM_MOD_INTELLECT_SHORT', SPIRIT: 'ITEM_MOD_SPIRIT_SHORT',
  ATTACK_POWER: 'ITEM_MOD_ATTACK_POWER_SHORT', RANGED_ATTACK_POWER: 'ITEM_MOD_RANGED_ATTACK_POWER_SHORT',
  SPELL_POWER: 'ITEM_MOD_SPELL_POWER_SHORT', MANA_REGENERATION: 'ITEM_MOD_MANA_REGENERATION_SHORT',
  CRIT_RATING: 'ITEM_MOD_CRIT_RATING_SHORT', HIT_RATING: 'ITEM_MOD_HIT_RATING_SHORT',
  DEFENSE_SKILL_RATING: 'ITEM_MOD_DEFENSE_SKILL_RATING_SHORT', DODGE_RATING: 'ITEM_MOD_DODGE_RATING_SHORT',
  PARRY_RATING: 'ITEM_MOD_PARRY_RATING_SHORT', BLOCK_RATING: 'ITEM_MOD_BLOCK_RATING_SHORT' }

// { [ITEM_MOD_*_SHORT]: value } of a worn item's stats list (random suffix included: the API lists the
// item's stats as worn), negated ones left out; undefined without a list
function storedStats(list) {
  if (!Array.isArray(list)) return undefined
  const st = {}
  for (const s of list) {
    const key = STAT_KEYS[s?.type?.type]
    if (key && !s.is_negated && Number.isInteger(s.value)) st[key] = (st[key] ?? 0) + s.value
  }
  return st
}

const MAX_BONUS = 16 // Core/Gear.lua's Gear.MAX_BONUS

// Core/Gear.lua's record from the /equipment response and the profile: { ts, src: 'api', race, sex,
// items: { [slot]: { id, e, s, l, q, st, b } } }, null without a list of equipped items. The suffix ID is not
// in the response as far as known (2026-11-13), so it is 0; st holds the stats the response lists for the
// item (its random suffix included), which Guildy takes for the worn item instead of the game's; b the
// item's bonus_list.
export function gearRecord(equipment, profile, ts) {
  if (!Array.isArray(equipment?.equipped_items)) return null
  const items = {}
  for (const item of equipment.equipped_items) {
    const slot = SLOT_IDS[item?.slot?.type]
    const id = item?.item?.id
    if (!slot || !Number.isInteger(id) || id <= 0) continue
    const enchant = (item.enchantments ?? []).map(e => e?.enchantment_id).find(e => Number.isInteger(e) && e > 0) ?? 0
    const level = item.level?.value ?? item.item_level ?? 0
    items[slot] = { id, e: enchant, s: 0, l: Number.isInteger(level) && level > 0 ? level : 0,
      q: Math.max(0, Math.min(QUALITY[item.quality?.type] ?? 1, 5)) }
    const st = storedStats(item.stats)
    if (st) items[slot].st = st
    // the bonus IDs: WoW Forever's modern engine carries a random suffix there; Guildy rebuilds the item
    // string with them (Core/Gear.lua, b), else the game gives the base item
    const b = Array.isArray(item.bonus_list) ? item.bonus_list.filter(x => Number.isInteger(x) && x > 0).slice(0, MAX_BONUS) : []
    if (b.length > 0) items[slot].b = b
  }
  const race = profile?.race?.id
  const sex = { MALE: 2, FEMALE: 3 }[profile?.gender?.type]
  const rec = { ts, src: 'api', items }
  if (Number.isInteger(race) && race > 0) rec.race = race
  if (sex) rec.sex = sex
  return rec
}

// Writes record into guild.gear[key] when it is newer than what is there; true when written. A record
// without items (an empty equipped_items) is never written: it would wipe good gear.
export function updateGear(guild, key, record) {
  if (!record || Object.keys(record.items ?? {}).length === 0) return false
  const book = guild.table('gear')
  const have = book.get(key)
  const stored = have instanceof LuaTable ? have.get('ts') : undefined
  if (typeof stored === 'number' && stored >= record.ts) return false
  book.set(key, toLua(record))
  return true
}

// Enchant texts of the response into GuildyDB.enchantText, the text after the first ": " of display_string
// ("Verzaubert: Bergbau +2" -> "Bergbau +2"); only when locale (the language the response was asked in)
// is the client's. A table of another language is replaced.
export function enchantTexts(db, equipment, locale) {
  if (typeof locale !== 'string' || db.get('clientLocale') !== locale) return
  let cache = db.get('enchantText')
  if (!(cache instanceof LuaTable) || cache.get('locale') !== locale || !(cache.get('names') instanceof LuaTable)) {
    cache = toLua({ locale, names: {} })
    db.set('enchantText', cache)
  }
  const names = cache.get('names')
  for (const item of equipment?.equipped_items ?? []) {
    for (const e of item?.enchantments ?? []) {
      const id = e?.enchantment_id
      if (!Number.isInteger(id) || id <= 0 || typeof e.display_string !== 'string') continue
      const at = e.display_string.indexOf(': ')
      const text = (at >= 0 ? e.display_string.slice(at + 2) : e.display_string).trim()
      if (text) names.set(id, toBytes(text))
    }
  }
}

// What recipes make into GuildyDB.craftItems: pairs [[spellID, itemID]], positive integers only, at most
// MAX_CRAFTS entries (Core/Upgrades.lua); Guildy drops what cannot be worn when it loads
export const MAX_CRAFTS = 3000
export function craftItems(db, pairs) {
  const map = db.table('craftItems')
  let count = map.keys().length
  for (const [spell, item] of pairs) {
    if (!Number.isInteger(spell) || spell <= 0 || !Number.isInteger(item) || item <= 0) continue
    if (!map.has(spell)) {
      if (count >= MAX_CRAFTS) continue
      count++
    }
    map.set(spell, item)
  }
}

// Stats.ReadGear on the /equipment response: { [gearID]: value }, {} with nothing equipped
export function gearValues(equipment) {
  const bySlot = new Map()
  for (const item of equipment?.equipped_items ?? []) {
    const slot = SLOT_IDS[item?.slot?.type]
    if (slot) bySlot.set(slot, item)
  }
  let levels = 0, count = 0, empty = 0, twoHanded = false, emptyOffHand = false
  const qualities = [0, 0, 0, 0, 0, 0]
  const slots = {}
  for (const slot of GEAR_SLOTS) {
    const item = bySlot.get(slot)
    if (item) {
      const level = item.level?.value ?? item.item_level ?? 0
      const q = Math.max(0, Math.min(QUALITY[item.quality?.type] ?? 1, 5))
      levels += level
      count++
      qualities[q]++
      slots[slot] = q + 1
      if (slot === 16 && /^TWOHWEAPON$|^2HWEAPON$/.test(item.inventory_type?.type ?? '')) twoHanded = true
    } else if (slot === 17) emptyOffHand = true
    else empty++
  }
  if (emptyOffHand) {
    if (twoHanded) slots[17] = SLOT_TWO_HANDED
    else empty++
  }
  const values = {}
  if (count > 0) {
    values[GEAR.ILVL] = Math.floor(levels / count * 10 + 0.5)
    values[GEAR.COUNT] = count
    if (empty > 0) values[GEAR.EMPTY] = empty
    for (const [slot, v] of Object.entries(slots)) values[GEAR_SLOT_BASE + Number(slot)] = v
  }
  qualities.forEach((n, q) => { if (n > 0) values[GEAR[QUALITY_IDS[q]]] = n })
  return values
}

// /achievements/statistics response to { [statID]: quantity }, zeros left out (like the game reading)
export function statValues(response) {
  const values = {}
  const walk = category => {
    for (const s of category?.statistics ?? []) {
      const q = Math.floor(Number(s.quantity))
      if (Number.isInteger(s.id) && s.id > 0 && s.id < 1e7 && q > 0 && q < 1e12) values[s.id] = q
    }
    for (const sub of category?.sub_categories ?? []) walk(sub)
  }
  for (const category of response?.categories ?? []) walk(category)
  return values
}

// /professions response to [{ skillLine, rank, max, spec?, recipes? }]: spec is the specialization's name
// (null for a profession that has them when none is taken), recipes the known recipes as { id, name }.
// The API names recipes in English whatever locale is asked (checked 2026-11-13); localize() gives
// them the client's names
export function professions(response) {
  const list = []
  for (const p of [...(response?.primaries ?? []), ...(response?.secondaries ?? [])]) {
    const skillLine = p?.profession?.id
    if (!SKILL_LINES.has(skillLine)) continue
    const tier = (p.tiers ?? []).reduce((best, t) => (!best || (t.max_skill_points ?? 0) > (best.max_skill_points ?? 0) ? t : best), null)
    if (!tier) continue
    const clamp = x => Math.max(0, Math.min(MAX_SKILL, Math.floor(Number(x) || 0)))
    const entry = { skillLine, rank: clamp(tier.skill_points), max: clamp(tier.max_skill_points) }
    if (typeof p.specialization?.name === 'string') entry.spec = p.specialization.name
    else if (SPEC_SKILLS.has(skillLine)) entry.spec = null
    const recipes = (p.tiers ?? []).flatMap(t => t.known_recipes ?? [])
      .filter(r => typeof r?.id === 'number' && typeof r?.name === 'string')
      .filter(r => r.name !== EN_PROFESSIONS[skillLine] && r.name !== p.profession?.name)
      .map(r => ({ id: r.id, name: r.name }))
    if (recipes.length) entry.recipes = recipes
    list.push(entry)
  }
  return list
}

// Stats.MonthKey: "2026-11" in local time
export function monthKey(ts) {
  const d = new Date(ts * 1000)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
}

function valuesTable(values) {
  const t = new LuaTable()
  for (const [id, v] of Object.entries(values)) t.set(Number(id), v)
  return t
}

function plain(t) {
  const out = {}
  if (t instanceof LuaTable) for (const [k, v] of t.hash) if (typeof k === 'number' && typeof v === 'number') out[k] = v
  return out
}

const isGear = id => Number(id) > GEAR_BASE

// Stores API values in member.stats like Stats.Update with src "seen": only when newer than what is
// stored. The API leaves out statistics (all gold ones, for example): stored values it lacks are kept,
// and equipment is replaced only when the API returned some. Returns true when anything changed.
export function updateStats(member, apiStats, gear, ts) {
  let rec = member.get('stats')
  if (!(rec instanceof LuaTable)) {
    rec = new LuaTable()
    member.set('stats', rec)
  }
  const months = rec.table('months')
  const hasGear = Object.keys(gear).length > 0
  let changed = false
  let current = null
  const stored = rec.get('ts')
  if (typeof stored !== 'number' || ts > stored) {
    const values = plain(rec.get('v'))
    for (const id of Object.keys(values)) if (hasGear && isGear(id)) delete values[id]
    Object.assign(values, apiStats, gear)
    current = cap(values)
    rec.set('ts', ts)
    rec.set('src', 'seen')
    rec.set('v', valuesTable(current))
    changed = true
  }
  const month = monthKey(ts)
  const snap = months.get(month)
  if (!(snap instanceof LuaTable)) {
    const snapValues = current ?? cap({ ...plain(rec.get('v')), ...apiStats, ...gear })
    const s = new LuaTable()
    s.set('ts', ts)
    s.set('v', valuesTable(snapValues))
    months.set(month, s)
    changed = true
  } else if (hasGear && !Object.keys(plain(snap.get('v'))).some(isGear)) {
    const v = snap.table('v')
    for (const [id, value] of Object.entries(gear)) v.set(Number(id), value)
    changed = true
  }
  const keys = months.keys().filter(k => typeof k === 'string').sort()
  for (const k of keys.slice(0, Math.max(0, keys.length - MONTHS_KEPT))) months.set(k, null)
  return changed
}

// Receivers drop records with more than 500 values: keep the gear and the catalog-relevant low IDs
function cap(values) {
  const ids = Object.keys(values)
  if (ids.length <= MAX_VALUES) return values
  const keep = ids.sort((a, b) => (isGear(b) - isGear(a)) || (Number(a) - Number(b))).slice(0, MAX_VALUES)
  return Object.fromEntries(keep.map(id => [id, values[id]]))
}

// The recipe names Guildy saved in the client's language (GuildyDB.recipeNames, Game/TradeSkill.lua):
// the API numbers recipes differently from the game, the name is the bridge. null when none are saved.
export function nameBridge(db) {
  const saved = db?.get?.('recipeNames')
  const names = saved instanceof LuaTable ? saved.get('names') : null
  if (!(names instanceof LuaTable)) return null
  const byName = new Map()
  const add = (id, name) => {
    if (typeof id !== 'number' || typeof name !== 'string') return
    const text = fromBytes(name)
    if (!byName.has(text)) byName.set(text, [])
    byName.get(text).push(id)
  }
  for (const id of names.keys()) add(id, names.get(id))
  names.arr.forEach((name, i) => add(i + 1, name))
  const spells = name => byName.get(name) ?? []
  return {
    locale: typeof saved.get('locale') === 'string' ? saved.get('locale') : undefined,
    spells,
    // the spell ID of a specialization's name, null when the name is none
    specId(name) {
      const ids = spells(name).filter(id => SPEC_IDS.has(id))
      if (ids.length === 1) return ids[0]
      return EN_SPECS[name] ?? null
    },
  }
}

// The recipes ({ id, name }) with the names of the client's language from names (recipe ID -> name,
// /data/wow/recipe in that locale); null when one has none yet
export function localize(recipes, names) {
  if (!Array.isArray(recipes)) return null
  const out = []
  for (const r of recipes) {
    const name = names.get(r.id)
    if (typeof name !== 'string') return null
    out.push(name)
  }
  return out
}

// The API's locale for a client locale ("deDE" -> "de_DE")
export function apiLocale(locale) {
  return typeof locale === 'string' && /^[a-z]{2}[A-Z]{2}$/.test(locale) ? `${locale.slice(0, 2)}_${locale.slice(2)}` : 'en_US'
}

// The recipe names as spell IDs, and how many could not be translated (a name Guildy never saw, or one
// that stands for more spells than the book has of it)
function translate(names, bridge) {
  const count = new Map()
  for (const name of names) count.set(name, (count.get(name) ?? 0) + 1)
  const ids = []
  let missing = 0
  for (const [name, n] of count) {
    const found = bridge.spells(name)
    if (found.length === n) ids.push(...found)
    else missing += n
  }
  return { ids: [...new Set(ids)].sort((a, b) => a - b), missing }
}

// A book that lacks at most this many recipes is still written for a member without one ("partial")
export const MAX_MISSING = 3

// Specialization like Specs.Merge with src "api": over a book whatever its age, over the game's own
// word only when newer. Returns true when it changed.
function writeSpec(rec, skillLine, name, bridge, ts) {
  if (!SPEC_SKILLS.has(skillLine) || name === undefined) return false
  const id = name === null ? 0 : bridge.specId(name)
  if (id === null) return false
  const have = rec.get('spec')
  if (have instanceof LuaTable) {
    const src = have.get('src'), at = have.get('ts')
    if (have.get('id') === id && src === 'api' && at === ts) return false
    if ((src === 'known' || src === 'api') && !(ts > at || (ts === at && SPEC_RANK.api > SPEC_RANK[src]))) return false
  }
  rec.set('spec', toLua({ id, src: 'api', ts }))
  return true
}

// Stores profession ranks like Professions.Merge with src "relay": a stored record that is newer or as
// new wins, the stored recipes and specialization are kept. With a name bridge it also writes the book
// (complete or not at all, never over one read in the game after the login) and the specialization.
// Returns true when anything changed.
export function updateProfessions(member, list, ts, bridge = null) {
  const profs = member.table('profs')
  let changed = false
  for (const entry of list) {
    const { skillLine, rank, max } = entry
    let rec = profs.get(skillLine)
    let madeNew = false
    const renewed = !(rec instanceof LuaTable && typeof rec.get('ts') === 'number' && rec.get('ts') >= ts)
    if (renewed && !(rec instanceof LuaTable && rec.get('rank') === rank && rec.get('max') === max && rec.get('src') !== 'note')) {
      madeNew = true
      const fresh = new LuaTable()
      fresh.set('rank', rank)
      fresh.set('max', max)
      fresh.set('ts', ts)
      fresh.set('src', 'relay')
      if (rec instanceof LuaTable && rec.get('recipes') instanceof LuaTable) fresh.set('recipes', rec.get('recipes'))
      if (rec instanceof LuaTable && rec.get('spec') instanceof LuaTable) fresh.set('spec', rec.get('spec'))
      profs.set(skillLine, fresh)
      rec = fresh
      changed = true
    }
    if (!bridge || !(rec instanceof LuaTable)) continue
    // a book read in the game after the login is newer than anything the API knows
    const readLater = rec.get('ts') > ts && rec.get('recipes') instanceof LuaTable
    let completed = false
    if (entry.recipes && BOOK_SKILLS.has(skillLine)) {
      const { ids, missing } = translate(entry.recipes, bridge)
      const have = rec.get('recipes')
      const hadList = have instanceof LuaTable
      // partial = recipes a book written by this script lacks; Guildy drops the mark when it takes a
      // reading of its own into the record, so a marked list is still the script's
      const lacked = rec.get('partial')
      const wasPartial = typeof lacked === 'number'
      const same = hadList && have.arr.join(',') === ids.join(',')
      if (missing === 0) {
        // complete: over anything but a book read in the game after the login, over a partial one always
        if ((!readLater || wasPartial) && (!same || wasPartial)) {
          rec.set('recipes', toLua(ids))
          rec.set('partial', null)
          completed = true
        }
      } else if (missing <= MAX_MISSING && ids.length > 0) {
        // partial: only where there is no book yet, or a partial one that lacks more
        if (!hadList || (wasPartial && missing < lacked)) {
          rec.set('recipes', toLua(ids))
          rec.set('partial', missing)
          completed = true
        }
      }
    }
    if (writeSpec(rec, skillLine, entry.spec, bridge, ts)) completed = true
    // the guild only takes a record newer than its own (Professions.Digest): one completed here, at
    // the time every other client already holds, would never leave this one
    if (completed && !madeNew) rec.set('ts', rec.get('ts') + 1)
    if (completed) changed = true
  }
  return changed
}

// Asks Guildy to save recipe names from the next login on (settings.recipeNames, Game/TradeSkill.lua):
// only users of this script need them. unknown = names of the client's language no saved name matched:
// Guildy looks for them among the game's spells at the next login (GuildyDB.wantedNames). items = name ->
// the item the recipe makes: its use effect often bears the same name, and Guildy leaves that spell out.
const MAX_WANTED = 3000
export function wantNames(db, unknown = [], locale = undefined, items = new Map()) {
  db.table('settings').set('recipeNames', true)
  if (!unknown.length || !locale) {
    db.set('wantedNames', null)
    return
  }
  const names = unknown.slice(0, MAX_WANTED)
  const wanted = toLua({ locale, names: names.map(toBytes) })
  const made = new LuaTable()
  for (const name of names) {
    const item = items.get(name)
    if (Number.isInteger(item) && item > 0) made.set(toBytes(name), item)
  }
  if (made.hash.size) wanted.set('items', made)
  db.set('wantedNames', wanted)
}

// The SavedVariables file is handled as bytes (latin1 strings); API text is real Unicode.
export const toBytes = s => Buffer.from(String(s), 'utf8').toString('latin1')
export const fromBytes = s => Buffer.from(String(s), 'latin1').toString('utf8')

// Guildy's member key for an API name "First Last" (Names.Key: trimmed, single spaces, lower case),
// as bytes like the keys in the file
export function nameKey(name) {
  return toBytes(String(name).trim().replace(/\s+/g, ' ').toLowerCase())
}

// API character slug for a Guildy member key from the file ("eoy goldcog" -> "eoy-goldcog")
export function slugOf(key) {
  return fromBytes(key).trim().replace(/\s+/g, '-').toLowerCase()
}

// Guild slug for a Guildy guild key ("Murloc Mafia@Realm" -> "murloc-mafia")
export function guildSlug(guildKey) {
  return fromBytes(guildKey).split('@')[0].trim().replace(/\s+/g, '-').toLowerCase()
}

// --- talent specs (Core/Talents.lua; not the profession specializations above) ----------------------
// The API's class IDs as the client's class files
export const CLASS_FILES = { 1: 'WARRIOR', 2: 'PALADIN', 3: 'HUNTER', 4: 'ROGUE', 5: 'PRIEST', 7: 'SHAMAN', 8: 'MAGE',
  9: 'WARLOCK', 11: 'DRUID' }
const MAX_TREE_POINTS = 100

// The client locales Core/TalentTreeNames.lua holds and the API locale each is asked in
export const TREE_LOCALES = { deDE: 'de_DE', enUS: 'en_US', frFR: 'fr_FR', esES: 'es_ES', ruRU: 'ru_RU', ptBR: 'pt_BR' }

const luaString = s => '"' + String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n') + '"'

// The source of Core/TalentTreeNames.lua from byLocale = { [locale]: { [classFile]: classSpecs } }:
// ns.TalentTreeNames = { ids = { [classFile] = { id1, id2, id3 } }, names = { [locale] = { [classFile] =
// { name1, name2, name3 } } } }, classes by class ID, locales in TREE_LOCALES order. Throws when a class's
// spec IDs differ between locales.
export function treeNamesLua(byLocale) {
  const classes = Object.entries(CLASS_FILES).sort((a, b) => a[0] - b[0]).map(([, file]) => file)
  const locales = [...Object.keys(TREE_LOCALES), ...Object.keys(byLocale).filter(l => !(l in TREE_LOCALES))]
    .filter(l => byLocale[l])
  const ids = {}
  for (const locale of locales) {
    for (const [file, specs] of Object.entries(byLocale[locale])) {
      const these = specs.map(([id]) => id).join(', ')
      if (ids[file] && ids[file] !== these) throw new Error(`${file}: spec IDs ${these} (${locale}) differ from ${ids[file]}`)
      ids[file] = these
    }
  }
  const out = [
    '-- The classic talent trees per class in tab order: their specialization IDs and their names in each client',
    '-- language, from the Battle.net static game data API for WoW Forever (/data/wow/playable-class/{classId}).',
    '-- Generated by tools/bnet-sync/tree-names.mjs; do not edit by hand, run the script again.',
    'local _, ns = ...',
    '',
    'ns.TalentTreeNames = {',
    '  ids = {',
    ...classes.filter(f => ids[f]).map(f => `    ${f} = { ${ids[f]} },`),
    '  },',
    '  names = {',
  ]
  for (const locale of locales) {
    out.push(`    ${locale} = {`)
    for (const file of classes) {
      const specs = byLocale[locale][file]
      if (specs) out.push(`      ${file} = { ${specs.map(([, name]) => luaString(name)).join(', ')} },`)
    }
    out.push('    },')
  }
  out.push('  },', '}', '')
  return out.join('\n')
}

// The static namespace of this game version from the links in a profile answer, null without one
export function staticNamespaceOf(body) {
  return JSON.stringify(body ?? null).match(/[?&]namespace=(static-[\w.-]+)/)?.[1] ?? null
}

// The class's talent trees in tab order from /data/wow/playable-class/{id} (static namespace):
// [[specializationID, name], ...], null without three valid entries
export function classSpecs(body) {
  const list = Array.isArray(body?.specializations) ? body.specializations : null
  if (!list || list.length !== 3) return null
  const specs = list.map(s => [s?.id, s?.name])
  return specs.every(([id, name]) => Number.isInteger(id) && typeof name === 'string') ? specs : null
}

// The points per talent tree of the /specializations response: { trees: [p1, p2, p3], names }, null when
// it has none. Shape (live, profile-forever-eu): specialization_groups[] with is_active, each with
// specializations[] of { specialization { id, name }, specialization_name, spent_points, talents[] { talent_rank } },
// listing only the trees with points. Each is placed by its specialization ID in the class's tab order
// (specs: classSpecs of the class), a missing tree counts 0. Without specs the trees are placed by the names
// Guildy knows for the class (known: three names in the response's language), else nothing is taken.
export function talentTrees(response, known = null, specs = null) {
  const groups = Array.isArray(response?.specialization_groups) ? response.specialization_groups : []
  const group = groups.find(g => g?.is_active) ?? groups[0]
  const list = Array.isArray(group?.specializations) ? group.specializations : null
  if (!list || list.length > 3) return null
  const points = s => Number.isInteger(s?.spent_points) ? s.spent_points
    : (s?.talents ?? []).reduce((sum, t) => sum + (Number.isInteger(t?.talent_rank) ? t.talent_rank : 0), 0)
  const trees = [0, 0, 0]
  if (Array.isArray(specs) && specs.length === 3) {
    const ids = specs.map(([id]) => id)
    for (const s of list) {
      const at = ids.indexOf(s?.specialization?.id)
      if (at < 0) return null
      trees[at] = points(s)
    }
    return { trees, names: specs.map(([, name]) => name), ids }
  }
  if (list.length === 0 || !Array.isArray(known) || known.length !== 3) return null
  const ids = [null, null, null]
  for (const s of list) {
    const at = known.indexOf(typeof s?.specialization_name === 'string' ? s.specialization_name : '')
    if (at < 0) return null
    trees[at] = points(s)
    if (Number.isInteger(s?.specialization?.id)) ids[at] = s.specialization.id
  }
  return { trees, names: known, ids }
}

// Core/Talents.lua's record: { ts, src: 'api', trees, spec? }, null without three valid trees; spec is the
// specialization ID of the tree with the most points (the first of a tie), left out without points
export function talentRecord(response, ts, known = null, specs = null) {
  const found = talentTrees(response, known, specs)
  if (!found || !found.trees.every(p => Number.isInteger(p) && p >= 0 && p <= MAX_TREE_POINTS)) return null
  const rec = { ts, src: 'api', trees: found.trees }
  const top = Math.max(...found.trees)
  const spec = top > 0 ? found.ids?.[found.trees.indexOf(top)] : null
  if (Number.isInteger(spec) && spec > 0) rec.spec = spec
  return rec
}

// Writes record into guild.talents[key] when it is newer than what is there; true when written
export function updateTalents(guild, key, record) {
  if (!record) return false
  const book = guild.table('talents')
  const have = book.get(key)
  const stored = have instanceof LuaTable ? have.get('ts') : undefined
  if (typeof stored === 'number' && stored >= record.ts) return false
  book.set(key, toLua(record))
  return true
}

// The trees' names of classFile into GuildyDB.talentNames ({ locale, classes = { [classFile] = names } },
// Game/Talents.lua), only when locale (the language the response was asked in) is the client's
export function talentNames(db, classFile, names, locale) {
  if (typeof locale !== 'string' || db.get('clientLocale') !== locale || !classFile) return
  if (!Array.isArray(names) || names.length !== 3 || names.some(n => typeof n !== 'string' || n === '')) return
  let cache = db.get('talentNames')
  if (!(cache instanceof LuaTable) || cache.get('locale') !== locale || !(cache.get('classes') instanceof LuaTable)) {
    cache = toLua({ locale, classes: {} })
    db.set('talentNames', cache)
  }
  cache.get('classes').set(classFile, toLua(names.map(toBytes)))
}

// The trees' names Guildy keeps for classFile in locale, null when none
export function knownTreeNames(db, classFile, locale) {
  const cache = db?.get?.('talentNames')
  if (!(cache instanceof LuaTable) || cache.get('locale') !== locale) return null
  const names = cache.get('classes')?.get?.(classFile)
  return names instanceof LuaTable && names.arr.length === 3 ? names.arr.map(fromBytes) : null
}
