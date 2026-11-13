# Guildy — gear on the character page

Date: 2026-11-13 · Author: Conoar (Sven) · Status: draft for review

Marks: **(Sven)** is what the author decided, **(call)** is a choice made while writing
this document that he has not discussed and may overrule.

## 1. Intent

Guildy stores the gear guild members wear, item by item with enchantments, and the character
page shows it next to a 3D model of the character in that gear. **(Sven)** The Battle.net script
(`tools/bnet-sync`) reads gear and enchantments too and writes them into the same fields. **(Sven)**

The page is rebuilt as variant A, "readiness" (`media/gallery/mock/character-a.png`, drawn by
`media/gallery/mock_character.py`). **(Sven)** Its four jobs: is this member ready for a raid or
dungeon; which slots are weak and who in the guild can craft better; looking at guildmates for fun;
officers judging a promotion. **(Sven)** The surface brief `.impeccable/surfaces/ui-characterpage-lua.md`
and `PRODUCT.md` are binding; this document settles the two points the brief left unresolved
(upgrade data, the model of members who are not nearby).

## 2. The constraint that shapes everything

As for professions: about 5000 installations, almost nobody runs the script. **(Sven)**

> Every field the script fills must also be fillable inside the game.
> The script only fills it faster. **(Sven)**

The game hands out another member's gear only through an inspect, and only while that member is
near. So most gear in a Guildy client was read by *some* Guildy user standing next to that member,
then relayed. One user who targets people in the capital fills the page for everyone.

## 3. What was established before writing this

Verified on 2026-11-13; not re-checked here.

- **Guildy already inspects.** `Game/Stats.lua` asks for statistics and gear together when a member
  becomes the target (mouseover as an opt-in), waits until every slot has a link, and reads the
  links per slot (`GetInventoryItemLink`). It stores only aggregates (`Stats.GEAR`: average item
  level, quality counts, quality per slot) in the stats record and shares them in `STAT`. The item
  links themselves are thrown away.
- **The page already knows race and gender**, but only for the session: `RaceInfo` in
  `UI/CharacterPage.lua` asks `GetPlayerInfoByGUID`, which answers once the client saw the character.
- **The profile API's `/equipment`** gives per item the real game item ID, `slot.type`, quality,
  item level, `enchantments[]` with `enchantment_id` and a localized `display_string`. Gear needs no
  name bridge. The profile itself carries race and gender.
- **The static recipe endpoint** gives `crafted_item.id` per API recipe. The script already caches
  it (`out/recipe-items.json`) and already bridges API recipes to the game's spell IDs by name.
- **Guildy's books store spell IDs** (`ProfRec.recipes`), never what a recipe makes. The only
  recipe→item knowledge in the addon today is `GuildyDB.recipeIcons` (per account, not shared) and
  a fallback through `C_TradeSkillUI.GetRecipeOutputItemData(spellID)` in `TradeSkill.RecipeIcon`.
- **The guild is levelling.** ~99 members, few at 60. Upgrades, ready marks and enchantments will be
  empty or thin for most members for a while; that is the normal view, not a broken one.

## 4. Goals, non-goals

- Every member Guildy has inspected, or whose gear a Guildy user shared, shows full gear with
  enchantments — with the game alone, in every guild. **(Sven)**
- The "Upgrades aus der Gilde" box shows only real data: an item a guild member's known recipe
  makes, better than what the member wears, usable by them. Nothing guessed. **(Sven)**
- The model is the game's own model frame, never a picture. **(Sven)**
- Saved data stays bounded: one gear record per roster member, a capped recipe→item map. **(call)**
- Not built: gems (not stored), set bonuses, item comparison tooltips
  beyond the game's own, "who can enchant this", gear history over months, an inspect button that
  works without a nearby member (the game has none). **(call)**
- Nothing is copied from inspect or gear addons under other licences (Guildy is GPL-3.0).

## 5. Approaches considered

**Getting other members' gear**

1. *Only what each Guildy user shares about their own character.* Clean, but a guild of mostly
   non-Guildy members stays empty.
2. *Inspect nearby, store per slot, relay* (picked). Extends the inspect `Game/Stats.lua` already
   runs; no new request, no new rate limit. Own gear goes out with `settings.share`, gear read
   nearby is relayed like statistics. The script fills the same record.
