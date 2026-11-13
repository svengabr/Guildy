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
const BOOK_SKILLS = new Set([171, 164, 333, 202, 165, 197, 185, 129])
const SPEC_IDS = new Set([20219, 20222, 17039, 17040, 17041, 9787, 9788, 10656, 10658, 10660])
// The API's English names, for a client that never saved its own (Core/Specs.lua)
const EN_SPECS = { 'Gnomish Engineer': 20219, 'Goblin Engineer': 20222, Weaponsmith: 9787, Armorsmith: 9788,
  'Master Swordsmith': 17039, 'Master Hammersmith': 17040, 'Master Axesmith': 17041,
  'Dragonscale Leatherworking': 10656, 'Elemental Leatherworking': 10658, 'Tribal Leatherworking': 10660 }
const SPEC_RANK = { known: 3, api: 2, book: 1 }

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
      .filter(r => typeof r?.id === 'number' && typeof r?.name === 'string').map(r => ({ id: r.id, name: r.name }))
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

// The recipe names as spell IDs, all or nothing: a book with one unknown name would be wrong as a whole
function translate(names, bridge) {
  const count = new Map()
  for (const name of names) count.set(name, (count.get(name) ?? 0) + 1)
  const ids = []
  for (const [name, n] of count) {
    const found = bridge.spells(name)
    if (found.length !== n) return null
    ids.push(...found)
  }
  return [...new Set(ids)].sort((a, b) => a - b)
}

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
    if (entry.recipes && BOOK_SKILLS.has(skillLine) && !readLater) {
      const ids = translate(entry.recipes, bridge)
      const have = rec.get('recipes')
      if (ids && !(have instanceof LuaTable && have.arr.join(',') === ids.join(','))) {
        rec.set('recipes', toLua(ids))
        completed = true
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
// only users of this script need them
export function wantNames(db) {
  db.table('settings').set('recipeNames', true)
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
