# Gear on the Character Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Guildy stores each member's gear item by item with enchantments, shares it, and the rebuilt character page (variant A) shows it beside the game's 3D model, with a ready mark, "Upgrades aus der Gilde" and the member's activity score with its breakdown; the bnet-sync script fills the same fields.

**Architecture:** Two pure modules (`Core/Gear.lua`, `Core/Upgrades.lua`) hold the record, its wire form, merge, ready mark, enchant-line diff, craft map and upgrade rules, all unit-tested. A new `Game/Gear.lua` reads own gear and takes the per-slot links the existing inspect in `Game/Stats.lua` already gets, records recipe → item, and resolves enchant text. `Game/Sync.lua` adds a `GEAR` message and `SUM.g`; a `CRAFT` message is built only if the in-game probe says so. `UI/CharacterPage.lua` is rebuilt as variant A. `Core/Activity.lua` keeps the inputs of each player's score so the page can explain it; nothing new is synced for that.

**Tech Stack:** Lua 5.1 addon (WoW Forever, Interface 16001), `luajit tests/run.lua`; Node ≥ 20 for `tools/bnet-sync` (`node --test "tools/bnet-sync/*.test.mjs"`).

**Spec:** `docs/superpowers/specs/2026-11-13-gear-character-page-design.md` (including "Decided by Sven (2026-11-13)"). Visual target: `media/gallery/mock/character-a.png`, brief `.impeccable/surfaces/ui-characterpage-lua.md`, `PRODUCT.md`.

## Global Constraints

- Everything works in the game alone; the script only fills the same fields faster. Nothing the script writes is gated.
- `Protocol.VERSION` stays 1. New messages and `SUM` fields are dropped silently by older versions; never rely on them answering.
- Never compare or store a secret value: any link/name/unit value for which `ns.AnySecret` is true aborts that read.
- Nothing is stored while `ns.Anon.on`. Real member names never reach published images: every maker name drawn on the page goes through `ns.Anon.Name`.
- Own gear is sent only with `settings.share`; others' gear is relayed like statistics.
- Stored shape (exact): `guild.gear[nameKey] = { ts, src = "self"|"seen"|"relay"|"api", race = raceID|nil, sex = 2|3|nil, items = { [slot] = { id, e, s, l, q } } }`, slots 1..19 (4 shirt and 19 tabard for the model only), `e`/`s` = 0 when none, `q` 0..5.
- Merge: newer `ts` wins; at equal `ts`, `src == "self"` wins. An incomplete read (a slot with an item ID but no link) is never stored.
- `Gear.ENCHANTABLE` = back 15, chest 5, wrist 9, hands 10, feet 8, main hand 16, off hand 17 only when it is a weapon or shield. Head, shoulders, legs show an enchantment when present, never flagged missing.
- Ready mark = median `Stats.GEAR.ILVL` of roster members at the same level with gear known, only with at least 5 of them; else no tick and no header part.
- Upgrades: never main hand 16, off hand 17, ranged 18. Candidate must beat the stored level by at least 3, fit the slot, required level ≤ member level, wearable armour, not bind-on-pickup (bind type 1), from another member's book. At most 3 rows, sorted by gain; makers online first, then by last seen.
- Per account: `GuildyDB.craftItems = { [spellID] = itemID }` (equippable only, cap 3000); `GuildyDB.enchantText = { locale, names = { [enchantID] = text } }`, reset on locale change.
- `GEAR` wire: `{ m = name, g = { ts, src, r, x, i = { "slot:id:e:s:l:q", ... } } }`; `SUM.g = { [nameKey] = ts }` for records younger than 60 days; offers after 12–20 s random delay, at most `MAX_OFFERS`.
- The dungeon collection leaves the character page completely. Where `SetCustomRace` is not supported, members not nearby keep today's race-icon portrait; gear is never shown on the viewer's own body.
- Smallest window 1130 × 560: all 17 list rows visible, row height ≥ 18 px; the level bar narrows first, the enchant text truncates with "…" before the item name does.
- Every new locale key exists in deDE, enUS, frFR, esES, ruRU, ptBR (no middle dot "·" in ruRU). German texts as players say them.
- Activity score on the page: score 0–100 with its `Activity.Bucket` colour and label, "–" when there is none; the tooltip shows presence x/30, playing x/25, group play x/45, what fed each part per week, the scaled-to-100 line below `MIN_COUNTED` days, fade factor and days away beyond `FADE_FROM`, that the score is per player (characters named when several, through `ns.Anon.Name`) and its window. No new sync data.
- The relayed-own-gear rule (equal or older `ts` never replaces `self`) stays tested in Task 2 and smoked in Task 6.
- The changes go into the unreleased 1.8.0 section of `CHANGELOG.md`.

## Review Focus

- A secret item link (instance, combat) in the middle of an own or inspected read: nothing stored, no comparison made, no error (smoke test in Task 5 with `SECRET`).
- A relayed `GEAR` with slot 20, slot 0, a float item ID, `q = 9`, `ts` an hour in the future, or 40 slot strings: refused or trimmed by `Gear.Validate` (test in Task 2).
- A member without an activity score (lead character without a current reading, fresh install, a twink whose main was never read): the score tile shows "–" and its tooltip says there is no current reading, never 0 and never parts of another player (smoke in Task 10).
- An off hand left empty by a two-hander: not flagged "keine Verzauberung", not counted in the header, not an upgrade slot (tests in Tasks 2 and 3).
- Item info not loaded yet when the page draws (fresh login, relayed items never seen): rows draw from the stored `l`/`q` with a placeholder name, no Lua error, and the page redraws on `GET_ITEM_INFO_RECEIVED` (smoke in Task 9).

---

### Task 1: In-game probes (`/guildy modeltest`, `/guildy craftprobe`, `/guildy gearshow`)

The three checks the spec says the builder runs first. They depend on nothing else in this plan; `gearshow` reads live links (own character, or the target) until Task 5 adds stored records.

**Files:** Create `Game/GearProbe.lua`; modify `Guildy.toc` (after `Game\Stats.lua`), `Core/Init.lua` (slash `modeltest`, `craftprobe`, `gearshow`), `tests/smoke.lua`.