3. *Piggyback per-slot item IDs on `STAT`.* No new message, but `Stats.Validate` takes numbers only,
   the record is snapshotted per month (gear history nobody asked for, three times the size), and
   released versions treat every ID above `GEAR_BASE` as gear. Rejected.

**The model of a member who is not nearby**

Binding rule **(Sven)**: the model always shows the member's race and sex, never the viewer's own body
with someone else's race or sex.

Checked in game on Forever (2026-11-13, `/guildy modeltest scene <race>`): `DressUpModel` has no
`SetCustomRace`. What works is a `ModelScene` from the template `ModelSceneMixinTemplate`,
`TransitionToModelSceneID(596, 1, 1, true)`, its `GetPlayerActor()`, and
`actor:SetModelByUnit(unit, false, false, false, true, false, raceID)`. That shows a body of `raceID`
with the **sex of the unit passed**, hair and face from that unit; about 0.5 s later `Undress()` and
`TryOn(link)` dress it in every item, chest, legs, belt and boots included (race 1 with "player" gave
a human man, race 3 a dwarf, race 1 with a female Horde player targeted a human woman). A dressed body
stays when that unit leaves (checked by changing target). A creature display
(`SetModelByCreatureDisplayID`) shows only attachments (shoulders, weapon): not usable.

The routes, in order (`GameGear.ModelRoute`, `Game/Gear.lua`):

1. *Own page:* `SetModelByUnit("player")` without a race. The real look.
2. *A unit token shows the member right now* (target, focus, mouseover, party, raid, nameplate —
   `GameStats.FindUnitByGuid`): that unit, without a race. The real look.
3. *Stored race and sex:* a donor, a player unit whose `UnitSex` is the member's sex — "player" first,
   then target, focus, mouseover, party1-4, raid1-40, nameplate1-40, preferring units where
   `IsUnitModelReadyForUI` says yes; secret values are skipped, never compared. `SetModelByUnit(donor,
   …, member's raceID)` always with the race, so race and sex are the member's by construction; then
   `Undress()` and `TryOn` of every stored slot after 0.5 s. Face and hair are the donor's.
4. *No donor of that sex around:* the race portrait; while the page shows, Guildy looks again on
   `PLAYER_TARGET_CHANGED`, `NAME_PLATE_UNIT_ADDED`, `GROUP_ROSTER_UPDATE`, `UPDATE_MOUSEOVER_UNIT`
   (throttled to 0.5 s) and switches to the model once one is found. A body once dressed stays: new
   gear without a donor keeps the old gear on it until a donor shows up.
5. *No stored race or sex:* the portrait.

`GameGear.ModelKey` names the member, the route (not the donor unit) and the gear's `ts`: the model is
loaded again only when one of them changes. The earlier own-body file-ID check is gone: race and sex
are set explicitly. Without the template the page keeps the portrait.

Behind the model the race's dressing room art (game data): a race atlas if the client has one
(`dressingroom-background-<race>`), else the classic four tiles `Interface\DressUpFrame\DressUpBackground-<RaceFile>1..4`
(256×256, 64×256, 256×128, 64×128 over 320×384), else the class atlas `dressingroom-background-<class>`
(renders on Forever), else the dark fill. Scaled to fill the area with its shape kept, cropped, the
bottom edge shaded. `/guildy modeltest bg` prints which of them the client has.

**Upgrades aus der Gilde: which items guild members can make**

The chain is: member's book (spell IDs) → item the recipe makes → slot, item level, required level,
armour type → compare with the member's stored item. The middle link is the open question.

1. *Each client learns recipe→item from windows it opens*, like `recipeIcons`. True and cheap, but a
   client only knows the books it opened itself; relayed books stay blank. Alone, the box is empty
   for almost everybody.
2. *Each client asks the game per spell ID* (`C_TradeSkillUI.GetRecipeOutputItemData(spellID)`, already
   used as icon fallback) without any window. If Forever answers for recipes the player does not
   know, this alone covers every relayed book, with no sharing.
3. *A shared recipe→item map* (`CRAFT` message), filled from windows (1), from the game (2), and from
   the script's static recipe data; relayed so one client's knowledge serves the guild.
4. *A table shipped with the addon.* Rejected: breaks silently when Forever changes a recipe, and
   the professions design ruled out hard-coded recipe lists.

