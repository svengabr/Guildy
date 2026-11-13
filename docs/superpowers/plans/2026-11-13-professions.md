# Specializations, Cooldowns, Recipe Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Guildy shows profession specializations and cooldowns, shares both, and the bnet-sync script can fill complete recipe books and specializations for the whole guild.

**Architecture:** Two pure modules (`Core/Specs.lua`, `Core/Cooldowns.lua`) hold all rules and are unit-tested. `Game/TradeSkill.lua` detects own specializations and infers others from books; a new `Game/Cooldowns.lua` reads own cooldowns. `Game/Sync.lua` carries `spec` inside `PROF` and adds a `CD` message. The script writes the same fields, translating API names through a name map Guildy saves.

**Tech Stack:** Lua 5.1 addon (WoW Forever, Interface 16001), `luajit tests/run.lua`; Node ≥ 20 for `tools/bnet-sync` (`node --test`).

**Spec:** `docs/superpowers/specs/2026-11-13-professions-design.md`

## Global Constraints

- Everything works in the game alone; the script only fills the same fields faster.
- `Protocol.VERSION` stays 1.
- Specialization spells: engineering 20219/20222; blacksmithing 17039, 17040, 17041, 9787, 9788 (sub-specs first); leatherworking 10656, 10658, 10660.
- Cooldown seed: 17187, 11479, 11480, 17559–17566, 1317279 (alchemy 171), 18560 (tailoring 197), Salt Shaker item 15846 → spell 19566 (leatherworking 165).
- Stored shapes: `ProfRec.spec = { id, src = "known"|"api"|"book", ts }` (`id` 0 = none); `guild.cooldowns[key] = { ts, cd = { [spellID] = readyAt } }`; `GuildyDB.cooldownSpells[spellID] = skillLine`; `GuildyDB.recipeNames = { locale, names = { [spellID] = name } }`.
- Own cooldowns are shared only with `settings.share`; nothing is stored while `ns.Anon.on`.
- Every locale file gets the same new keys.

## Review Focus

- A relayed `spec` naming a spell of another profession, or `id = 0` from a book: refused (`Specs.Validate` test).
- A book with markers of two rival specializations: no inference (`Specs.FromBook` test).
- `Professions.Merge` with a newer rank update keeps the stored `spec` (test in test_specs).
- Cooldown readings that only differ by seconds of jitter do not count as a change, so nothing is re-shared every few seconds (`Cooldowns.Note` test).
- A cooldown record older than seven days, or a `readyAt` beyond seven days, is ignored (`Cooldowns.Validate`/`Of` tests).

---

### Task 1: Core/Specs.lua

**Files:** Create `Core/Specs.lua`, `tests/test_specs.lua`; modify `Core/Professions.lua` (`Merge` carries `spec`), `Guildy.toc` (after `Core\Professions.lua`), `tests/lib.lua`, `tests/run.lua`.

**Produces:** `Specs.ORDER[skillLine] = { spellID, ... }`, `Specs.SKILL_OF[spellID]`, `Specs.MARKERS[recipeSpellID] = specSpellID` (engineering only), `Specs.Detect(skillLine, isKnown) -> id`, `Specs.FromBook(skillLine, recipes) -> id|nil`, `Specs.Validate(skillLine, raw) -> spec|nil`, `Specs.Merge(rec, incoming) -> changed`.

- [ ] Tests first (detect order, book inference incl. rivals, validate refusals, merge rules of 6b.1, Merge carries spec), red, implement, green, commit.

### Task 2: Core/Cooldowns.lua

**Files:** Create `Core/Cooldowns.lua`, `tests/test_cooldowns.lua`; register like Task 1.

**Produces:** `Cooldowns.SEED`, `Cooldowns.ITEMS`, `Cooldowns.MAX_AGE = 7*86400`, `Cooldowns.Watched(learned)`, `Cooldowns.Learn(learned, spellID, skillLine)`, `Cooldowns.Note(book, key, cd, ts) -> changed` (60 s tolerance), `Cooldowns.Validate(raw, now)`, `Cooldowns.Merge(book, key, rec)`, `Cooldowns.Digest(book)`, `Cooldowns.Wire(rec)`, `Cooldowns.Of(book, key, now, skillLine?)`, `Cooldowns.Prune(book, keep)`, `Cooldowns.Span(seconds) -> unit, count`.

- [ ] Tests first, red, implement, green, commit.

### Task 3: Game side

**Files:** Modify `Game/TradeSkill.lua` (detect own specs in `ScanSkills`, infer in `StoreOwn` for links, report own window cooldowns from `ScanOpen`, `TradeSkill.InferAll()`, `TradeSkill.RememberNames()`), create `Game/Cooldowns.lua` (read own spell and item cooldowns, debounced, `/guildy cd` debug), modify `Core/Init.lua` (events `SPELLS_CHANGED`, `SPELL_UPDATE_COOLDOWN`, `BAG_UPDATE_COOLDOWN`, `LEARNED_SPELL_IN_TAB`; login pass; `GuildyDB.clientLocale`; slash `cd`, `spec`), `Game/Roster.lua` (prune cooldowns).

- [ ] Smoke test: a fake `IsSpellKnown` makes the own engineering record carry Goblin; a fake cooldown fills `guild.cooldowns`; `/guildy cd` and `/guildy spec` run.

### Task 4: Sync

**Files:** Modify `Game/Sync.lua`: `SendMember` adds `spec`; `OnProfessions` validates and merges it, infers from received books; `SUM.c` digest; `CD` send/receive/offer; `Sync.ShareCooldowns(key)`.

- [ ] Smoke test: a `CD` message from another member lands in `guild.cooldowns`; a `PROF` with `spec` lands on the record.

### Task 5: UI and locales

**Files:** Modify `UI/TabProfessions.lua` (name tag, book panel line for spec and cooldowns with dynamic offsets, rail tooltip), `UI/Popups.lua` (spec per profession, cooldown lines), `UI/CharacterPage.lua` (spec after profession name), `Locales/*.lua`, `CHANGELOG.md`.

- [ ] Smoke test: the professions tab renders a member with spec and cooldowns; locale tests pass.

### Task 6: Script

**Files:** Modify `tools/bnet-sync/map.mjs` (`professions()` returns `spec` and `recipes` names; `updateProfessions()` writes spec and complete recipe lists through the name map), `tools/bnet-sync/sync.mjs` (API locale from `clientLocale`), tests, `README.md`.

- [ ] `node --test "tools/bnet-sync/*.test.mjs"` green.
