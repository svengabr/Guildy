#!/usr/bin/env node
// Fills Guildy's SavedVariables with the guild members' data from the Battle.net profile API
// (WoW Forever): statistics, equipment, reputation counts, dungeon kills and profession ranks.
// Run it with the game closed; the game reads the file at its next start.
//
//   node --env-file=<file with BATTLENET_CLIENT_ID/SECRET> sync.mjs --sv <path to Guildy.lua> [--dry-run]
//
// Records are written the way Guildy writes data it read in the game (src "seen" / "relay"), with
// the character's last login as timestamp: newer data read in the game keeps winning, and Guildy
// shares the rest with the guild as usual.
import { readFileSync, writeFileSync, copyFileSync, readdirSync, unlinkSync, existsSync, mkdirSync } from 'node:fs'
import { basename, dirname, join } from 'node:path'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { parse, serialize, LuaTable } from './lua.mjs'
import { gearValues, statValues, professions, updateStats, updateProfessions, nameBridge, apiLocale, wantNames, localize, nameKey, slugOf, guildSlug, toBytes, fromBytes } from './map.mjs'

const args = process.argv.slice(2)
const flag = name => args.includes(name)
const option = name => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined }

const SV = option('--sv') ?? process.env.GUILDY_SV
const OUT = option('--out') // write the result there instead of the game file (works while WoW runs)
const DRY = flag('--dry-run') || !!OUT
const REGION = option('--region') ?? process.env.BATTLENET_REGION ?? 'eu'
const NAMESPACE = `profile-${process.env.BATTLENET_NAMESPACE_FAMILY ?? 'forever'}-${REGION}`
const CONCURRENCY = 6
const BACKUPS_KEPT = 7
const MIN_LEVEL = 10 // the API has no profile below level 10

function die(msg) {
  console.error(`Fehler: ${msg}`)
  process.exit(1)
}

if (!SV) die('Pfad zu Guildy.lua fehlt (--sv oder GUILDY_SV).')
const { BATTLENET_CLIENT_ID: ID, BATTLENET_CLIENT_SECRET: SECRET } = process.env
if (!ID || !SECRET) die('BATTLENET_CLIENT_ID / BATTLENET_CLIENT_SECRET fehlen (--env-file=...).')

function gameRunning() {
  if (process.platform !== 'win32') return false
  try {
    const list = execFileSync('tasklist', ['/FO', 'CSV', '/NH'], { encoding: 'utf8' })
    // Wow.exe, WowClassic.exe, Wow-64.exe ... but not helpers like WowVoiceProxy.exe
    return /^"wow(?!voice)[^"]*\.exe"/im.test(list)
  } catch { return false }
}
if (!DRY && gameRunning()) die('WoW läuft noch. Das Spiel überschreibt die Datei beim Beenden – erst schließen.')

// --- API ---------------------------------------------------------------------------------------
async function token() {
  const r = await fetch(`https://oauth.battle.net/token`, {
    method: 'POST',
    headers: { Authorization: 'Basic ' + Buffer.from(`${ID}:${SECRET}`).toString('base64'),
      'Content-Type': 'application/x-www-form-urlencoded' },
    body: 'grant_type=client_credentials',
  })
  if (!r.ok) die(`Battle.net-Token: HTTP ${r.status}`)
  return (await r.json()).access_token
}

let accessToken
let requests = 0
async function api(path, locale = 'en_US', namespace = NAMESPACE) {
  for (let attempt = 0; ; attempt++) {
    requests++
    const r = await fetch(`https://${REGION}.api.blizzard.com${path}?namespace=${namespace}&locale=${locale}`,
      { headers: { Authorization: `Bearer ${accessToken}` } })
    if (r.ok) return r.json()
    if (r.status === 404 || r.status === 403) return null
    if ((r.status === 429 || r.status >= 500) && attempt < 3) {
      const wait = Number(r.headers.get('retry-after')) * 1000 || 1000 * 2 ** attempt
      await new Promise(res => setTimeout(res, wait))
      continue
    }
    throw new Error(`HTTP ${r.status} ${path}`)
  }
}

async function pool(items, worker) {
  let next = 0
  await Promise.all(Array.from({ length: Math.min(CONCURRENCY, items.length) }, async () => {
    while (next < items.length) {
      const item = items[next++]
      await worker(item)
    }
  }))
}

// --- run -------------------------------------------------------------------------------------
const text = readFileSync(SV, 'latin1')
const globals = parse(text)
const db = globals.get('GuildyDB')
if (!(db instanceof LuaTable) || !(db.get('guilds') instanceof LuaTable)) die('GuildyDB ohne Gilden – einmal mit Guildy einloggen.')
const own = new Set((db.get('ownChars') instanceof LuaTable ? db.get('ownChars').keys() : []).map(String))

// recipe books and specializations need the names Guildy saved in the client's language
const bridge = nameBridge(db)
const PROF_LOCALE = apiLocale(bridge?.locale)
console.log(bridge
  ? `Rezeptnamen von Guildy (${bridge.locale}): Bücher und Spezialisierungen werden mitgeschrieben.`
  : 'Keine Rezeptnamen gespeichert – einmal mit diesem Guildy einloggen, dann schreibt das Skript auch Bücher.')

// The profile API names recipes in English whatever locale is asked; its static recipe entries
// (/data/wow/recipe) honor the locale. Each recipe's name in the client's language is looked up once and
// kept in out/, since it never changes.
const NAMES_FILE = join(dirname(fileURLToPath(import.meta.url)), 'out', `recipe-names-${bridge?.locale ?? 'enUS'}.json`)
const recipeNames = new Map(existsSync(NAMES_FILE)
  ? Object.entries(JSON.parse(readFileSync(NAMES_FILE, 'utf8'))).map(([id, name]) => [Number(id), name]) : [])
