# Guildy — specializations, profession cooldowns and better recipe coverage

Date: 2026-11-13 · Author: Conoar (Sven) · Status: approved 2026-11-13

Marks: **(Sven)** is what the author decided, **(call)** is a choice made while writing
this document that he has not discussed and may overrule.

## 1. Intent

Three additions to the professions tab, asked for by a guild member and by Sven:

- Show each member's **profession specialization** (Goblin engineer, armorsmith, …). **(Sven)**
- Show **profession cooldowns** (Arcanite transmute, Mooncloth, Salt Shaker). **(Sven)**
- Get **recipe books of more members**, because the layer system limits in-game reading
  to one or two members per session. **(Sven)**

This is the next larger version. Rebuilding the character page is **not** part of it. **(Sven)**

## 2. The constraint that shapes everything

Guildy has about 5000 installations. **(Sven)** An addon cannot ask a web API, and almost
nobody runs the `tools/bnet-sync` script. So:

> Every field the script fills must also be fillable inside the game.
> The script only fills it faster. **(Sven)**

Whatever one member gathers — in the game or through the script — spreads to the other
Guildy users in that guild over the existing sync. That is what makes a single well-equipped
client useful to a whole guild, and it needs no new mechanism.

## 3. What was established before writing this

Measured on 2026-11-13 against Forever's own Wowhead database, the live profile API and
Sven's saved data (99 members).

- **Forever has specializations in three professions only.** Engineering (Gnomish `20219`,
  Goblin `20222`), blacksmithing (Weaponsmith `9787`, Armorsmith `9788`, Master Swordsmith
  `17039`, Master Hammersmith `17040`, Master Axesmith `17041`), leatherworking (Dragonscale
  `10656`, Elemental `10658`, Tribal `10660`). The Burning Crusade alchemy and tailoring
  specializations do **not** exist there; their spell IDs resolve to nothing.
- **Cooldown crafts:** Arcanite `17187`, Iron to Gold `11479`, Mithril to Truesilver `11480`,
  the eight elemental transmutes `17559`–`17566`, Mooncloth `18560`, Salt Shaker (item `15846`,
  spell `19566`), and Forever's own Transmute: Legionite `1317279`. Forever shortens the
  classic durations, so no duration is hard-coded anywhere.
- **Recipe coverage today:** 37 books for about 337 known member professions. Leatherworking
  4 of 23, tailoring 4 of 20.
- **Specializations can be read in the game**: `IsSpellKnown` works on this client.
- **Specializations can be inferred from a recipe book**: Au Tsch's harvested engineering book
  holds three Goblin-only recipes. Forever has dropped the specialization requirement from some
  blacksmithing recipes (Lionheart Helm now wants a Master Forge), so marker recipes are
  trustworthy for engineering and must be verified before being used elsewhere.
- **The profile API knows the specialization outright** (`specialization: { name }`) and returns
  complete recipe lists. It numbers recipes differently from the game, and the bridge between
  the two is the recipe name.

## 4. Goals, non-goals

- Everything works with the game alone, in every guild, without the script. **(Sven)**
- A member who does not use Guildy still gets a specialization where their book shows it. **(call)**
- Cooldowns of other members are only ever what Guildy users share — nobody can read them
  otherwise, and the window must say so rather than imply "no cooldown". **(call)**
- No duration, no recipe list and no specialization name is hard-coded in a way that breaks when
  Forever changes it. **(call)**
- Not built: alchemy and tailoring specializations (they do not exist here), a cooldown alarm,
  reagent tracking, the character page rebuild.
- Nothing is copied from ProfessionMaster: it is "All Rights Reserved", Guildy is GPL-3.0. The
  IDs above come from Forever's database and from Sven's own data, which are game facts. **(call)**

## 5. Approaches considered

**Specializations**

1. *Own character only, shared between Guildy users.* Simple, but a guild of mostly
   non-Guildy members stays empty.
2. *Inferred from recipe books only.* Covers everyone with a book, but says nothing about the
   80 % without one, and is unreliable outside engineering.
3. *Both, with the clearer source winning* (picked). `IsSpellKnown` for the player's own
   characters, inference for everyone whose book was read, shared like any other data.

**Cooldowns**

1. *Read at the open profession window* (`GetTradeSkillCooldown`), the way ProfessionMaster does.
2. *Read from the spell itself* (`GetSpellCooldown`) (picked, with 1 as fallback). It needs no open
   window, so the display is right at any moment. Which of the two the client answers is verified
   in the game before the UI is built.

**Recipe coverage**

1. *Scan harder in the game.* The layer limit is a wall; nothing to win.
2. *Second data world from the API, stored as names.* Covers everyone, but splits the data model
   in two and only ever helps the one guild whose officer runs the script.