Picked: **2 with 1 underneath, and 3 only if 2 fails** (call). The builder runs
`/guildy craftprobe` first (§6). If the game resolves at least 95 % of the spell IDs in relayed books,
`CRAFT` is not built. Otherwise `CRAFT` is built exactly as in §6. Either way the local map
`GuildyDB.craftItems` exists and the script writes it.

**Enchantment text**

1. *Store the text.* Localized, so a German reading relayed to a French client shows German.
2. *Store the enchant ID, make the text per client* (picked): the tooltip of
   `item:<id>:<enchantID>` minus the tooltip of `item:<id>` leaves the enchant line. Cached per
   account and locale. The script may prefill that cache from `display_string` (its locale is the
   client's, `GuildyDB.clientLocale`).

## 6. Design

**Data.** A new pure module `Core/Gear.lua` (tested, like `Core/Cooldowns.lua`):

```
guild.gear[nameKey] = {
  ts  = epochSeconds,           -- when read (script: last login)
  src = "self" | "seen" | "relay" | "api",
  race = raceID | nil,          -- UnitRace's 3rd return; API race.id is the same number
  sex  = 2 | 3 | nil,           -- UnitSex values; API gender MALE/FEMALE -> 2/3
  items = { [slot] = { id, e, s, l, q } },   -- slot 1..19 incl. shirt 4 and tabard 19 (model only)
}                                -- e enchantID|0, s suffixID|0, l item level, q quality 0..5
```

`l` and `q` are stored although `GetItemInfo` could give them: the page draws bars and colours before
item info has loaded, and upgrades compare stored levels. **(call)** Merge rule: newer `ts` wins;
at equal `ts`, `self` over the rest. An incomplete read (a slot with an item ID but no link) is never
stored, the same rule `OnInspectReady` keeps today. Records of members who left the roster are
pruned (`Gear.Prune`, like `Cooldowns.Prune`). About 0.5 KB per member, so ~50 KB for 99 members.

`Gear.ENCHANTABLE` = back, chest, wrist, hands, feet, main hand, off hand when it is a weapon or
shield — the slots the mock marks orange. Head, legs and shoulders (arcanum, inscriptions) show an
enchantment when there is one, but are never flagged as missing. **(call)**

Per account, not per guild, because they are game facts:

- `GuildyDB.craftItems = { [spellID] = itemID }` — only recipes that make an equippable item
  (`GetItemInfoInstant` equip location not empty), capped at 3000. Recipes checked and found
  non-equippable are remembered for the session only.
- `GuildyDB.enchantText = { locale, names = { [enchantID] = text } }`, reset when the locale changes.

**Core/Upgrades.lua** (pure, tested): `Upgrades.For(member, gearRec, books, itemInfo)` returns at most
three rows `{ slot, itemID, have = l, offer = l, makers = { nameKey… } }`, sorted by gain. A candidate:

- comes from a recipe in some guild member's `ProfRec.recipes` (not the member's own),
- fits the slot (equip location), and its required level ≤ the member's level,
- is wearable by the class (armour subclass ≤ the class's best: cloth/leather/mail/plate; plate and
  mail from level 40 as in the game; a small class table, game facts),
- is not bind-on-pickup (`GetItemInfo` bind type 1) — the maker could not hand it over,
- beats the stored item level by at least 3. **(call)**

Weapons, off hands and ranged are left out of upgrades in this version: weapon skills, two-hand vs
one-hand and specs make "better" a guess. **(call)** Makers are ordered online first, then by last seen.

**Ready mark.** `Gear.ReadyMark(guild, level)` = the median average item level (`Stats.GEAR.ILVL`)
of roster members at the same level with gear known, needing at least 5 of them; else none, and the
header and the tick are left out. **(call — see open question 1)**

**Game side** (`Game/Gear.lua`):

- *Own gear:* read alongside `GameStats.ReadGear` from the same links on login and
  `PLAYER_EQUIPMENT_CHANGED` (the existing 5 s debounce), `src = "self"`, race/sex from `UnitRace`/`UnitSex`.
- *Others:* `ReadUnitGear` in `Game/Stats.lua` returns the per-slot links alongside the aggregates;
  `Finish` and `CheckLateGear` hand them to `Gear.Store(request, links, unit)`. No new inspect, no new
  timing. `src = "seen"`.
- Item strings are parsed `item:id:enchant:g1:g2:g3:g4:suffix`. Any link for which `ns.AnySecret` is
  true aborts the read (instances, combat); nothing secret is ever compared or stored.
