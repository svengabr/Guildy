#!/usr/bin/env node
// Writes Core/TalentTreeNames.lua: each class's classic talent trees in tab order, their specialization IDs
// and their names in every client language Guildy supports, from the Battle.net static game data API for
// WoW Forever (/data/wow/playable-class/{classId}). The client cannot tell them (GetSpecIDs is empty there).
//
//   node --env-file=<file with BATTLENET_CLIENT_ID/SECRET> tools/bnet-sync/tree-names.mjs [--namespace <ns>] [--out <file>]
//
// The static namespace changes with the game version; pass the current one with --namespace (sync.mjs
// reads it from the profile answers' links).
import { writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { classSpecs, treeNamesLua, CLASS_FILES, TREE_LOCALES } from './map.mjs'

const args = process.argv.slice(2)
const option = name => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined }
const REGION = option('--region') ?? process.env.BATTLENET_REGION ?? 'eu'
const NAMESPACE = option('--namespace') ?? `static-1.60.1_70399-forever-${REGION}`
const OUT = option('--out') ?? join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'Core', 'TalentTreeNames.lua')

function die(msg) {
  console.error(`Fehler: ${msg}`)
  process.exit(1)
}

const { BATTLENET_CLIENT_ID: ID, BATTLENET_CLIENT_SECRET: SECRET } = process.env
if (!ID || !SECRET) die('BATTLENET_CLIENT_ID / BATTLENET_CLIENT_SECRET fehlen (--env-file=...).')

const tokenResponse = await fetch('https://oauth.battle.net/token', {
  method: 'POST',
  headers: { Authorization: 'Basic ' + Buffer.from(`${ID}:${SECRET}`).toString('base64'),
    'Content-Type': 'application/x-www-form-urlencoded' },
  body: 'grant_type=client_credentials',
})
if (!tokenResponse.ok) die(`Battle.net-Token: HTTP ${tokenResponse.status}`)
const accessToken = (await tokenResponse.json()).access_token

async function api(path, locale) {
  const r = await fetch(`https://${REGION}.api.blizzard.com${path}?namespace=${NAMESPACE}&locale=${locale}`,
    { headers: { Authorization: `Bearer ${accessToken}` } })
  if (!r.ok) die(`HTTP ${r.status} ${path} (${locale}, ${NAMESPACE})`)
  return r.json()
}

const byLocale = {}
for (const [locale, apiLocale] of Object.entries(TREE_LOCALES)) {
  byLocale[locale] = {}
  for (const [classId, file] of Object.entries(CLASS_FILES)) {
    const specs = classSpecs(await api(`/data/wow/playable-class/${classId}`, apiLocale))
    if (!specs) die(`${file} (${locale}): keine drei Spezialisierungen`)
    byLocale[locale][file] = specs
  }
}
writeFileSync(OUT, treeNamesLua(byLocale), 'utf8')
console.log(`${OUT}: ${Object.keys(CLASS_FILES).length} Klassen, ${Object.keys(TREE_LOCALES).length} Sprachen`)