3. *The script writes the same fields as the game* (picked). It translates the API's recipe IDs
   to spell IDs itself, using a name bridge built once from Forever's database and kept inside
   `tools/`. Guildy stores what it always stored, and the sync carries it to the guild.

## 6. Design

**Data.** `ProfRec` (`Core/Professions.lua`) gains one field:

- `spec` = the specialization's spell ID, with `specSrc` saying how it was learned
  (`"known"` from `IsSpellKnown`, `"book"` inferred, `"api"` from the script). A clearer source
  replaces a weaker one; among equals the newer timestamp wins. **(call)**

Cooldowns live apart from the profession records, because they belong to a character and not to a
profession's skill: `guild.cooldowns[nameKey] = { [spellID] = readyAt }`, `readyAt` an absolute
server time, `0` meaning ready. An entry older than seven days is dropped on read. **(call)**

**Core/Specs.lua** (pure, tested): the eleven spells per skill line, the marker recipes per
specialization, `Specs.FromBook(skillLine, recipes)`, and the merge rule above.

**Core/Cooldowns.lua** (pure, tested): the seed list of cooldown spells, `Cooldowns.Note`,
`Cooldowns.Merge`, digest and wire format, and the text ("ready", "in 14 h").

The seed list is a starting point, not the truth: every recipe Guildy ever sees with a cooldown is
remembered per guild, so Forever's own crafts arrive by themselves. **(call)**

**Game side.** Own specializations are read after login and whenever the skill list changes.
Own cooldowns are read on login, on `SPELL_UPDATE_COOLDOWN` and `BAG_UPDATE_COOLDOWN` (debounced),
and after each craft. Books that Harvest reads are run through `Specs.FromBook`.

**Sync.** `PROF` carries `spec` and `specSrc` alongside the rank. Cooldowns get their own message
`CD` and a digest in `SUM`, offered the way the bank is: whoever knows more offers, after a random
delay, unless someone else was faster. Older Guildy versions send neither and are not offered any.

**UI.** The professions tab shows the specialization as a short tag in the member row and as a
filter in the rail; the member list gains a cooldown cell showing the nearest one. The member
tooltip and the character page name both. Where nothing is known, the window says "not known"
rather than leaving an empty cell that reads as "nothing on cooldown". **(call)**

**The script** (`tools/bnet-sync`) writes `spec` as a spell ID — matching the API's localized name
against the spell names the game reports — and recipe lists as spell IDs through the name bridge.
It asks the API in the client's language, which Guildy records in `GuildyDB.clientLocale`. **(call)**

## 6a. The guild has not got there yet

Measured on 2026-11-13 over all 99 members: exactly **one** has a specialization at all
(Au Tsch, Goblin engineer, engineering 264). Three leatherworkers sit at 225 and could take one;
no blacksmith is above 200. The guild is still levelling, and a specialization is endgame. **(Sven)**

Two consequences, both deliberate:

- **The empty state is the normal case**, not the exception. A profession nobody has specialized
  in must look finished and quiet, never like a broken feature. The same holds for cooldowns while
  no Guildy user shares any. **(call)**
- **Marker recipes for blacksmithing and leatherworking cannot be derived from live data yet** —
  one specialized member is no sample. Engineering markers are safe because Forever's database
  names the requirement per recipe. The other two wait until the guild gets there. **(Sven)**

## 6b. Decided after review (all **(Sven)**, 2026-11-13)

1. **Who may change a specialization.** Only the game itself (`IsSpellKnown` on the player's own
   character) and the script may replace or revoke one. A recipe book only ever adds: a missing
   marker recipe proves nothing.
2. **Cooldowns are personal data** and go under the existing "share my data" switch, no new option.
   Only the logged-in character can be read; the player's other characters show the state of
   their last login.
3. **Cooldowns are relayed** like everything else, through a digest in `SUM` (offer only when
   someone knows more), so the sending budget holds.
4. **New cooldown recipes are learned from own observation only**: the player's own profession
   window and own spells. Nobody can see cooldowns in someone else's book.
5. **No new columns.** The specialization is a short tag after the member's name (like "Twink" on
   the members tab). Cooldowns go into the right-hand panel that shows the selected member's
   profession. The rail's tooltip lists who has which specialization; with nobody specialized it
   shows nothing extra.

Settled by the code: older Guildy versions drop unknown fields and message types silently as long
as `Protocol.VERSION` stays 1; unlearning a profession drops its record and the specialization
with it. `Professions.Merge` rebuilds the record on every update, so it must carry `spec` over.

## 7. Open, to settle while building

- Which of `GetSpellCooldown` and `GetTradeSkillCooldown` this client answers.
- Marker recipes for blacksmithing and leatherworking stay unbuilt for now (see 6a). Those two
  professions rely on `IsSpellKnown` and sharing until the guild has specialists to learn from.
  The script's data is the ground truth to derive them from later, one specialist at a time.