- Nothing is stored while `ns.Anon.on`.
- `ScanOpen` (own and link-opened windows) also records spell → item: `GetTradeSkillItemLink(i)` for
  the legacy window, `GetCraftItemLink(i)` for the craft frame, `C_TradeSkillUI.GetRecipeOutputItemData`
  for the modern one. When the page shows upgrades, spell IDs without an entry are asked from the
  game (approach 2) in batches of 20 per frame; item info is requested with
  `C_Item.RequestLoadItemDataByID` and the page redraws on `GET_ITEM_INFO_RECEIVED` (debounced 0.5 s).

**Checks the builder runs first** (debug commands, removed or kept quiet after):

- `/guildy modeltest [raceID sex]` — opens a test `DressUpModel` and prints which of `SetUnit`,
  `SetCustomRace`, `Undress`, `TryOn`, `SetSheathed` exist, then dresses each race/sex with the own
  equipment. `modeltest scene <raceID>` tries the model scene route (target, else "player", with that
  race), `modeltest creature <displayID>` a creature display, `modeltest bg` lists the backgrounds the
  client has. Settled: no `SetCustomRace` on Forever; the model scene route works (see above).
- `/guildy craftprobe` — for up to 200 spell IDs from relayed books: how many
  `GetRecipeOutputItemData` resolves without a window, and how many `GetItemInfoInstant` reports as
  equippable. Settles whether `CRAFT` is built.
- `/guildy gearshow [name]` — the stored record slot by slot, with item info loaded or not, and the
  enchant text the tooltip diff produces (`C_TooltipInfo.GetHyperlink` if present, else a hidden
  `GameTooltip`). Settles the enchant-text path.

**Sync.** New message, new digest; `Protocol.VERSION` stays 1, older versions drop both silently.

- `GEAR {m = name, g = {ts, src, r, x, i = {"slot:id:e:s:l:q", …}}}` — one string per slot keeps the
  message at about 400 bytes. `Gear.Validate` rejects slots outside 1..19, non-integer fields,
  `ts` in the future.
- `SUM` gains `g = {nameKey = ts}` for records younger than 60 days, offered like statistics: whoever
  knows newer offers after a random delay (12–20 s, behind statistics), unless someone sent it first;
  at most `MAX_OFFERS`. Own gear only with `settings.share`. **(call)**
- *Only if craftprobe fails:* `CRAFT {c = {spellID, itemID, …}}` in messages of 400 pairs, `SUM` gains
  `k = {n = count, h = sum of spellIDs mod 2^31}`; on a difference, the side with more offers once per
  state and sender, like `JOIN`. Receivers take the union; an entry read in their own window wins a
  conflict.

**UI** (`UI/CharacterPage.lua`, variant A):