**Interfaces:**
- Produces: `ns.GearProbe.ModelTest(args: string)`, `ns.GearProbe.CraftProbe()`, `ns.GearProbe.GearShow(name: string)`, `ns.GearProbe.TooltipLines(link) -> { string }` (reused by Task 5: `C_TooltipInfo.GetHyperlink(link).lines[i].leftText` when present, else a hidden `GameTooltip` named `GuildyScanTooltip` with `SetHyperlink` and its `TextLeft<i>` regions).

- [ ] **Step 1: Write the smoke test** `it("runs the gear probes without errors")`: call each slash command through `env.SlashCmdList.GUILDY("modeltest")`, `("modeltest 1 2")`, `("craftprobe")`, `("gearshow")`, `("gearshow Au Tsch")`; run timers; `T.eq(errors, {})`; assert that printed output contains `"SetCustomRace"` and `"craftprobe:"` (capture `ns.Print`).
- [ ] **Step 2:** `luajit tests/run.lua` — the new test fails (unknown commands open the window, no output).
- [ ] **Step 3: Implement `Game/GearProbe.lua`.**
  - `ModelTest(args)`: create once a `DressUpModel` frame (300 × 400, centred, movable, a close button); print `yes/no` for each of `SetUnit`, `SetCustomRace`, `Undress`, `TryOn`, `SetSheathed`, `SetFacing`, `SetPortraitZoom`. With `raceID sex` given: `SetCustomRace(raceID, sex)`, `Undress()`, `TryOn` every own equipped link (slots 1..19). Without args: step through races `{1,2,3,4,5,6,7,8,10,11}` × sex `{0,1,2,3}` every 3 s, printing the pair, so Sven sees which gender values work. Every call through `pcall`; print errors.
  - `CraftProbe()`: collect up to 200 distinct spell IDs from `ProfRec.recipes` of members other than the own characters; for each, `C_TradeSkillUI.GetRecipeOutputItemData(spellID)` (`pcall`); count resolved (`.itemID` number) and, of those, equippable (`C_Item.GetItemInfoInstant(itemID)` or `GetItemInfoInstant`, 4th return `itemEquipLoc` not `""`). Print `craftprobe: N asked, R resolved (P %), E equippable` and the first 5 unresolved IDs.
  - `GearShow(name)`: resolve the member (default: self; the target when its name matches); for slots 1..19 print `slot, link-or-nil, item info loaded yes/no`, and for each link with an enchant ID ≠ 0 the line(s) `TooltipLines("item:id:e")` has that `TooltipLines("item:id")` lacks. Print which tooltip path was used.
- [ ] **Step 4:** `luajit tests/run.lua` — all green (362 + new).
- [ ] **Step 5: Commit** `feat: gear probes for the model, crafted items and enchant text`.

---

> ## ⏸ STOP POINT 1 — Sven tests in game before Tasks 7 and 12
>
> Sven runs, on Forever, and reports the printed output:
> 1. `/guildy modeltest` (watch the cycle) and `/guildy modeltest <ownRaceID> <sex>` — **reports:** does `SetCustomRace` exist and change the body; which gender values give male/female (0/1 or 2/3); does `TryOn` dress the custom body; does `Undress` exist.
> 2. `/guildy craftprobe` in a guild with relayed books — **reports:** the resolved percentage.
> 3. `/guildy gearshow` on his own character with an enchanted item, and on a target — **reports:** whether an enchant line comes out, and which tooltip path.
>
> Record the answers in this plan under "Probe results" below before going on. Tasks 2–6 and 8–11 do not depend on them and may proceed while waiting; **Task 7 (CRAFT) and Task 12 (model) must not start before the results are recorded.**
>
> **Probe results:** _(to fill in)_
> - SetCustomRace supported: ☐ yes ☐ no — gender values: male = __, female = __ — TryOn on custom body: ☐ yes ☐ no
> - craftprobe resolved: __ % → CRAFT ☐ not built (≥ 95 %) ☐ built (< 95 %)
> - Enchant text path: ☐ C_TooltipInfo ☐ hidden GameTooltip ☐ neither (fallback: show nothing, never the raw ID)

---

### Task 2: Core/Gear.lua

**Files:** Create `Core/Gear.lua`, `tests/test_gear.lua`; modify `Guildy.toc` (after `Core\Stats.lua`), `tests/lib.lua` (`PURE`, after `Core/Stats.lua`), `tests/run.lua` (`FILES`).

