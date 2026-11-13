# Guildy — a banner when a guild member reaches level 60

Date: 2026-11-13 · Author: Conoar (Sven) · Status: approved 2026-11-13, built

Marks used below: **(Sven)** is what the author decided, **(call)** is a choice made
while writing this document that he has not discussed and may overrule.

## 1. Intent

When someone in the guild reaches level 60, every Guildy user sees a big
announcement on their own screen: a banner. **(Sven)** Guildy also says it once in
guild chat, sent by the first Guildy user who notices, not by every one of them.
**(Sven)**

## 2. Goals, non-goals

- Any guild member counts, whether or not they run Guildy. **(call)**
- The player's own level 60 is announced too. **(call)**
- Only what happens while the player is logged in is announced. Who reached 60
  while the player was offline gets no banner at the next login. **(call)**
- Not built: banners for other levels, a list of past level 60s, a new message
  kind on the addon channel.

## 3. Approaches

1. **Compare the roster with the scan before** (picked). Guildy already reads
   every member's level on each roster scan (`Game/Roster.lua`). A member whose
   level was below 60 in the scan before and is 60 now has just made it. Works
   for everybody, needs no message between clients.
2. **Guildy users tell each other** over the addon channel. Immediate, but only
   for members who run Guildy, and one more message kind in the protocol.
3. **Read the game's chat** for a level-up line. The game sends none for guild
   members.

Approach 1 has one catch: today Guildy asks the game for the roster only at login
and when its window opens. With the window closed, a level 60 would go unnoticed
for a long time. So Guildy asks for the roster every 30 seconds while the player is
in a guild. **(call)** A scan cost about 10 ms with 98 members (measured
2026-11-10, comment in `Game/Roster.lua`); what the listeners of "ROSTER" add with
the window closed is measured with `/guildy perf` before this ships, and if it is
too much the 30 seconds grow.

## 4. Design

**Finding it — `Core/Ding.lua` (pure).** `Ding.Find(before, members)` takes the
levels of the scan before (`{ [key] = level }`, nil on the first scan) and the
roster, and returns the members who went from 59 to 60 plus the new levels
table. A jump over several levels is a roster that was wrong for a moment, not a
level 60 (changed after review: a false banner is worse than a missed one). A
member is announced once a session. Nothing is found on the first scan of a session, for a member who was not
in the scan before (someone who joins at 60), or after a change of guild.

**Game side — `Game/Ding.lua`.** Listens to "ROSTER", keeps the levels table for
the session (per guild; nothing is saved), and for each member found shows the
banner and takes care of the line in guild chat, each when its option is on. It
also starts the 30-second roster request. On `PLAYER_LEVEL_UP` to 60 the own
character is announced at once, without waiting for the roster. The 30-second
request asks for the roster only, not for the guild event log.

**The line in guild chat, once.** The text is "[Guildy] Name has reached level
60!" in the language of whoever sends it. Who sends it:

- Every client that finds the level 60 waits a short random time (up to 3
  seconds) before it posts. **(call)**
- Every client reads guild chat. A line that starts with "[Guildy]" and holds the
  name of a member who is level 60 means: said already. A client that has seen it
  does not post, whether it found the level 60 before or after that line.
- The clients ask for the roster at different moments, so one of them finds it
  first and the others see its line long before their own turn. The random wait
  is for two that find it in the same second. Two lines are still possible when
  both post within the fraction of a second a chat line travels; rare, and
  harmless.
- The member who reached 60, when they run Guildy, knows at once and so is
  usually the one who posts. **(call)**

No message between clients is needed for this: guild chat itself is the signal,
and it also works with Guildy users on an older version (they neither post nor
get in the way).

**Not checked yet:** whether Forever lets an addon send to guild chat from a timer,
without a key press. Guildy's own chat line sends after Enter, which proves
nothing for this. The send is wrapped so a refusal breaks nothing, and it is
tried in game first; if the game refuses, this part is dropped and the banner
stays.

**Banner — `UI/Ding.lua`.** One frame in the upper middle of the screen, not part
of Guildy's window and shown whether or not that is open:

```
        ─────────────────────  ◆60◆  ─────────────────────
                         Makira Farron        <- large, in the class colour
                  has reached the highest level
             ──────────────────────────────────────────
```

A dark band that runs out to both sides, two gold hairlines, and on the upper one
a seal with the level (a square on its corner). Changed after the first look in
game: three bare lines of text had no hold on the scenery. **(Sven)** The seal
drops in, the lines run outward, name and text rise into place; it stays about 5
seconds and fades out, with the game's own level-up sound. Several at once are shown one after the other. It does not take the mouse
and is not shown in combat lockdown-sensitive ways (a plain, unprotected frame).

**Options.** Two check boxes under General in the options, both on by default and
part of "Reset all customizations": "Banner when someone reaches level 60"
(`settings.ding60`, banner and sound) and "Say it in guild chat"
(`settings.ding60Post`). **(call)** With the second one off this client never
posts; others still may.

**Trying it.** `/guildy ding` shows the banner for the own character, for looking
at it and for pictures. It posts nothing.

**Texts** in all six languages (`Locales/*.lua`).

## 5. Tests

- `tests/test_ding.lua`: first scan, 59 to 60, a jump from lower (not found), already 60, new
  member at 60, member gone, broken levels.
- `tests/test_ding.lua` also: which guild chat lines count as "said already".
- `tests/test_dingflow.lua`: a roster whose member goes to 60 between two scans shows the
  banner and, after the wait, sends one line to guild chat; a "[Guildy]" line
  with the name arriving first means nothing is sent; each option off stops its
  part.

## 6. Left to the builder

Exact fonts, sizes, timings and the sound id; they are checked in game.
