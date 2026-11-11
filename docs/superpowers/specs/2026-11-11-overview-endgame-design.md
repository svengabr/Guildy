# Guildy — an endgame view for the overview tab, with an activity score

Date: 2026-11-11 · Author: Conoar (Sven) · Status: draft for approval

Marks used below: **(Sven)** is what the author decided, **(call)** is a choice made
while writing this document that he has not discussed and may overrule.

Picture of the result: `docs/mockups/overview-endgame.png` (drawn into a real
screenshot; all names and numbers in it are made up). It is the layout to build.
Where this text and the picture differ, the text wins; section 7 lists the
differences.

## 1. Intent

The overview tab is a census of the levelling phase: levels 1–60 stacked by class,
class × level bracket, professions. Once most of the guild is level 60 those boxes
stop saying anything. The tab gets a second view for that time, and a switch
between the two. **(Sven)**

The endgame view answers: how active is the guild, what did it do this month, how
well is it equipped, who comes and goes. Its centre is an activity score per
member, worked out from the game's statistics. **(Sven)**

Not everybody in the guild raids. The score must let a member who only runs
dungeons, or only plays PvP, or mostly plays alone, come out as active too.
**(Sven: "allgemeine Aktivität und Dungeon-, Raid-, PvP-Aktivität, alles gemeinsam
berechnet. Nicht alle bei uns raiden")**

Success: an officer opens the overview in the endgame and sees at a glance whether
the guild is getting more or less active, and can click through to the members
behind each number. The level-phase view is still there, unchanged, one click away.

## 2. Goals

1. A switch "Levelphase | Endgame" in the overview's toolbar, left of the time
   window. **(Sven)**
2. The choice is kept across reloads and logins. **(Sven)** While nobody has
   chosen, Guildy decides: endgame as soon as at least half of the members active
   in the last 30 days are level 60, level phase before that. **(call)**
3. The same choice in Guildy's options: "Overview shows: Automatic / Level phase /
   Endgame". **(Sven asked for an option; that it is the same stored value as the
   switch, and that there is an "Automatic", is a call)**
4. The endgame view has six boxes, three by two, as in the picture: **(Sven chose
   this layout, "D")**
   - Activity (score, section 4)
   - This month (section 5)
   - Item level of the level 60 members (section 6)
   - Last online — as today
   - Joins and departures — as today
   - Raids (section 6)
5. An activity score 0–100 per player (a main and its twinks together) from the
   game's statistics, and the guild's pulse as their average. **(Sven)**
6. Guildy counts on which days a member was seen online. **(call, needed for the
   score and for one row of "This month")**
7. All new texts in all six languages; the locale tests cover them.

## 3. Non-goals and anti-goals

- No line charts or other history graphs. **(Sven: not meaningful, did not like
  them)**
- No ranking of members inside the overview. The members behind a bar are reached
  by a click, in the members tab. **(call; Sven saw the ranking variant "E" and
  chose "D")**
- No heat map of online times, no class × gear matrix, no professions box in the
  endgame view. Professions stay on their own tab and in the level-phase view.
- The level-phase view does not change.
- No new message type on the addon channel, and no sharing of the days Guildy saw
  *other* members online. **(call, see 4.2)**
- Anti-goal: a score that looks exact where Guildy knows little. A member without
  a recent reading has no score — never a low one. **(call)**
- Anti-goal: a score only raiders can max out. **(Sven)**

## 4. The activity score

### 4.1 What it is built from

Per member, from the statistics record Guildy already keeps (`Core/Stats.lua`,
current values plus the first values seen in each month):

| Part | Statistics | Max |
|---|---|---|
| Presence | days seen online (4.2) | 30 |
| Playing | creatures killed (107), honorable kills (588), quests completed (98) | 25 |
| Group play | raid end bosses, dungeon end bosses, dungeons entered (932), battlegrounds played (839) | 45 |

Score = presence + playing + group play, rounded, 0–100. **(call: the split
55 general / 45 group. With it a player who logs in daily and plays alone reaches
"Active", and nobody reaches "Very active" without group play. Honorable kills
count as playing, like creature kills, so a pure PvP player is not short of that
part; battlegrounds are the PvP share of group play.)**