**Interfaces:**
- Produces:
  - `Gear.SLOTS = {1..19}`, `Gear.LIST_SLOTS` = `Stats.GEAR_SLOTS` (17, no shirt/tabard), `Gear.MAX_AGE = 60 * 86400`, `Gear.ENCHANTABLE = { [15]=true, [5]=true, [9]=true, [10]=true, [8]=true, [16]=true, [17]="weapon" }`.
  - `Gear.ParseLink(link) -> id, enchant, suffix | nil` (`item:id:enchant:g1:g2:g3:g4:suffix`, missing fields → 0).
  - `Gear.ItemString(item) -> "item:<id>:<e>:0:0:0:0:<s>"`.
  - `Gear.FromLinks(links: {[slot]=link}, ids: {[slot]=itemID}, info: fn(link)->quality, level) -> items | nil` (nil when a slot has an ID but no link, or info missing for a link).
  - `Gear.Validate(raw, now) -> rec | nil` (wire form → stored form).
  - `Gear.Wire(rec) -> { ts, src, r, x, i = { "slot:id:e:s:l:q", ... } }` (sorted by slot).
  - `Gear.Merge(book, key, rec) -> changed`.
  - `Gear.Digest(book, now) -> { [key] = ts }` (younger than `MAX_AGE` only).
  - `Gear.Prune(book, keep) -> removed`.
  - `Gear.Average(rec) -> tenths | nil` (mirror of `Stats.ReadGear`'s average over `LIST_SLOTS` with an item).
  - `Gear.Unenchanted(rec, equipLocOf: fn(itemID)->equipLoc|nil) -> { [slot]=true }, count` (off hand counts only for `INVTYPE_WEAPON`, `INVTYPE_WEAPONOFFHAND`, `INVTYPE_SHIELD`; an unknown equipLoc for 17 does not count).
  - `Gear.ReadyMark(list: { {level, ilvl} }, level) -> tenths | nil` (median, `MIN_READY = 5`).
  - `Gear.EnchantLine(withLines, withoutLines) -> text | nil` (first line of `with` not in `without`, counting duplicates; trims colour codes).
  - `Gear.EnchantCache(db, locale) -> names` (creates/resets `db.enchantText`).
  - `Gear.Fit(height, width) -> rowH, barW, enchantW` (17 rows; `rowH = max(18, floor((height - 52) / 17))`; `barW` shrinks from 130 to 60 first, then `enchantW` from 200 to 0; item name keeps at least 140).

- [ ] **Step 1: Write `tests/test_gear.lua`** with at least these cases:
  - `ParseLink("|cff0070dd|Hitem:12345:1887:0:0:0:0:-17:0:60|h[X]|h|r")` → `12345, 1887, -17`; `ParseLink("item:7")` → `7, 0, 0`; `ParseLink(nil)` → nil.
  - `FromLinks` returns nil when slot 5 has an ID but no link; stores shirt 4 and tabard 19; `l`, `q` from info; `q` clamped to 0..5.
  - `Validate`: accepts a good record; drops slots 0 and 20, a float id, `q = 9`, non-integer `l`; returns nil for `ts > now + 300`, missing `ts`, non-table; reads at most 19 slot strings; `src` outside the four values → `"relay"`; `r`/`x` kept only as positive integers, `x` only 2 or 3.
  - `Wire` then `Validate` round-trips a record exactly.
  - `Merge`: newer wins; older loses; equal `ts` with `src = "self"` replaces a `"seen"`; equal `ts` `"relay"` never replaces `"self"`.
  - `Digest` leaves out a record 61 days old; `Prune` removes keys not in `keep`.
  - `Average` of items at 30, 20, 40 (+ shirt at 1) → 300; nil for no items.
  - `Unenchanted`: chest and feet without enchant counted, head without not; off hand 17 with `INVTYPE_HOLDABLE` not counted, with `INVTYPE_SHIELD` counted; an empty 17 (two-hander) not counted.
  - `ReadyMark`: 4 members at level 60 → nil; 5 at levels 60 with ilvl 400, 420, 450, 470, 500 → 450; members of other levels ignored; even count → lower median (documented).
  - `EnchantLine({"Name","Brust","+4 Werte","Rüstung"}, {"Name","Brust","Rüstung"})` → `"+4 Werte"`; identical lists → nil.
  - `EnchantCache` resets `names` when the locale changes, keeps them when it is the same.
  - `Fit(17*18+52, 900)` → `rowH == 18`; `Fit(300, 900)` still `rowH == 18`; at width 560 `barW == 60` and `enchantW < 200`.
- [ ] **Step 2:** `luajit tests/run.lua` — FAIL (`Core/Gear.lua` missing).
- [ ] **Step 3: Implement `Core/Gear.lua`** to the interfaces above; pure, no WoW API; header comment with the stored shape like `Core/Cooldowns.lua`.
- [ ] **Step 4:** `luajit tests/run.lua` — green.
- [ ] **Step 5: Commit** `feat: Core/Gear.lua, gear records item by item`.

### Task 3: Core/Upgrades.lua

**Files:** Create `Core/Upgrades.lua`, `tests/test_upgrades.lua`; register like Task 2 (after `Core\Gear.lua`).

**Interfaces:**
- Consumes: `Gear` record shape (Task 2).
- Produces:
  - `Upgrades.MAX_CRAFTS = 3000`, `Upgrades.MIN_GAIN = 3`, `Upgrades.LEFT_OUT = { [16]=true, [17]=true, [18]=true, [4]=true, [19]=true }`.
  - `Upgrades.SLOTS_OF[equipLoc] = { slot, ... }` (`INVTYPE_HEAD`→{1}, `INVTYPE_NECK`→{2}, `INVTYPE_SHOULDER`→{3}, `INVTYPE_CHEST`/`INVTYPE_ROBE`→{5}, `INVTYPE_WAIST`→{6}, `INVTYPE_LEGS`→{7}, `INVTYPE_FEET`→{8}, `INVTYPE_WRIST`→{9}, `INVTYPE_HAND`→{10}, `INVTYPE_FINGER`→{11,12}, `INVTYPE_TRINKET`→{13,14}, `INVTYPE_CLOAK`→{15}).
  - `Upgrades.ARMOR[classFile] = { best, bestFrom40 }` with subclass IDs cloth 1, leather 2, mail 3, plate 4: MAGE/PRIEST/WARLOCK {1,1}, ROGUE/DRUID {2,2}, HUNTER/SHAMAN {2,3}, WARRIOR/PALADIN {3,4}.
  - `Upgrades.Wearable(classFile, level, info, wornSubclasses) -> bool` (armour class 4 only: subclass 0 and cloaks always; else ≤ the class's best for the level, or a subclass the member already wears).
  - `Upgrades.Learn(map, spellID, itemID) -> bool` (cap; refuses non-integers).
  - `Upgrades.Clean(map, isEquippable: fn(itemID)->bool|nil) -> removed` (nil = unknown yet, kept).
  - `Upgrades.For(member, gearRec, makers, craft, itemInfo) -> rows, missing`
    - `member = { key, level, classFile }`
    - `makers = { { key, online = bool, offline = hoursOrZero, profs = { [skillLine] = ProfRec } } }` (the member themself may be in it and is skipped)
    - `craft = { [spellID] = itemID }`
    - `itemInfo(itemID) -> { equipLoc, level, reqLevel, classID, subclassID, bind, quality } | nil`
    - `rows = { { slot, itemID, quality, have = l|0, offer = l, makers = { { key, skillLine, online } } } }`, at most 3, gain descending, then slot ascending; one row per slot (the best item).
    - `missing = { itemID, ... }` whose info was nil (to request).

- [ ] **Step 1: Write `tests/test_upgrades.lua`**:
  - A recipe in another member's book making a level-58 waist item beats a stored 47 → one row `{ slot = 6, have = 47, offer = 58 }` with that maker.
  - Gain 2 → no row; gain 3 → row.
  - The member's own book → no row.
  - `reqLevel` above member level → no row.
  - Bind type 1 → no row; bind type 2 → row.
  - Plate for a level-39 warrior → no row; at 40 → row; mail for a level-20 hunter who already wears mail → row (worn subclass rule).
  - Main hand, off hand, ranged items → never a row.
  - Ring: compared with the lower of slots 11 and 12.
  - An empty slot → row with `have = 0`.
  - Four slots with gains → three rows, largest gain first.
  - Makers: online before offline, then fewer offline hours first.
  - `itemInfo` nil → no row, the ID in `missing`.
  - `Learn` stops at `MAX_CRAFTS`; `Clean` removes `false`, keeps `nil`.
- [ ] **Step 2:** `luajit tests/run.lua` — FAIL.
- [ ] **Step 3: Implement `Core/Upgrades.lua`.**
- [ ] **Step 4:** `luajit tests/run.lua` — green.
- [ ] **Step 5: Commit** `feat: Core/Upgrades.lua, better crafted pieces from the guild`.

### Task 4: Core/Activity.lua keeps how a score was made

Independent of the gear tasks; may run any time before Task 10.

**Files:** Modify `Core/Activity.lua` (`ScorePlayer`, new `Activity.DayTime`), `Game/Activity.lua` (`GameActivity.ScoreOf` returns the detail as a third value), `tests/test_activity.lua`.

**Interfaces:**
- Produces:
  - `player.detail` next to `player.score`/`player.parts` whenever a score exists (nil otherwise):
    `{ rates = { kills, honorKills, quests, raidBosses, dungeonBosses, dungeons, battlegrounds } (summed weekly rates of the counted characters), presence = daysPerWeek | nil, scaled = bool (presence nil → playing and group scaled to 100), fade = keepFactor | nil, away = days | nil (both only when the lead is away more than FADE_FROM days), chars = { memberKey, ... } (characters whose rates were counted, lead first), fromDay, toDay (the lead's window, Activity.Day numbers) }`.
  - `player.parts` stays as today (points after fading).
  - `Activity.DayTime(day) -> ts` (the existing local `Noon`, exported, for dates in the tooltip).
  - `GameActivity.ScoreOf(memberKey) -> score, parts, detail` (existing callers use the first two and are unchanged).

- [ ] **Step 1: Write the failing tests in `tests/test_activity.lua`** (reusing the file's `rates`/`recordOf` helpers):
  - Main + twink both with readings → `byKey.a.detail.chars == { "a", "b" }`, `detail.rates.kills` == sum of both characters' weekly kills, `detail.fromDay`/`toDay` == the lead's `Rates` window.
  - `since` 3 days ago (fewer than `MIN_COUNTED`) and no own-days counter → `detail.presence == nil`, `detail.scaled == true`; `since` 9 days ago → `presence` == the seen days × 7 / counted, `scaled == false`.
  - Lead offline 10 days → `detail.away == 10`, `detail.fade` == `1 - (10 - 3) / (30 - 3)` (to 1e-9), and `score` equals the rounded unfaded score × `fade`; online lead → `fade == nil`, `away == nil`.
  - A twink without a current reading is not in `detail.chars`.
  - Lead without a reading → `score == nil`, `detail == nil`.
  - `Activity.DayTime(Activity.Day(ts))` lies on the same day as `ts`.
- [ ] **Step 2:** `luajit tests/run.lua` — the new cases fail (`detail` nil).
- [ ] **Step 3: Implement** in `ScorePlayer`: collect `chars` while summing, keep `presence`, `scaled = presence == nil`, `fade`/`away` in the fade branch, `fromDay`/`toDay` from `sum`; assign `player.detail`. No change to the score values (all existing activity tests stay green unchanged).
- [ ] **Step 4:** `luajit tests/run.lua` — green.
- [ ] **Step 5: Commit** `feat: the activity score keeps what it was made of`.

### Task 5: Game side — reading, storing, recipe → item, enchant text

**Files:** Create `Game/Gear.lua`; modify `Game/Stats.lua` (`ReadUnitGear` also returns links; `Finish` and `CheckLateGear` hand them on), `Game/TradeSkill.lua` (`ScanOpen` records spell → item), `Game/Roster.lua` (prune `guild.gear`), `Core/Init.lua` (event `GET_ITEM_INFO_RECEIVED`; login pass `GameGear.Start`; `gearshow` now calls `GameGear.Show`), `Game/GearProbe.lua` (`GearShow` delegates to the stored record when one exists), `Guildy.toc` (after `Game\Stats.lua`), `tests/smoke.lua`.

**Interfaces:**
- Consumes: `Gear.*` (Task 2), `Upgrades.Learn`/`Clean` (Task 3), `GearProbe.TooltipLines` (Task 1).
- Produces:
  - `ns.GameGear.ReadOwn()` (called from `GameStats.UpdateOwn` after `ReadOwn`; stores `src = "self"`, `race = select(3, UnitRace("player"))`, `sex = UnitSex("player")`; calls `Sync.ShareGear(key)` when changed and `settings.share`).
  - `ns.GameGear.Store(request, links, unit)` (`src = "seen"`; race/sex from `UnitRace(unit)`/`UnitSex(unit)` when not secret; shares through `Sync.ShareGear`).
  - `ns.GameGear.ItemInfo(itemID) -> table | nil` (the `Upgrades` itemInfo shape; requests `C_Item.RequestLoadItemDataByID` when nil).
  - `ns.GameGear.ResolveCrafts(spellIDs)` (asks `GetRecipeOutputItemData` 20 per frame for IDs without an entry; learns equippable ones; non-equippable remembered for the session).
  - `ns.GameGear.EnchantText(itemID, enchantID) -> text | nil` (cache first, then the tooltip diff; stores into the cache).
  - `ns.GameGear.Show(name)` (`/guildy gearshow`).
  - Event `ns.Fire("GEAR")` on any stored change; `GET_ITEM_INFO_RECEIVED` fires `"GEAR_INFO"` debounced 0.5 s.
  - `GameStats`: `ReadUnitGear(unit)` returns `values, links, ids`; `job.links`/`job.ids` carried to `Finish`, which calls `GameGear.Store(job.request, job.links, job.gearUnit)` only when `job.gear[S.GEAR.ILVL]` (complete read).

- [ ] **Step 1: Write the smoke tests:**
  - `it("stores the own gear item by item")`: stub `GetInventoryItemLink("player", slot)` for slots 1, 4, 5, 16 with enchant 1887 on 5; `ns.GameStats.UpdateOwn()`; `T.eq(guild.gear["ran fred"].items[5], { id = …, e = 1887, s = 0, l = …, q = … })`, `.src == "self"`, `.race`, `.sex` set; slot 4 present.
  - `it("stores the gear of an inspected member")`: drive the existing inspect path the stats smoke test uses (target, `INSPECT_ACHIEVEMENT_READY`, `INSPECT_READY`, run timers) → `guild.gear["au tsch"].src == "seen"`.
  - `it("stores nothing from a secret link")`: one slot returns `SECRET` → the own record unchanged, no error.
  - `it("stores nothing for pictures")`: `ns.Anon.Enable(true)`; `UpdateOwn` → no new record; disable again.
  - `it("learns the item a recipe makes")`: open an own legacy window stub with `GetTradeSkillItemLink(i)` → an equippable item → `GuildyDB.craftItems[spellID] == itemID`; a non-equippable one → not stored.
  - `it("prunes gear of members who left")`: a `guild.gear["gone member"]` disappears after a roster update.
  - `it("makes the enchant text from the tooltip")`: stub `C_TooltipInfo.GetHyperlink` → `GameGear.EnchantText(id, 1887)` returns the extra line and `GuildyDB.enchantText.names[1887]` holds it.
- [ ] **Step 2:** `luajit tests/run.lua` — the new tests fail.
- [ ] **Step 3: Implement** `Game/Gear.lua` and the hooks above. On `GameGear.Start` (login, 9 s): `Upgrades.Clean(GuildyDB.craftItems, equippable)` for entries the script wrote. `ScanOpen`: legacy window `GetTradeSkillItemLink(i)`, craft frame `GetCraftItemLink(i)`, modern `C_TradeSkillUI.GetRecipeOutputItemData(id).itemID`; links checked with `ns.IsSecret`. Use the tooltip path recorded in Probe results; if "neither", `EnchantText` returns the cache only.
- [ ] **Step 4:** `luajit tests/run.lua` — green.
- [ ] **Step 5: Commit** `feat: Guildy keeps the gear it reads item by item`.

### Task 6: Sync — `GEAR` and `SUM.g`

**Files:** Modify `Game/Sync.lua` (header comment, `seenGear`, `SendGear`, `Sync.ShareGear`, `OnGear`, `SUM.g` in `SendSummary`, offers in `OnSummary`, `HANDLERS.GEAR`), `tests/smoke.lua`.

**Interfaces:**
- Consumes: `Gear.Wire`, `Gear.Validate`, `Gear.Merge`, `Gear.Digest` (Task 2).
- Produces: `Sync.ShareGear(key)`; incoming `GEAR` fires `"GEAR"`.

- [ ] **Step 1: Write the smoke test** `it("shares gear with the guild")` in the style of "shares specializations and cooldowns":
  - `Receive("GEAR", { m = "Makira Farron", g = { ts = now, src = "self", r = 4, x = 3, i = { "5:12345:1887:0:52:3" } } }, "Makira-Farron", "g1")` → `guild.gear["makira farron"].items[5].e == 1887`, `.src == "self"`.
  - From another sender with `src = "self"` → stored as `"relay"`.
  - Someone outside the guild → nothing.
  - A relayed copy of `"ran fred"` (own) with equal `ts` → own record kept.
  - `SendSummary` → `sent.SUM.g["makira farron"] == now`; a record 61 days old not in it.
  - `ShareGear("ran fred")` → `sent.GEAR.g.i` has the slot strings; with `settings.share = false` → no `GEAR`.
  - `T.eq(errors, {})`.
- [ ] **Step 2:** `luajit tests/run.lua` — FAIL.
- [ ] **Step 3: Implement.** `OnGear` mirrors `OnCooldowns` (roster check, `Anon.on` check, `ns.Names.Same(sender, data.m)` → `"self"`, `"self"` from others → `"relay"`). Offers in `OnSummary`: `C_Timer.After(12 + math.random() * 8 + i * 0.5, …)` unless `seenGear[key] >= myTs`.
- [ ] **Step 4:** `luajit tests/run.lua` — green.
- [ ] **Step 5: Commit** `feat: gear travels between Guildy users`.

### Task 7: CRAFT message — ONLY if Probe results say craftprobe < 95 %

**Blocked by STOP POINT 1.** If craftprobe resolved ≥ 95 %, mark this task skipped with the number from Probe results and go on; nothing in other tasks depends on it.

**Files:** Modify `Core/Upgrades.lua` (`CraftDigest`, `CraftWire`, `CraftMerge`), `tests/test_upgrades.lua`, `Game/Sync.lua` (`CRAFT`, `SUM.k`), `Game/Gear.lua` (`own = { [spellID] = true }` for entries read in an own window this session), `tests/smoke.lua`.

**Interfaces:**
- Produces: `Upgrades.CraftDigest(map) -> { n = count, h = sum of spellIDs % 2^31 }`; `Upgrades.CraftWire(map) -> { { spellID, itemID, ... } }` (flat pairs, 400 pairs per message); `Upgrades.CraftMerge(map, list, own) -> changed` (union; on conflict the entry in `own` wins, else the existing one stays; respects `MAX_CRAFTS`).

- [ ] **Step 1: Tests:** digest of `{[1]=10,[2]=20}` is `{ n = 2, h = 3 }`; `CraftWire` of 900 entries gives 3 lists of ≤ 800 numbers; `CraftMerge` takes new pairs, keeps an own entry on conflict, refuses odd-length lists and non-integers. Smoke: a `CRAFT` message fills `GuildyDB.craftItems`; a `SUM` with a smaller `k.n` makes the client send its `CRAFT` once per state and sender (like `JOIN`).
- [ ] **Step 2:** run — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** run — green.
- [ ] **Step 5: Commit** `feat: Guildy users share which items recipes make`.

### Task 8: The script writes gear, enchant text and crafted items

**Files:** Modify `tools/bnet-sync/map.mjs` (`gearRecord`, `updateGear`, `enchantTexts`, `craftItems`), `tools/bnet-sync/sync.mjs` (call them; `craftedItem` for every recipe of guild books the bridge translates to exactly one spell), `tools/bnet-sync/map.test.mjs`, `tools/bnet-sync/README.md`.

**Interfaces:**
- Produces (exports of `map.mjs`):
  - `gearRecord(equipment, profile, ts) -> { ts, src: 'api', race, sex, items: { [slot]: { id, e, s, l, q } } } | null` (`SLOT_IDS` for `slot.type`; `item.id`; first `enchantments[].enchantment_id` or 0; suffix from the response field found while building, else 0; `level.value`; quality via the existing quality map → 0..5; `race = profile.race.id`; `sex` MALE → 2, FEMALE → 3).
  - `updateGear(guild, key, record) -> bool` (writes `guild.gear[key]` only when `record.ts` is newer than what is there).
  - `enchantTexts(db, equipment, locale)` (fills `GuildyDB.enchantText.names[enchantID]` from `display_string` cut after the first `": "`, only when `db.clientLocale === locale`; resets the table when its locale differs).
  - `craftItems(db, pairs: [[spellID, itemID]])` (writes `GuildyDB.craftItems`, cap 3000, integers > 0 only).

- [ ] **Step 1: Write tests in `map.test.mjs`:** `gearRecord` maps HEAD/SHIRT/CHEST/MAIN_HAND/TABARD to 1/4/5/16/19 with enchant and quality; FEMALE → 3; no `equipped_items` → null. `updateGear` refuses an older `ts`. `enchantTexts` cuts `"Verzaubert: Bergbau +2"` to `"Bergbau +2"` and writes nothing for another locale. `craftItems` caps and skips 0.
- [ ] **Step 2:** `node --test "tools/bnet-sync/*.test.mjs"` — FAIL.
- [ ] **Step 3: Implement**; in `sync.mjs` reuse the already fetched `equipment` and `profile`; print one line with the counts.
- [ ] **Step 4:** `node --test "tools/bnet-sync/*.test.mjs"` — green (28 + new).
- [ ] **Step 5: Commit** `feat(bnet-sync): gear, enchant text and crafted items into Guildy's fields`.

### Task 9: Character page, variant A — layout, gear list, family list, professions

**Files:** Modify `UI/CharacterPage.lua` (rebuild), `Locales/*.lua` (all six), `tests/smoke.lua`.

**Interfaces:**
- Consumes: `guild.gear`, `Gear.Average`, `Gear.Unenchanted`, `Gear.ReadyMark`, `Gear.Fit`, `Gear.ItemString` (Task 2); `GameGear.ItemInfo`, `GameGear.EnchantText` (Task 5); events `"GEAR"`, `"GEAR_INFO"`.
- Produces: `page.Gear` (box with `.Rows[i]`: `.Slot`, `.Icon`, `.Name`, `.Enchant`, `.Bar`, `.Tick`, `.Level`), `page.Upgrades` (empty box filled in Task 11), `page.ModelArea` (frame holding today's `Portrait`, the model comes in Task 12), `page:RenderGear(m)`.
- New locale keys (German given; the other five translated): `GEAR = "Ausrüstung"`, `GEAR_LEVEL_HEAD = "Gegenstandsstufe"`, `GEAR_AVG = "Ø %s"`, `GEAR_READY = "bereit ab %s"`, `GEAR_UNENCHANTED = "%d ohne Verzauberung"`, `NO_ENCHANT = "keine Verzauberung"`, `GEAR_UNSEEN = "Noch nicht gesehen. Guildy liest die Ausrüstung, sobald jemand mit Guildy %s ins Ziel nimmt."`, `GEAR_SEEN_AGO = "vor %s gesehen"`, `GEAR_SELF_AGO = "von %s selbst, vor %s"`, `GEAR_API_AGO = "aus dem Arsenal, vor %s"`, `UPGRADES = "Upgrades aus der Gilde"`, `UPGRADE_GAIN = "%d auf %d"`, `UPGRADES_NO_DATA = "Noch keine Rezepte der Gilde bekannt."`, `UPGRADES_NONE = "Nichts in der Gilde, das besser wäre."`, `MODEL_HINT = "Ziehen zum Drehen · Mausrad zum Zoomen"` (ruRU without "·"). Remove `DUNGEON_COLLECTION`, `DUNGEON_COUNT`, `DUNGEON_KILLS`, `DUNGEON_OPEN`, `NO_STATS_SHORT` from all six (only the page used them). Slot names come from the game's globals (`HEADSLOT`, `NECKSLOT`, `SHOULDERSLOT`, `BACKSLOT`, `CHESTSLOT`, `WRISTSLOT`, `HANDSSLOT`, `WAISTSLOT`, `LEGSSLOT`, `FEETSLOT`, `FINGER0SLOT`, `FINGER1SLOT`, `TRINKET0SLOT`, `TRINKET1SLOT`, `MAINHANDSLOT`, `SECONDARYHANDSLOT`, `RANGEDSLOT`) with English fallbacks.

Layout (mock `character-a.png`): left hero card `W.SIDE` wide — model area on top (~45 % of the card), `MODEL_HINT` under it, level ring top-right, name, title, race · gender · class, rank · zone · online, notes block, whisper/invite, officer bar (as today). Right of it: the four tiles across the full width (Task 10 adds a fifth; keep the tile row a loop over a key list so that is one entry); below them the gear box (about 62 % of the width) and a right column (family list, upgrades, professions). Gear rows in `Stats.GEAR_SLOT_GROUPS` order: slot name, 16 px icon (`GetItemIconByID`), item name in quality colour (suffix name once item info has it; placeholder `"…"` in the stored `q` colour before), enchant text in green or `NO_ENCHANT` in orange for slots `Gear.Unenchanted` names, item-level bar scaled to the guild's highest stored level with the ready tick, level number. Header right: `GEAR_AVG` · `GEAR_READY` · `GEAR_UNENCHANTED`, each part only when known. Row hover: `GameTooltip:SetHyperlink(Gear.ItemString(item))`. Under the list, small grey: the age/source line. Family: a plain list (name in class colour, level, class), as many lines as fit, "+N" after.

- [ ] **Step 1: Write the smoke tests:**
  - `it("shows the gear on the character page")`: store `guild.gear["au tsch"]` with 3 items (one chest without enchant, one off hand `INVTYPE_HOLDABLE` without enchant); `ShowMember(Au)`; row for slot 5 shows `L.NO_ENCHANT`, the off-hand row does not; header text contains the average.
  - `it("shows an empty gear list as finished")`: member with no gear → every row's level text is `"–"`, the unseen line contains the member's name.
  - `it("draws before item info is loaded")`: stub `GetItemInfo` → nil; render; no error; then return info and fire `GET_ITEM_INFO_RECEIVED`, run timers → the name is set.
  - `it("has no dungeon collection any more")`: `ns.UI.MemberPage().Dungeons == nil`.
  - `it("fits the smallest window")`: size the content to the area of a 1130 × 560 window (as `test_scale.lua` does), render, all 17 rows shown and each `GetHeight() >= 18`.
  - Existing page tests (family card, professions rows) adapted to the list.
- [ ] **Step 2:** `luajit tests/run.lua` — FAIL.
- [ ] **Step 3: Implement** the rebuild. Keep `RaceInfo`, `Portrait`, `UI.CharParts` (used by `UI/TabCommunities.lua`). Medal icons go (no room beside the model; the first-place title stays as the title line). `Gear.Fit` drives row height and widths; enchant text `SetWordWrap(false)` with truncation before the name.
- [ ] **Step 4:** `luajit tests/run.lua` — green (incl. locale tests).
- [ ] **Step 5: In-game check (Sven):** open his own page and a guildmate seen nearby: gear rows, enchant green/orange, hover tooltip, empty state for an unseen member; shrink the window to the smallest size in German. Report anything that clips.
- [ ] **Step 6: Commit** `feat: the character page shows the gear slot by slot`.

### Task 10: Activity score tile and its tooltip

**Files:** Modify `UI/CharacterPage.lua` (`page.Tiles.score`, `page:RenderScore(m)`, `Layout` with five tiles), `Locales/*.lua` (all six), `tests/smoke.lua`.

**Interfaces:**
- Consumes: `GameActivity.ScoreOf(m.key) -> score, parts, detail`, `Activity.DayTime` (Task 4); `Activity.Bucket`, `Activity.MAX`, `Activity.MIN_COUNTED`; existing keys `SCORE_1`..`SCORE_5`; the bucket colours the members tab uses for its activity bars.
- Produces: a fifth tile in the tile row, after "Ø Itemlevel": label `SCORE_TILE`, value the score (or "–"), line the bucket label in the bucket colour (`SCORE_5` when none). Tooltip on hover (`GameTooltip`, `ANCHOR_BOTTOM`):
  1. title `SCORE_TIP_TITLE` (score) in the bucket colour;
  2. `SCORE_PART_PRESENCE` x/30 with `SCORE_FED_PRESENCE` (days a week, one decimal) under it in grey, or `SCORE_PRESENCE_UNCOUNTED` when `detail.presence` is nil;
  3. `SCORE_PART_PLAYING` x/25 with `SCORE_FED_PLAYING` (kills, honorable kills, quests per week);
  4. `SCORE_PART_GROUP` x/45 with `SCORE_FED_GROUP` (raid bosses, dungeon bosses, dungeon runs, battlegrounds per week);
  5. when `detail.scaled`: `SCORE_SCALED` (`MIN_COUNTED`);
  6. when `detail.fade`: `SCORE_FADED` (days away, percent kept);
  7. `SCORE_PER_PLAYER`; when `#detail.chars > 1`: `SCORE_CHARS` with the names (`ns.Anon.Name`, class colour) joined by `ns.L.SEP`;
  8. `SCORE_WINDOW` with the two dates (`GameStats.Date` on `Activity.DayTime(fromDay/toDay)`, the date format the page already uses for "Mitglied seit").
  Without a score: only `SCORE_5` and `SCORE_HINT`.
  Parts are shown rounded to whole points; weekly numbers with one decimal below 10, whole above.
- New locale keys (German given): `SCORE_TILE = "Aktivität"`, `SCORE_TIP_TITLE = "Aktivität %d von 100"`, `SCORE_PART_PRESENCE = "Anwesenheit %d/%d"`, `SCORE_PART_PLAYING = "Spielen %d/%d"`, `SCORE_PART_GROUP = "Gruppenspiel %d/%d"`, `SCORE_FED_PRESENCE = "%s Tage online pro Woche"`, `SCORE_PRESENCE_UNCOUNTED = "noch nicht gezählt"`, `SCORE_FED_PLAYING = "pro Woche: %s Kills, %s ehrenhafte Siege, %s Quests"`, `SCORE_FED_GROUP = "pro Woche: %s Raidbosse, %s Dungeonbosse, %s Dungeons, %s Schlachtfelder"`, `SCORE_SCALED = "Anwesenheit zählt erst nach %d Tagen, bis dahin sind Spielen und Gruppenspiel auf 100 hochgerechnet."`, `SCORE_FADED = "Seit %d Tagen nicht online: nur noch %d %% des Werts."`, `SCORE_PER_PLAYER = "Der Wert gilt für den Spieler, Main und Twinks zusammen."`, `SCORE_CHARS = "Gezählt: %s"`, `SCORE_WINDOW = "Zeitraum: %s bis %s"`. Placeholders identical and in the same order in all six (the locale test checks it); no "·" in ruRU.

Placement (ruling): a fifth tile in the existing tile row rather than a box in the right column. At 1130 × 560 the right side is about 830 px wide, so five tiles are about 158 px each — enough for "15.112" in the huge font and "Platz 1 von 91"; the right column keeps its height for family, upgrades and professions, and the gear list loses no rows. `Layout` computes `tileW = floor((width - 4 * 8) / 5)`; the quality bars of the item-level tile use its new width.

- [ ] **Step 1: Write the smoke tests:**
  - `it("shows the activity score on the character page")`: give a member a score through stats records like the activity smoke tests do; `ShowMember`; `page.Tiles.score.Value:GetText()` is the score from `GameActivity.ScoreOf`; `Line` is `L["SCORE_" .. Activity.Bucket(score)]`.
  - `it("explains the score in its tooltip")`: trigger the tile's `OnEnter`; collect `GameTooltip` lines (stub `AddLine`/`SetText`); they contain the three part lines with `/30`, `/25`, `/45`, the window line, and for a main with a twink the `SCORE_CHARS` line with both names; with `ns.Anon.Enable(true)` the real names are absent.
  - `it("shows no score as a dash")`: member without a current reading → `Value` is `"–"`, `Line` is `L.SCORE_5`, tooltip has no part lines.
  - `it("fits five tiles in the smallest window")`: content at 1130 × 560, every tile `GetWidth() >= 150`.
- [ ] **Step 2:** `luajit tests/run.lua` — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** `luajit tests/run.lua` — green (incl. locale tests).
- [ ] **Step 5: In-game check (Sven):** his own page and a guildmate with twinks: tile value matches the members tab's score column, tooltip lines read naturally in German, nothing clips at the smallest window.
- [ ] **Step 6: Commit** `feat: the activity score on the character page, with how it is made`.

### Task 11: "Upgrades aus der Gilde"

**Files:** Modify `UI/CharacterPage.lua` (`page:RenderUpgrades(m)`), `Game/Gear.lua` (`GameGear.UpgradesFor(m) -> rows, state` where state is `"nodata"|"none"|"rows"`), `tests/smoke.lua`.

**Interfaces:**
- Consumes: `Upgrades.For` (Task 3), `GameGear.ItemInfo`, `GameGear.ResolveCrafts` (Task 5), `ns.Roster.Members()` for online/last seen, `TradeSkill.Record(m)` for books.
- Produces: rows drawn as slot · item name in quality colour · `UPGRADE_GAIN`, under it the maker(s) (`ns.Anon.Name`), profession name, online green / offline grey; click on a maker → `UI.Whisper(fullName)`. Empty: `UPGRADES_NO_DATA` when no book of another member has a recipe in `craftItems`; `UPGRADES_NONE` when there is data but no row.

- [ ] **Step 1: Write the smoke tests:** a member with a level-47 waist item, another member whose book has spell 99001, `GuildyDB.craftItems[99001] = 50001` with item info (waist, level 58, req 50, cloth, bind 2) → the box shows one row with `"47 auf 58"` and the maker's name; with `ns.Anon.Enable(true)` the maker's real name does not appear; without any craft entry → `UPGRADES_NO_DATA`; with an entry that is not better → `UPGRADES_NONE`; missing item info → `C_Item.RequestLoadItemDataByID` called with 50001.
- [ ] **Step 2:** run — FAIL.
- [ ] **Step 3: Implement.** Showing the page calls `ResolveCrafts` for the spell IDs of guild books without an entry; the page redraws on `"GEAR_INFO"`.
- [ ] **Step 4:** run — green.
- [ ] **Step 5: In-game check (Sven):** a member below a crafter's recipe level shows a row; whispering a maker from the box works.
- [ ] **Step 6: Commit** `feat: upgrades from the guild on the character page`.

### Task 12: The model

**Blocked by STOP POINT 1.** Pick the path from Probe results.

**Files:** Modify `UI/CharacterPage.lua` (`page.Model`, a `DressUpModel` in `page.ModelArea`), `Game/Gear.lua` (`GameGear.DressModel(model, m) -> bool`, `GameGear.MODEL_SEX = { [2] = <male value>, [3] = <female value> }` from Probe results), `tests/smoke.lua`.

**Interfaces:**
- Produces: `GameGear.DressModel(model, m)`:
  1. a unit token points at the member (`FindUnit`-style search over target, mouseover, focus, party, raid, nameplates; expose `GameStats.FindUnitByGuid(guid)` from `Game/Stats.lua`) → `model:SetUnit(unit)`, true;
  2. **path A (SetCustomRace works):** stored `race` and `sex` → `SetCustomRace(race, MODEL_SEX[sex])`, `Undress()`, `TryOn(Gear.ItemString(item))` for every stored slot incl. 4 and 19, true;
  3. otherwise false → the page hides the model and shows today's race/class portrait, no hint text.
  **Path B (not supported):** step 2 is left out entirely; never `SetUnit("player")` for someone else.
- Drag rotates (`SetFacing`, mouse delta × 0.01 rad), wheel zooms (`SetPortraitZoom` 0..0.8 in steps of 0.1); the own character always via `SetUnit("player")`.

- [ ] **Step 1: Write the smoke tests:** own page → `SetUnit("player")` called; a member with a stored race and no unit → (path A) `SetCustomRace` and `TryOn` called with item strings, (path B) model hidden and portrait shown; a member without race → portrait shown, `MODEL_HINT` hidden; `SetUnit("player")` is never called for another member (record calls on the stub).
- [ ] **Step 2:** run — FAIL.
- [ ] **Step 3: Implement** the chosen path.
- [ ] **Step 4:** run — green.
- [ ] **Step 5: In-game check (Sven):** own model in own gear; a guildmate in range (`SetUnit`); a guildmate far away (path A: their race in their gear; path B: portrait); drag and wheel work; the model never shows his own body for someone else.
- [ ] **Step 6: Commit** `feat: the character page shows the character in its gear`.

### Task 13: Changelog, README and final checks

**Files:** Modify `CHANGELOG.md` (1.8.0), `tools/bnet-sync/README.md` (if not done in Task 8), `Game/GearProbe.lua` (quiet: prints only when typed; keep all three commands as debug commands like `statshow`).

- [ ] **Step 1:** Add to the 1.8.0 section, in the voice of the existing entries: the character page shows each member's gear slot by slot with enchantments, the 3D model (path per Probe results), the ready mark, "Upgrades aus der Gilde", the activity score as a tile whose tooltip explains how it is made, that gear comes from targeting members nearby and is shared between Guildy users (own gear only with "share my data"), that the dungeon collection left the page (it stays in the Hall of Fame), `/guildy gearshow`.
- [ ] **Step 2:** `luajit tests/run.lua` and `node --test "tools/bnet-sync/*.test.mjs"` — both green; note the counts.
- [ ] **Step 3: Commit** `docs: changelog for gear on the character page`.

> ## ⏸ STOP POINT 2 — Sven's final in-game check
>
> 1. Character page at 1130 × 560 in German and in Russian (`/guildy` language switch or client): no clipping, all 17 rows, enchant text truncates before item names, five tiles readable, the score tooltip's lines do not run off screen.
> 2. `/guildy sync` in the guild (~100 members): size of `SUM` with `g` — if it needs more than two parts more than before, shorten `Gear.MAX_AGE` from 60 days (spec §7).
> 3. `/guildy shots`: the character page picture shows no real names in the upgrades box.
> 4. One run of the script, then login: a member never seen in game shows gear with enchant text.

---

## Spec rulings made while planning

- `Upgrades.For` gets the craft map as its own parameter (`member, gearRec, makers, craft, itemInfo`); the spec's signature had no place for it.
- Armour table: hard-coded with mail/plate from level 40, plus "a subclass the member already wears is always allowed", so a Forever change downward never hides a real upgrade (spec §7 left this open).
- Medal icons leave the hero card (the mock and the brief have none; the model needs the room); the first-place title stays.
- Rings and trinkets compare against the weaker of their two slots; an empty slot counts as level 0.
- `/guildy gearshow` reads live links until stored records exist, so the probe can run first.
- Activity score: shown as a fifth tile in the tile row (five tiles of about 158 px fit at 1130 × 560; the right column and the gear list keep their room). The tooltip's window is the lead character's window, the same one presence is counted over today; `player.detail` is nil whenever `score` is nil.
