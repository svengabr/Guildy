# Guildy — design

Date: 2026-11-05 · Author: Conoar (Sven) · Status: draft for approval

## 1. Intent

Guildy replaces the default "Guild & Communities" window in WoW Forever with a
Blizzard-styled window that shows more about the guild: who is online, the class,
level and profession make-up of the *active* guild ("census"), and who can craft
what — down to individual recipes.

Why: the default window shows a chat, a plain roster and little else. The guild
(Murloc Mafia, ~55 members, growing fast, mostly levels 10–25) organises dungeon
groups and crafting in guild chat ("Heiler für Ruins of Lordaeron?", "wer kann mir X
craften?"). Answering those questions today means scrolling the roster or asking
around. Existing addons that do this look dated; the author wants a modern but
native-looking window.

Success: pressing J opens Guildy instead of the default window, the guild chat is
right there, and the author (an officer) can see who is online and invite people
faster than before. Census and recipe search answer "who/how many" questions without
asking in chat.

## 2. Goals

1. Fully replace the guild part of the default window. J (TOGGLEGUILDTAB) and every
   other path that opens the guild window open Guildy.
2. Always open on the **Chat** tab.
3. Keep every guild feature the default window has (chat, roster, notes, ranks,
   invite/remove, MOTD, guild info, news, log, guild settings). Nothing an officer can
   do today may be lost.
4. Census of active members, filterable by activity window.
5. Professions and recipes per member, searchable.
6. Share profession data between Guildy users in the guild automatically.

## 3. Non-goals (for now)

- Communities other than the guild. The author uses none. Guildy keeps a small
  "Communities" button that opens the default Blizzard window, so nothing is lost.
- Guild bank, calendar, recruitment ads, DKP/loot (Raidy covers raids).
- Website or Discord sync.
- Other game flavours. Forever only (`## Interface: 16001`), like Raidy and KeepOrSell.

## 4. Anti-goals (would make it a failure even if it works)

- **Invasive.** Guildy must not touch other frames, chat frames, nameplates, or spam
  the user. No popups on login. No chat output except on errors or slash commands.
- **Off-brand look.** No flat "web app" styling. It must look like a Blizzard window
  (gold frame, portrait, parchment/dark insets, red panel buttons, bottom tabs) —
  the same family as Raidy and KeepOrSell.
- **Lag or disconnects** from addon-channel traffic.
- **Losing default functionality**, especially officer actions.
- **Taint** that breaks protected actions (e.g. group invite in combat, other
  addons' secure buttons).

## 5. The window

Agreed layout (mockup "chat-v3", option A).

- Base: `ButtonFrameTemplate` with the Guildy portrait, title = guild name, Esc
  closes it (`UISpecialFrames`), movable, position saved.
- Default size about 1000 × 500 (default window is ~830 × 450). **Resizable** with a
  grip in the bottom-right corner; size is saved. A sensible minimum size keeps all
  three chat-tab columns usable.
- **Left: narrow icon bar** (~40 px). Guild icon (selected), a "Communities" icon that
  opens the Blizzard window, tooltips carry the names.
- **Bottom tabs** (Raidy style): Chat · Members · Overview · Professions · Info & Log.
  Guildy remembers nothing about the last tab: J always opens on Chat.

### 5.1 Chat tab (default)

- Centre: channel dropdown (Guild, Officer — officer only if the player can read it),
  the message history, an input line. Chat text slightly larger than default.
  Names in class colour. Join/leave events as a grey system line.
  History must show what was said before the window was opened (at least the
  session's guild chat; whatever the default guild window shows today).
- Right: **online list**, always visible (~240 px): level, name in class colour,
  profession icons, zone; sorted by level by default. Header "35 / 55 online".
  - Hover: tooltip with rank, public note, professions with skill, last online.
  - Left-click: whisper. Right-click: the usual player menu (whisper, group invite,
    notes / rank for officers).
- Below the list: **"Invite member"** (only if the player may invite). Opens a small
  input box. It is pre-filled with the current target's name when the target is an
  unguilded player, and offers the last few people who whispered the player as
  one-click suggestions ("inv pls" use case).

### 5.2 Members tab

Replacement of the default roster ("mockup B" list).

- Search box (name, zone, note), filter chips (class, level range, profession,
  online only / show offline), sort by any column.
- Columns: level, class, name, zone, rank, professions (icons + skill), last online,
  public note.
- Selecting a row opens a **details panel on the right** (not a separate window):
  level/class/zone/rank, last online, public note, officer note (editable when
  allowed), rank dropdown, remove, group invite, whisper, professions + recipe count.
- Every officer action the default roster offers stays available, gated by the
  player's guild permissions.

### 5.3 Overview tab (census)

- Activity selector: "Active in the last **1 month** / 3 months / 6 months / All".
  Default 1 month; the choice is saved.
- A member counts as active if they are online now or their roster "last online"
  is within the window.
- Side box: active count of total ("41 active of 55"), average level, joined in the
  last 30 days (from the guild event log where available), professions known
  ("33 / 41").
- Panels: class distribution (bars in class colours), level histogram (brackets of
  10: 1–9 … 50–60), profession distribution (bars). Clicking a class, bracket or
  profession jumps to the Members tab with that filter applied.

### 5.4 Professions tab

- Search box at the top: type a recipe or item name, get the members who know it,
  with online status; click to whisper. Item links can be pasted / shift-clicked in.
- Below: list grouped by profession, members with skill / max skill, "data as of"
  date, source (own scan, Guildy sync, chat link).

### 5.5 Info & Log tab

MOTD (editable when allowed), guild info text (editable when allowed), guild news,
the guild event log, and the guild settings currently on their own page (preferred
language / region, GM only — `C_GuildInfo.Get/SetPreferredPlaySettings`).

## 6. Data

### 6.1 Roster

From the guild roster API (`C_GuildInfo.GuildRoster()` to request,
`GUILD_ROSTER_UPDATE`, `GetGuildRosterInfo`, `GetGuildRosterLastOnline`, etc.).
Must be verified against Forever (see §9).

### 6.2 Professions and recipes — sources, in priority order

1. **Own characters**: when the player opens a profession window, Guildy reads
   profession, skill / max skill and the full known-recipe list. Works for all of
   the player's alts.
2. **Guildy sync**: Guildy users broadcast their own data on the guild addon channel
   when it changes, and newcomers / players coming online fetch missing or newer
   data from an online member. Data is versioned per member + profession (scan
   timestamp) so only newer data replaces older data.
3. **Chat links**: when anyone posts a profession / trade-skill link in a channel
   Guildy sees, record at least profession + skill for that member; recipes too if
   the link carries them (verify in Forever).
4. **Blizzard guild professions**: `C_GuildInfo.QueryGuildMemberRecipes`,
   `QueryGuildMembersForRecipe`, `C_TradeSkillUI.IsGuildTradeSkillsEnabled` exist in
   the Forever API docs. Use them if they work in Forever; otherwise ignore.

Sharing own data is **on by default** and can be switched off in settings.

### 6.3 Storage

- One account-wide SavedVariable `GuildyDB` (convention of the author's addons).
- Data keyed per guild (guild name + realm/region) then per member (full Forever
  name "First Last").
- Every profession record carries a timestamp and source; the UI shows its age.
- Members who left the guild drop out of search and census. Whether their data is
  deleted or kept hidden is left to the builder.
- Storage must stay bounded (recipes of ~50–100 members × 2 professions).

### 6.4 Addon-to-addon protocol

Follow Raidy's pattern: own prefix, versioned envelope, compressed + encoded for the
addon channel, chunking, a token-bucket send throttle, per-sender receive limits,
graceful "newer version" handling. Channel: GUILD. Only accept data a sender
publishes about **their own** characters (no relaying of third-party data), unless
the builder finds a safe way to relay.

## 7. Look and feel

- Same visual family as Raidy / KeepOrSell: `ButtonFrameTemplate`, gold borders,
  Morpheus/quest-title headings, `UIPanelButtonTemplate` red buttons,
  `PanelTabButtonTemplate` bottom tabs, dark insets with the tooltip border.
- Class colours from `RAID_CLASS_COLORS`; real profession icons.
- Reuse / copy the widget helpers from Raidy `UI/Widgets.lua` (itself copied from
  KeepOrSell `UI/Style.lua`).
- Mockups (HTML, for reference only): `richtungen.html`, `fenster-v2.html`,
  `chat-v3.html` (option A chosen) — to be copied into `docs/mockups/`.

## 8. Project and tooling (decided)

- Repo `C:\_dev\workspace\Guildy`, git, installed with a directory junction into
  `C:\Spiele\World of Warcraft\_forever_\Interface\AddOns\Guildy`.
- Conventions copied from KeepOrSell / Raidy:
  - `local addonName, ns = ...` namespace, modules on `ns`, Init with an event
    handler table.
  - TOC: `## Interface: 16001`, `## Author: Conoar`, `@debug@` version block,
    SavedVariables `GuildyDB`, load order libs → locales → pure core → game → UI →
    init.
  - Locales: English base, German override; all player-facing strings in locales.
  - English in code, comments, commits and docs.
  - Pure logic separated from frames and unit-tested (census maths, activity
    filter, sync merge rules, protocol encode/decode, recipe index/search).
  - luacheck, CHANGELOG.md, .pkgmeta (BigWigs packager), README doubles as the
    CurseForge description. CurseForge slug `guildy` (checked free on 2026-11-05;
    reserve early).
  - Conventional commits.

## 9. Open technical questions (builder must verify in-game early)

1. How the default window is opened in Forever (ToggleGuildFrame,
   CommunitiesFrame, keybinding TOGGLEGUILDTAB) and the least-taint way to redirect
   all of them to Guildy.
2. Which roster API set works in Forever (global `GetGuildRosterInfo` family vs.
   `C_GuildInfo` / `C_Club`), incl. last-online and rank permissions.
3. How guild chat history can be read for the chat tab (C_Club message history vs.
   capturing CHAT_MSG_GUILD from login).
4. Whether profession links in chat carry recipe data in Forever.
5. Whether Blizzard's guild-profession APIs (§6.2 point 4) return data.

A short spike that answers 1–5 should come before the bulk of the UI work.

## 9a. Decisions after the builder check (author's calls, author asked to build straight through)

1. **Opening path.** Override the global `ToggleGuildFrame` (used by the TOGGLEGUILDTAB
   binding and the guild micro button) and, as a safety net, hook `CommunitiesFrame`'s
   `OnShow`: if it shows the guild club and Guildy did not ask for it, hide it and show
   Guildy. If the in-game test shows taint from this, fall back to "J opens Guildy, other
   paths may still reach the Blizzard window".
2. **Scope of officer UI.** Guildy covers: invite to guild, remove, promote / demote / set
   rank, public and officer notes, MOTD, guild info, preferred play settings. The rank
   editor (rename / add / remove ranks, permissions) stays in Blizzard's UI: a
   "Guild control" button opens it (`GuildControlUI`), and the Communities icon opens
   the full Blizzard window.
3. **First test version** contains all five tabs and the sync; internally built in the
   order window+chat → members → overview → professions → sync.
4. **Relay is allowed.** Any Guildy user may forward the newest record they know about
   any member, so newcomers see offline crafters. Records are versioned by scan
   timestamp; newer wins. A record sent by the member themselves is marked `self`
   and is never replaced by a relayed record with the same or an older timestamp.
   Nobody accepts relayed records about their own characters.
5. **Alts** are separate members in census and lists (no main grouping in v1).
6. **"Invite member" is a guild invite** (shown only with invite permission). The
   whisper suggestions are for people asking for a guild invite. Group invite lives in
   the row menu.
7. Mockups are in `docs/mockups/` (`chat-v3.html` option A is binding for the Chat
   tab; the Overview layout follows `fenster-v2.html`; Members follows the list in
   `richtungen.html` option B with the details panel added).

## 10. Left to the builder

Internal module split, exact sizes and spacing, sort defaults beyond those named
here, sync scheduling details, how long cached data of departed members is kept,
slash commands (at least `/guildy` to open), minimap / addon compartment button
(optional, off by default is fine), test harness choice (KeepOrSell Python + lupa or
Raidy LuaJIT).