- *Left card:* model on top (drag to rotate, wheel to zoom — "Ziehen zum Drehen · Mausrad zum
  Zoomen"), level ring, name, title, race · gender · class, rank · zone · online, "Mitglied seit",
  notes, whisper/invite, officer bar as today. Without race known: today's race/class portrait in
  the model area, no hint text.
- *Right:* the four statistic tiles as today. Below, the gear list in `Stats.GEAR_SLOT_GROUPS` order:
  slot name, icon, item name in quality colour (suffix included once item info has it), the
  enchantment in green, or "keine Verzauberung" in orange for `Gear.ENCHANTABLE` slots; item level bar
  with the ready tick; level. Header: "Ø 47,4 · bereit ab 56 · 6 ohne Verzauberung" — each part only
  when known. Hovering a row shows the game's item tooltip of the stored item string. Below the list,
  in small grey: how old the reading is and its source ("vor 3 Tagen gesehen").
- *Right column:* family as a list (main and twinks with level and class), "Upgrades aus der Gilde"
  (slot, item in quality colour, "47 auf 58", maker with profession and online state; click on a maker
  whispers), professions as today. The dungeon collection goes. **(Sven allowed, call to drop)**
- *Empty states* (finished, never a broken look):
  gear unknown — slot names with "–" and one line "Noch nicht gesehen — Guildy liest die Ausrüstung,
  wenn jemand mit Guildy <Name> ins Ziel nimmt." (wording to polish);
  upgrades with no craft data — "Noch keine Rezepte der Gilde bekannt.";
  craft data but nothing better — "Nichts in der Gilde, das besser wäre.";
  no ready mark — no tick, no header part.
- *Smallest window (1130 × 560):* rows shrink to fit 17 slots (minimum 18 px), the level bar narrows
  first, enchant text truncates with "…" before the item name does.
- The member tooltip (`UI/Popups.lua`) gains nothing in this version. **(call)**

**The script** (`tools/bnet-sync`):

- `map.mjs` gains `gearRecord(equipment, profile, ts)` mirroring `Core/Gear.lua`: `slot.type` →
  slot number (`SLOT_IDS` exists), `item.id`, first `enchantments[].enchantment_id`, item level,
  quality, `src = "api"`, race from `profile.race.id`, gender from `profile.gender.type`. Written into
  `guild.gear[key]` only when newer than what is there. The equipment response is already fetched.
- Suffix IDs: written when the response carries them (field to find while building), else `0`.
- `GuildyDB.enchantText`: filled from `display_string` with the leading "Verzaubert: "-style prefix cut
  at the first ": ", only in the client's locale.
- `GuildyDB.craftItems`: for every recipe the bridge translates to exactly one spell ID, the
  `crafted_item.id` from the existing `recipe-items.json` cache, looked up for all recipes of guild
  books (not just unknown names). Guildy drops non-equippable entries on load.
- None of this is gated: gear, enchant text and craft items are fields the game fills too.

## Decided by Sven (2026-11-13)

All five questions settled as recommended:

1. The "bereit ab" ready mark is computed: the median average item level of members at the same
   level, only when at least 5 such members exist; otherwise no mark. An officer-set value may come
   later.
2. The upgrades box leaves out main hand, off hand and ranged in this version.
3. "keine Verzauberung" is flagged for back, chest, wrist, hands, feet, main hand, and off hand when it
   is a weapon or shield. Head, legs and shoulders show an enchantment when present but are never
   flagged as missing.
4. The dungeon collection is dropped from the character page completely.
5. Members who are not nearby stand in their race, sex and gear on a player of their sex (the
   model scene route above); their face and hair are not theirs unless they are nearby. The opposite
   sex of the viewer needs a player of that sex in sight; until then the race-icon portrait. Never the
   viewer's own body with someone else's race or sex.

## Added by Sven (2026-11-13): activity score on the character page

Sven wants the member's activity score (Core/Activity.lua, already shown as a column on the members
tab via `GameActivity.ScoreOf`) on the character page too, with a mouseover that shows how the score
is made up for this member.

- Show: the score 0–100 with its bucket colour/label (`Activity.Bucket`), as one more statistic tile or
  next to the tiles — placement decided in the plan against mock A at 1130 × 560. No score → the tile
  shows the finished empty state ("–"), never 0.
- Tooltip, built from data `ScorePlayer` already computes; today it keeps only `player.parts`, so it
  must also keep what the tooltip needs (pure change in Core/Activity.lua, unit-tested):
  - the three parts with their maxima: presence x/30, playing x/25, group play x/45;
  - what fed each part, per week: days online a week; kills, honorable kills, quests; raid bosses,
    dungeon bosses, dungeon runs, battlegrounds;
  - when presence is not counted yet (fewer than `MIN_COUNTED` days), a line saying the other two parts
    were scaled to 100;
  - when the score faded because the member has been away more than `FADE_FROM` days, the factor and
    the days away;
  - that the score is per player (main and twinks together), naming the characters counted when there
    are several, and the window it covers (from/to day).
- No new sync data: the score stays computed locally from what each client already has.

## 7. Open, to settle while building

- The three checks above: the model (settled 2026-11-13: model scene route, no `SetCustomRace`); whether
  `GetRecipeOutputItemData` answers without a window (decides `CRAFT`); the enchant-text path.
- Whether `GetTradeSkillItemLink` answers in a link-opened window of someone else (expected yes,
  as recipe links do).
- Which field of the profile API's equipment carries the random suffix, if any.
- The size of `SUM` with `g` added, measured with `/guildy sync` in a guild of ~100; if it crosses
  two parts more than before, shorten the age window from 60 days.
- The class armour table: verify Forever keeps mail/plate at level 40 before hard-coding it, or
  derive it from `IsSpellKnown` of the armour skills for the own class and from the item a member
  already wears.
- Layout at 1130 × 560 in German and Russian (longest slot and item names).