Group play is one pot of points, not three scores: every raid boss, dungeon boss,
dungeon run and battleground adds points to the same sum, and the
sum is bent by a saturating curve (`max * (1 - exp(-points / k))`), so a member
reaches the top of it by raiding, or by dungeons alone, or by PvP alone. Playing
uses the same kind of curve. Presence is linear and full at five days a week.
**(call)**

All inputs are rates per week over the reading window: from the first values of
the previous month where the record has them, else from the first values of this
month, up to the newest reading. **(call)** The window starts at that first
reading's own time and values — not at zero on the first of the month, as the
Hall of Fame does for the launch month — so the rates need no launch date.

The weights per event and the constants `k` are the builder's to set. Today's
saved data is from the launch month — levelling, hardly anybody at 60 — so the
constants cannot be fitted to it. They are set from three written-down example
players instead (each as weekly numbers, in the tests): one who logs in daily and
raids twice a week, one who logs in daily and only runs dungeons or only plays
battlegrounds several evenings a week — both must land above 75 — and one who
logs in twice a week and quests alone, who must land between 25 and 49.
**(call)** A slash command prints the distribution of the scores over the guild
(`/guildy activity` or similar), so Sven can look at real numbers now and again
once the guild is at 60; changing the constants then is a later release.
Sven's saved data for a first look: `tools/bnet-sync/out/Guildy.lua` or his
`SavedVariables\Guildy.lua` (neither is in the repository).

### 4.1a Per player, not per character

The score belongs to a player: a main with its twinks, as `Core/Family.lua`
groups them. A character with no known family is a player of its own.
**(Sven: "pro Spieler")**

- The weekly rates of all characters of a player are added up before the curves
  are applied; presence counts the days on which any of the characters was seen.
  **(call)**
- A player has a score when the character of theirs that was online most recently
  has a current reading (4.3). Characters of the same player without a current
  reading add nothing and do not take the score away. **(call)**
- The bars and "of n" count players. The click-through shows the members tab with
  twinks folded under their main, as it already does, the score on the main's row.
- Item level and raids (section 6) stay per character.

### 4.2 Days seen online

Guildy keeps, per member, the days on which it saw that member online: online in a
roster scan, or — from the roster's "last online" — the day that lies that far
back. About 60 days are kept. **(call)**

- For the player's own characters the count is exact, and it travels with the
  statistics record as one more Guildy-own value, so other Guildy users get it
  without a new message type. A cumulative "days played" counter fits that record:
  the month's growth falls out of the existing snapshots. **(call)** Its ID must
  lie above Blizzard's range but *below* `Stats.GEAR_BASE`: released versions
  treat every ID above that as equipment (`Stats.HasGear`, `Stats.CleanGear`) and
  would drop a member's known gear. Older versions lose the counter when they read
  that member nearby and relay the newer record, so merging and updating carry the
  highest counter forward (it only grows).
- For everybody else it is what this client observed. A member online only while
  the observer was away for days is undercounted; "last online" recovers the most
  recent day only. That is accepted. **(call)**
- The better of the two (own count received from the member, own observation) is
  used.
- Day counting starts with this version. Presence, and "days online per member" in
  section 5, are rated over the days actually counted so far (capped by the
  reading window), not over the whole window — otherwise every score would climb
  by itself for two months. Until a week of days is counted, a member's presence
  part is left out and the other parts are scaled up to 100. **(call)**

### 4.3 When a member has no score

A reading is current when it is at most 7 days old, **or** was taken at or after
the member's last logout (the roster's "last online"): nothing can have changed
since. So a member who stopped playing three weeks ago and was read on their last
evening has a real, low score and pulls the pulse down — that is the signal the
box exists for. **(call)**

So that this holds in numbers, a score falls off with the days since the player
was last online: unchanged for 3 days, then evenly down to 0 at 30 days. Without
it the saturating curves kept a player who quit at "Active" for four weeks.
**(call, from the final review)**

Days are local days that change at 5 in the morning, so an evening that runs past
midnight counts once. **(call, from the final review)**

