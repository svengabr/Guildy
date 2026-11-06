# Changelog

## 0.2.1

See who else uses Guildy, and more reliable statistics.

- Members tab shows which online members use Guildy and which version (green: same or newer, orange:
  older, "old": a Guildy before this version). Guildy users say hello on login.
- "online" is shown in green in the members list and tooltip.
- Statistics: answers that arrive in parts are read twice, and an answer without creature kills
  (level 10 and up) counts as incomplete and is asked again later instead of being stored.
- Optional: read statistics of guild members under the mouse (`/guildy statmouse`, off by default;
  switched off again automatically if a session ends during such a request).
- `/guildy statshow <name>` lists what Guildy knows about one member's statistics (for bug reports).
- Fix: reading the message of the day no longer triggers a blocked-action error on Forever.

## 0.2.0

Guild management without Blizzard's window, a Hall of Fame and a richer overview.

- Promote, demote and remove members right in Guildy (member details and member menu), with a
  confirmation before removing.
- Message of the day and guild info are edited in the Info tab, in Blizzard's own edit box shown
  inside Guildy. Preferred language and region of the guild are there too (guild master can change them).
- New Ranks tab: every rank with its permissions and members. The guild master edits ranks and
  permissions there in Blizzard's rank editor, opened right inside the tab.
- Only notes still open Blizzard's guild window (Forever saves notes only from Blizzard's own list).
- New Hall of Fame tab: guild totals, title cards (Slayer, Quest machine, Hogger's favourite, ...) and
  dungeon progress from Forever's character statistics, for all time, this month or last month; a click
  opens the guild ranking of any statistic. Guildy reads your own statistics and those of guild members
  you target nearby; Guildy users share theirs. Every statistic is kept for later features.
- Overview grows with the window: levels 1-60 stacked by class, highest known skill per profession,
  last-online activity, joins and departures of the last 30 days, and a class x level matrix. Clicks
  filter the members tab.
- Window minimum size 960 x 560.

## 0.1.0

First version.

- Replaces the default guild window: J opens Guildy, always on the guild chat (temporary key binding, Blizzard's
  code stays untouched).
- Chat with history, officer chat, join/leave lines and an online list with level, class colour, professions and zone.
- Members tab: search, filters (class, level, profession, online), sortable columns, details panel.
- Overview tab: census of the members active in the last 1 / 3 / 6 months or all, with class, level and profession
  bars; a click filters the members tab.
- Professions tab: recipe search, members per profession with skill, expandable recipe lists, Blizzard's recipe
  book from the menu.
- Profession data from your own windows, from other Guildy users (guild addon channel), from clicked profession
  links, from guild notes and from "Read online members".
- Invite member opens Blizzard's invite dialog with the target filled in and recent whisperers as suggestions;
  rank, notes and removal go through Blizzard's guild window (Forever reserves them for Blizzard's interface).
- Info & Log tab: message of the day, guild info, guild log, sharing switch.
- Guild emblem in the portrait, side tab in the style of Blizzard's profession window.