const lookups = new Map()
let staticNamespace = null
let namesLooked = 0
function recipeName(id) {
  if (recipeNames.has(id)) return null
  if (!lookups.has(id)) {
    lookups.set(id, api(`/data/wow/recipe/${id}`, PROF_LOCALE, staticNamespace).then(body => {
      if (typeof body?.name === 'string') {
        recipeNames.set(id, body.name)
        namesLooked++
      }
    }))
  }
  return lookups.get(id)
}

accessToken = await token()
const now = Math.floor(Date.now() / 1000)
const totals = { members: 0, added: 0, stats: 0, profs: 0, books: 0, bookCandidates: 0, missing: [], failed: [] }

for (const guildKey of db.get('guilds').keys()) {
  const guild = db.get('guilds').get(guildKey)
  if (typeof guildKey !== 'string' || !(guild instanceof LuaTable)) continue
  const members = guild.table('members')
  const slugs = new Map()

  const roster = await api(`/data/wow/guild/${encodeURIComponent(guildSlug(guildKey))}/roster`)
  if (roster) {
    for (const { character: c } of roster.members ?? []) {
      if (!c?.name || (c.level ?? 0) < MIN_LEVEL) continue
      const name = [c.name, c.surname].filter(Boolean).join(' ')
      const key = nameKey(name)
      slugs.set(key, c.slug)
      if (!members.has(key) && !own.has(key)) {
        const m = new LuaTable()
        m.set('name', toBytes(name))
        m.set('profs', new LuaTable())
        members.set(key, m)
        totals.added++
      }
    }
  } else {
    console.warn(`  ${guildKey}: kein Roster von der API, nur bekannte Mitglieder.`)
  }

  const keys = members.keys().filter(k => typeof k === 'string' && !own.has(k))
  console.log(`${fromBytes(guildKey)}: ${keys.length} Mitglieder`)
  await pool(keys, async key => {
    const member = members.get(key)
    if (!(member instanceof LuaTable)) return
    const base = `/profile/wow/character/${encodeURIComponent(slugs.get(key) ?? slugOf(key))}`
    try {
      const profile = await api(base)
      if (!profile?.last_login_timestamp) { totals.missing.push(key); return }
      const ts = Math.min(now, Math.floor(profile.last_login_timestamp / 1000))
      const [stats, equipment, profs] = await Promise.all([
        api(`${base}/achievements/statistics`), api(`${base}/equipment`), api(`${base}/professions`, PROF_LOCALE)])
      totals.members++
      if (stats && updateStats(member, statValues(stats), equipment ? gearValues(equipment) : {}, ts)) totals.stats++
      if (profs) {
        const list = professions(profs)
        // the static namespace of this game version, from the profile's own links
        staticNamespace ??= JSON.stringify(profs).match(/data\/wow\/recipe\/\d+\?namespace=([\w.-]+)/)?.[1] ?? null
        for (const entry of list) {
          if (!entry.recipes) continue
          if (!bridge || !staticNamespace) {
            delete entry.recipes
            continue
          }
          await Promise.all(entry.recipes.map(r => recipeName(r.id)))
          totals.bookCandidates++
          entry.recipes = localize(entry.recipes, recipeNames) ?? undefined
          if (entry.recipes && entry.recipes.every(name => bridge.spells(name).length > 0)) totals.books++
        }
        if (updateProfessions(member, list, ts, bridge)) totals.profs++
      }
    } catch (e) {
      totals.failed.push(`${key} (${e.message})`)
    }
  })
}

console.log(`\n${totals.members} Charaktere gelesen (${requests} Anfragen), ${totals.added} neu aus dem Roster.`)
console.log(`Statistiken/Ausrüstung aktualisiert: ${totals.stats}, Berufe aktualisiert: ${totals.profs}`)
if (totals.missing.length) console.log(`Kein API-Profil (umbenannt, gelöscht oder privat): ${totals.missing.map(fromBytes).join(', ')}`)
if (totals.failed.length) console.log(`Fehlgeschlagen: ${totals.failed.join('; ')}`)
if (bridge) {
  console.log(`Rezeptbücher übersetzbar: ${totals.books} von ${totals.bookCandidates} (${namesLooked} Rezeptnamen neu nachgeschlagen).`)
  console.log('Ein Buch, von dem Guildy ein Rezept noch nie gesehen hat, wartet, bis es dieses Rezept einmal in einem Buch liest.')
  mkdirSync(dirname(NAMES_FILE), { recursive: true })
  writeFileSync(NAMES_FILE, JSON.stringify(Object.fromEntries(recipeNames)))
}

wantNames(db) // from the next login on Guildy saves the names this needs
const out = serialize(globals)
if (DRY) {
  const target = OUT ?? join(process.env.TEMP ?? dirname(SV), 'Guildy.bnet-dry-run.lua')
  writeFileSync(target, out, 'latin1')
  console.log(`\nSpieldatei nicht geändert. Ergebnis: ${target}`)
} else {
  if (gameRunning()) die('WoW wurde während des Laufs gestartet – nichts geschrieben.')
  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace('T', '-').slice(0, 15)
  const backup = `${SV}.bnet-${stamp}.bak`
  copyFileSync(SV, backup)
  const prefix = `${basename(SV)}.bnet-`
  const old = readdirSync(dirname(SV)).filter(f => f.startsWith(prefix) && f.endsWith('.bak')).sort()
  for (const f of old.slice(0, Math.max(0, old.length - BACKUPS_KEPT))) unlinkSync(join(dirname(SV), f))
  writeFileSync(SV, out, 'latin1')
  console.log(`\nGeschrieben. Sicherung: ${backup}`)
}