No score — shown as "no current reading", counted in its own bar, left out of the
average — when the newest reading is not current, or the reading window is shorter
than 3 days, or there is no statistics record at all. **(call)**

### 4.4 The box

- Big number: the guild's pulse = average score of the members that have one.
  Under it: of how many members.
- Next to it the change against last month's pulse. Guildy stores the pulse it
  last computed in each month (per guild, a few months kept); with no value for
  last month there is no change shown. **(call)**
- Five bars: Very active 75–100, Active 50–74, Occasional 25–49, Hardly 0–24, No
  current reading. Colours as the "Last online" bars, the last one grey.
- A click on a bar opens the members tab filtered to those members, sorted by
  score, with the score visible per member. How that fits the members tab's
  columns and filter bar is the builder's.
- The time window of the toolbar does not apply to this box. **(call)**

## 5. This month

Six rows, guild totals of this month's growth (`Stats.Value(..., "month")`):
raid end bosses, dungeon end bosses, dungeons entered, quests completed, honorable
kills, and days online per member (average, from 4.2).

Each row: value, a bar, and a white mark for last month. A month that is ten days
old against a full last month would always look worse, so the mark and the
difference compare against last month's total scaled to the share of the month
that has passed (day 10 of 30: a third of last month). **(call — the picture's
hint says only "Strich: Vormonat"; the text should say what is compared)**

Members whose record has no start value for a month are left out of that month's
sum, as the Hall of Fame does.

## 6. Item level, raids

**Item level.** The level histogram's twin: one column per whole item level,
stacked by class, for level 60 members with an equipment reading who are active in
the toolbar's time window. Axis from the lowest to the highest level present,
ticks every five. A click on a column filters the members tab. A thin gold line
marks where the raid roster starts ("Raidkader ab 56"); the threshold is one
constant, 56 for now. **(call: the value. It is a guess about Forever's raid loot
and Sven should confirm or change it)**

**Raids.** One block per raid in `Stats.ALL_DUNGEONS` (`raid = true`), name and
icon as the Hall of Fame shows them:
- a bar and "n / m": members with at least one end boss kill, of the level 60
  members with a statistics reading;
- "new: +n": members whose first kill falls in this month;
- one line of names, in class colours, cut off with "+n": members who are raid
  ready — level 60, online within 7 days, item level at or above the threshold —
  and have no kill yet. A click on the block filters the members tab to the
  members with a kill.

The picture's "Siege diesen Monat" is dropped: the statistics count kills per
member, not raid evenings, and a sum over members would be a number nobody can
read. **(call)**

## 7. Where the picture is not the specification

- Raid names "Hügelgruft" and "Hyjal" are placeholders; the game supplies them.
- "Siege diesen Monat" in the raids box goes (section 6).
- The activity box's hint says "30 Tage"; the window is as in 4.1, and the hint
  should not claim a number of days.
- All numbers and names are invented and need not be reproduced.

## 8. Constraints

- WoW Forever client, Lua, no libraries beyond those bundled.
- Logic in `Core/` as pure functions with tests (`tests/`), game access in
  `Game/`, drawing in `UI/` — as the rest of the addon.
- The smallest window (1130 × 560) must hold all six boxes without cut-off text in
  all six languages. The screenshot runs (`/guildy shots`, `/guildy shots all`)
  get the endgame view as one more picture, and that run is the check.
- Screenshot mode (`Core/Anon.lua`): made-up names as everywhere else; nothing new
  may be stored while it is on.
- Saved data from older versions loads without loss; older Guildy versions that
  receive a record with the new value keep it, as they keep unknown IDs today.
- Settings: the switch's choice lives in `GuildyDB.settings` next to
  `activityDays`; unset means automatic.

## 9. Left to the builder

- File and function names, where the score lives (`Core/Activity.lua` or inside
  `Core/Census.lua`), how the two views share `UI/TabOverview.lua`.
- The exact weights and curve constants (within 4.1's target and calibration).
- Box proportions and row pitches at each window size.
- How the members tab shows and sorts by the score (4.4).
- Wording of the new texts in the six languages, in the tone of the existing ones.
