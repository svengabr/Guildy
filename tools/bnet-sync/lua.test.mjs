import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync, existsSync } from 'node:fs'
import { parse, serialize, LuaTable } from './lua.mjs'

test('parses WoW SavedVariables syntax', () => {
  const g = parse(`DB = {
["name"] = "Eoy \\"G\\" \\\\ x\\n",
["n"] = -12.5,
[42] = true,
plain = false,
"pos1", -- [1]
2, -- [2]
--[[ block ]] ["t"] = { ["a"] = { }, },
}
Other = nil
`)
  const db = g.get('DB')
  assert.equal(db.get('name'), 'Eoy "G" \\ x\n')
  assert.equal(db.get('n'), -12.5)
  assert.equal(db.get(42), true)
  assert.equal(db.get('plain'), false)
  assert.deepEqual(db.arr, ['pos1', 2])
  assert.ok(db.get('t').get('a') instanceof LuaTable)
  assert.equal(g.get('Other'), null)
})

test('keeps UTF-8 bytes when read and written as latin1', () => {
  const bytes = Buffer.from('X = {\n["n"] = "Jürgen Möller",\n}\n', 'utf8')
  const back = Buffer.from(serialize(parse(bytes.toString('latin1'))), 'latin1')
  assert.equal(back.toString('utf8'), 'X = {\n["n"] = "Jürgen Möller",\n}\n')
})

test('round-trips: parse(serialize(x)) serializes identically', () => {
  const text = 'A = {\n1,\n"two",\n["k"] = {\n[5] = 0.25,\n},\n[1794099408] = "\\001",\n}\n'
  const once = serialize(parse(text))
  assert.equal(serialize(parse(once)), once)
  assert.equal(once, text)
})

const REAL = process.env.GUILDY_SV
test('round-trips the real Guildy.lua', { skip: !REAL || !existsSync(REAL) }, () => {
  const text = readFileSync(REAL, 'latin1')
  const once = serialize(parse(text))
  assert.equal(serialize(parse(once)), once)
  assert.ok(parse(once).get('GuildyDB').get('guilds') instanceof LuaTable)
})
