# Changelog

## 1.8.0

- New: member since. Guildy remembers when each member joined the guild and shows it in the member
  tooltip and on the character page. The member list has a new column for it, sortable, so the members
  who are longest in the guild stand on top: add it with "Customize" and the + at the headings.
- The game itself keeps no join date. Guildy reads it from the guild's event log, which only reaches
  back about a hundred events, and Guildy users share what they know with each other. For a member who
  joined before anyone could read it, Guildy counts from the day it first saw them and marks the time
  with a +: in the guild at least that long.
- Fixed: on the Professions tab a skill like 278/300 broke into two lines.

## 1.7.1

- New: a banner when a guild member reaches level 60. A dark band across the upper middle of the screen
  with a gold seal showing the 60, under it the name, large and in the class colour, with the game's
  level-up sound, whether or not Guildy's window is open. It works for every member, with or without
  Guildy. `/guildy ding` shows it for your own character.
- Guildy also says it in guild chat, once: of all Guildy users online only the one who notices first
  sends the line.
- Both can be switched off under Options, General.
- For this Guildy asks the game for the guild roster every 30 seconds, so the tabs are also more up to
  date than before.
- Fixed: the bank's ledger lists only the days chosen in the toolbar.

## 1.6.2

- Fixed: much of what Guildy users share with each other never arrived. The game lets an addon send ten
  messages in a row and then one a second, and drops the rest without a word; Guildy sent about three a
  second. After a login, when a member who knows little is offered statistics, professions and the bank
  at once, most of it was lost, the bank among it. Guildy now stays under the game's limit and sends
  again what the game refuses. Sharing takes a little longer and arrives.
- The guild bank goes ahead of statistics and professions in line.

## 1.6.1

- Fixed: a member who knew nothing of the guild bank yet never got it from the others. Guildy now offers
  the bank to everyone who has the Bank tab, also to members still on 1.6.0.

## 1.6.0

- New tab: Bank. Guildy reads the guild bank whenever you stand at a banker (gold, tabs, the money log
  and the log of every tab) and keeps what it read, so the ledger goes back further than the game's
  own. Everyone in the guild who uses Guildy sees the same: readings are shared like the professions.
  The tab shows the gold over 7, 30 or 90 days with marks at unusual movements, the ledger with filters,
  who gives and who takes, the largest deposits and withdrawals, the tabs and your own access.
- At a banker Guildy opens on the Bank tab by itself; the Bank options switch that off.
- Customize: Bank, Hall of Fame and Members are yours to arrange, with the same handles everywhere. The
  button stands in the title bar. Boxes are dragged to move them and sized at their corner, the x removes
  one, the + adds one, and the window grows with what you add instead of scrolling.
- Hall of Fame: each page has its own layout, and every box can stand on every page. A click on a single
  tile or title card while customizing changes that one. The options tab for the Hall of Fame is gone.
- Members: drag a heading to move its column, drag its right edge for the width, hide and show columns
  at the headings. The column checkboxes left the options.
- General options: a slider for the size of the window and its texts.
- Fixed: scanning the professions could store the recipe book of the member read before on the next
  member, whose real professions then disappeared and never came back. Guildy now only takes a book
  that belongs to the member it asked. Because wrong and right books cannot be told apart afterwards,
  everything read from other members' books is thrown away once with this version: start a scan on the
  Professions tab to read it anew. Until then the lists are thinner. What members share of themselves
  stays. Books read by members with an older Guildy are no longer accepted, so ask your guild to update.
- A right click on a member has "Discard professions and read anew" for a single member whose
  professions are wrong.

## 1.5.0

- The account view is gone: the side tab with all your characters and their professions had nothing to
  do with the guild, and addons made for it do that better. Twinks inside the guild stay as they are
  (family on the character page, folding in the member list, the shared activity score).
- Without a guild Guildy shows your communities.
- Guildy no longer remembers class, level, race and guild of your characters, only their names for the
  twinks; what it had stored is removed.

## 1.4.0

- Overview tab: a second view for the endgame, with a switch "Levelling | Endgame" in the toolbar. Guildy
  changes to it by itself once half of the active members are level 60; your own choice is kept, and the
  general options have it too ("Overview shows").
- The endgame view shows the activity of the guild, what it did this month against the last (raid and
  dungeon bosses, dungeons, quests, honorable kills, days online), the item levels of the level 60
  members, last online, comings and goings, and for every raid who has a kill and who is raid ready
  without one. A click on a bar, column or raid lists the members behind it.
- New: an activity score from 0 to 100 per player, a main and its twinks together. It counts the days
  online, kills and quests, and group play: raid bosses, dungeon bosses, dungeon runs and battlegrounds
  all go into the same pot, so raiding, dungeons or PvP alone can fill it. A player without a recent
  statistics reading has no score rather than a low one. The guild pulse is the average.
- Guildy now counts the days a member was seen online. The count starts with this version, so the score
  leaves the days out for the first week.
- Members tab: a column "Act." with the score.
- /guildy activity prints the pulse and how many players are in each band.

## 1.3.0

- Guildy now also speaks French, Spanish, Russian and Brazilian Portuguese. It follows the language of
  your game; the general options have a language choice for anyone who wants another one (changing it
  reloads the interface, the game keeps its language).
- The four new translations were written without a native speaker reading them. If a wording is odd
  or a term is not the one the game uses, please open an issue.
- Profession names from the game are recognised in every language Guildy has, whatever language Guildy
  itself is set to.
- /guildy shots all takes every view in every language at the smallest window size, for checking that
  the translations fit; /guildy shots stop ends it.

## 1.2.3

- Members tab: a rank filter takes the place of the group filter, and the group column is gone. Groups
  only existed for guilds that write "Main, <group>" into their notes; ranks every guild has.

## 1.2.2

- Blizzard's own guild window (Info tab, "Blizzard guild window") works again: its chat was empty and
  its frame reached across the screen, because Guildy keeps Blizzard's member list off screen and
  Blizzard's chat hangs on that list. The list is put back while Blizzard's window is shown. Thanks to
  albeva for reporting it.
- The tab on Blizzard's window that leads back to Guildy sits under Blizzard's own side tabs; on
  Forever it was hidden behind the fourth one.
- Communities: the side tab shows a mark while a community has something new, the same mark
  Blizzard's window shows: lines that came in while Guildy did not show that community, and what was
  already unread at the login.
- Hall of Fame: a title card nobody holds yet (no exalted reputation in the guild, no gold spent on
  talents) is shown with "nobody yet". The options counted and showed such a card, the page left it out.
- /guildy shots shows made-up character names, ranks, guild and community names, notes and chat while
  it runs, and sample values on the PvP page; /guildy shots anon switches that on and off by hand.

## 1.2.1

- Fixed the stutter with the chat open: showing the chat fetched the next page of history, which showed
  the chat again, until the whole history of the guild was loaded, and every page wrote all of it anew
  (in a guild with a long history: seconds of stutter and tens of megabytes of memory). Thanks to
  albeva for reporting it.
- The chat shows the newest 100 lines, like Blizzard's guild window, and 100 more each time you scroll
  to the top. A new line no longer makes Guildy read the whole history again.
- Lists only build and fill the rows in view. In a guild of 500 members the member list used to create
  7800 widgets when it opened and fill every row again on each roster update.
- Faster roster updates: the professions in guild notes are only worked out again when a note changed,
  twinks named in notes are found through an index of the names, and sorting no longer lowers every
  name once per comparison.
- The Hall of Fame reads your own statistics at most once a minute instead of on every visit.
- /guildy perf on, then /guildy perf: measures how long Guildy's own code runs and how much memory it
  asks for (events, each tab, roster scans, the chat). The report is the thing to attach when Guildy
  stutters for you. /guildy perf copy shows it for copying, /guildy perf off stops measuring.
- /guildy shots takes a screenshot of every view in front of a plain backdrop (for the gallery
  pictures); /guildy shots backdrop shows the backdrop alone.

## 1.2.0

- Customize Guildy: the cog left of the close button opens a window of its own beside Guildy's, so every
  change shows at once. Its tabs are named like Guildy's: General (where a member's tooltip stands: beside
  the window, beside the row, at the cursor or the game's own spot; resetting everything), Chat
  (professions as icons in the online list), Members (columns to show, twinks under their main, and how
  the list tells online from offline, each style with a preview), Hall of Fame and Professions (sharing
  your professions, moved here from the info tab).
- Hall of Fame editor in that window: per page, the tiles and the title cards on top are yours to pick,
  order and remove, drawn as the page shows them with the guild's real numbers. Tiles can show any
  statistic Guildy tracks, title cards any title of any page; a search narrows both lists, and "Restore
  defaults" brings a page back.
- Members: online members stand above offline ones, each under a header with its count; the options
  offer one list with greyed-out offline names or with a status dot instead. A member's tooltip now
  stands beside the window instead of over the list.
- Every tab is built on the same layout, so nothing moves when switching between them: one toolbar row
  in the same place (search or selection on the left, actions on the right), the same edges for all
  boxes, sidebars of one width, hints and counts in the toolbar, and one size for buttons,
  dropdowns and search fields. "Invite member", "Join a community" and "Edit ranks" moved into the
  toolbar; the member list's column header is the first row of its box.
- Account: the professions of your characters are tiles, one per profession with the best skill, its
  bar and the characters that have it (all of them in the tooltip).
- The window shows the installed version in its title bar. When a guild member already uses a newer
  release, it says so there and once in the chat.
- A profession a character unlearned leaves it: your own characters lose what is no longer in their
  skill list, and others keep at most their two newest primary professions.

## 1.1.1

- Hall of Fame: the general page shows the guild's epic items and need rolls instead of pets. The game
  leaves its "pets owned" statistic empty however many pets a character has; pets come back once
  Blizzard fixes it.

## 1.1.0

- Communities in Guildy: a side tab under the account tab shows your communities on the left (with the
  number of lines you have not seen yet), the chat of the selected one in the middle (channel switch,
  history, timeline and input like the guild chat) and its members on the right, online first; a click
  on a member whispers. Works without a guild too.
- The list shows each community with its icon, short name and member count. "Invite members" under the member
  list opens Blizzard's own invite dialog over Guildy: like the notes, picking a community in Guildy
  also picks it in Blizzard's window underneath, and the guild tabs pick the guild there again. Right clicks on a community or a member open
  Blizzard's own menus (leave the community, member options, notifications); favorites carry Blizzard's
  star and stand first; member notes show as an icon
  and in the member's tooltip.
- Joining a community in Guildy (Blizzard's "Join or create a community" does not work under Guildy):
  invitations stand first in the list and open a panel whose Accept and Decline click Blizzard's own
  buttons underneath; or paste an invite code: Guildy writes it as a link into the chat
  window, and a click there joins (the game allows joining only from its own links). Invite links
  clicked in Guildy's chat go the same way. "Create a community" opens Blizzard's own
  create dialog right from the panel.
- An empty guild roster for a moment (after leaving and joining a community) no longer empties every
  tab: Guildy keeps the last roster and asks the game again.
- Blizzard's own guild window opened from Guildy keeps its chat: Guildy no longer lets go of the chat
  stream Blizzard's window shows while it is open.
- Blizzard's own window, opened from Guildy (Info tab, member menu, joining a community), now has a
  Guildy tab on its right edge that brings Guildy back without closing it.

## 1.0.1

- Guild members under the mouse are read for the Hall of Fame by default now (statistics and gear,
  nearby, same limits as for the target), so it fills up faster. Also switched on once for existing
  installs; `/guildy statmouse` switches it off. If a session ever ends during such a read, Guildy
  switches it off again by itself.

## 1.0.0

Guildy now lives inside Blizzard's guild window, and notes, ranks and Blizzard's member menu come with it.

- J, the guild button of the micro menu and Escape open and close Blizzard's guild window as always;
  Guildy is drawn on top of it (Blizzard's window stays underneath, invisible). Guildy no longer puts
  its own key binding on J, and nothing opens in the background any more.
- Public and officer notes: clicking a member anywhere in Guildy also picks them in Blizzard's own
  member list (Forever saves notes only from there), and their character page shows Blizzard's own
  member panel next to Guildy's window: a click on its note opens Blizzard's note dialog.
- That panel and the note dialog take Guildy's look (dark boxes with a gold edge); rank changes happen
  in the panel's own rank menu, so Guildy's rank button on the character page and promote/demote in
  the member menu are gone.
- A right click on a member in Guildy's lists opens Blizzard's own guild member menu: its "Copy
  character name" copies straight to the clipboard (only Blizzard's code may do that on Forever). In
  combat Guildy's own menu comes as before.
- Invite, message of the day, guild info and the rank editor work from the first click (no "loaded
  once, click again" any more).
- "Blizzard guild window" in the Info tab shows Blizzard's own window until it is closed.
- Recipe search lists each recipe once: the first crafter (online first) and "+N" for the others; the
  tooltip names them all, a click opens a recipe book that can be opened (or whispers), a right click
  picks the crafter.
- Professions tab: column headings that don't fit the narrow list beside the read status are hidden.
- `/guildy` only says to press J: Blizzard's window must be opened by Blizzard's own code.

## 0.6.2

Hotfix for the members tab at the smallest window size.

- The filter bar fits again: the level and profession menus are gone (clicks on a level or a profession
  in the overview still filter and name the filter next to the count). A set class or group shows only
  its value, long group names are cut off, the full text is in the tooltip.
- The "x of y shown" count sits below the list instead of running into the officer note column.

## 0.6.0

Chat history, a character page for every member, twinks and groups from notes, and an account tab
for all your characters.

Chat
- The chat reaches back through the whole guild chat history, like Blizzard's window: scrolling up
  loads older messages from the server. Every line has its time, every day a divider.
- A timeline right of the chat: a mark per day and one for "new since your last login", click to jump,
  drag the thumb. A strip on top names the day you are reading, or says that older messages are loading
  or that the start is reached. With only a few lines it stays empty.
- "New since your last login" divider; a reload keeps it. A button at the bottom jumps back to the
  newest line and counts the lines below.
- The input shows the channel it sends to ("Guild:" / "Officers:"). Wider online list, so zones fit;
  slim gold scrollbar; menu buttons carry an arrow.
- Lines of members who left show their name when the game still knows it, else a grey "Former member".

Members
- Members are clickable the same way everywhere (chat names, online list, members and ranks tab): click
  opens the character page, right-click the menu, shift-click whispers.
- The member menu lists the ranks under "Set rank": one click sets that rank (several /gpromote or
  /gdemote steps in one click). "Copy name" shows the name selected for Ctrl+C. "Remove from guild" is
  red, last in the menu and always asks first.
- The character page is a hero card: portrait by race and gender, level, the Hall of Fame title and
  medals, notes, and for officers the rank menu, notes and removal. Next to it the family (twinks in
  this guild), kills, quests, deaths and item level with the place in the guild, the dungeon collection
  and the professions with their trainer caps. Opening the window again returns to the page.
- Twinks: Guildy users share the characters they have in the guild (only with sharing on); for others
  notes like "Alt, Name", "Twink of Name" or "Main: Name" connect the characters.
- Members tab: class icons, a group column (whatever follows "Main," in the note, e.g. "Main, Murloc
  Raid" or "Main, Friends", so every guild uses its own; twinks take their main's group), item level and
  the officer note (for those who may read it); the professions column is gone. Twinks hang under their
  main or fold into it ("Fold twinks"). Filters by group, "Without note" and "Without officer note" with
  counts show who still needs one.

Account
- New "Account" side tab under the guild tab: an overview of your account (characters, levels,
  professions, kills, quests, deaths and dungeon bosses together, your guilds), all your characters in
  any guild or none, and every profession of the account with its skill. A click on a character opens
  its page in account mode: the family shows all your characters, the open one highlighted. Guildy
  remembers your characters on this computer at each login and never sends them.
- Without a guild the account is the only tab; joining a guild brings the other tabs and the chat back.

Window
- Guildy always opens on the chat tab after a login or reload (within a session it remembers the tab)
  and plays Blizzard's open and close sounds.
- Resizing the window no longer jumps: the bottom right corner follows the cursor, the window stays
  within its bounds and the screen.
- Lists show their scroll bar only when there is something to scroll.
- `/guildy chatdebug` tells where the chat history goes missing.

## 0.5.1

Hotfix for reading online members.

- The results of a run can be closed with the X in their corner, so the recipe book comes back.
- Members whose professions Guildy knows are only read for those professions, not for every one.
- The first member of a run no longer stays without an answer: the first look waits longer and is tried
  once more. Members on your server come first, before others in your zone.
- The result rows fit the narrower column again.

## 0.5.0

The professions tab is rebuilt: professions on the left, their members in the middle, the recipe book of
the selected member on the right. Reading online members works per server.

- Professions: a rail with every profession, its members, how many are online and the best skill. One
  click shows its members, without scrolling through all professions.
- Members: online first, then the offline ones below a divider; filter all, online or with recipes.
  The skill is a bar with marks at the trainer caps, members at the cap of their rank are marked
  "trainer". The age of the data only shows when it isn't from today.
- Recipe book: the recipes of the selected member with their item icons, an own search and buttons to
  open the recipe book, whisper or invite. Shift-click links a recipe in chat.
- Recipe icons are the made items' icons, remembered whenever a recipe book is read. Open your own
  books once, or use `/guildy scanreset` and read online members again, to fill them in.
- Reading online members: only members on your current server answer, so members in your zone go
  first, then those on your server; silent members are skipped for an hour instead of a day.
- Members who run Guildy are not read, they share their recipes themselves.
- The game's sound effects are off while reading and come back afterwards, also after a reload.
- The status column shows one row per member with profession icons and recipe counts, a progress bar
  with the time left, combat pauses and slowdowns.
- `/guildy scanreset` reads every profession again.

## 0.4.0

The Hall of Fame gets a fifth page: PvP. The window now closes with its X in combat too.

- PvP: honorable kills, duels won and lost and battlegrounds played as guild totals, for all time,
  this month or last month, and title cards (Headhunter, Duel master, Front-line regular, Punching
  bag).
- PvP per member: honorable kills with a bar in the class color, duels won : lost as a green and red
  bar with the win rate, battlegrounds and honorable kills this month.
- Killing blows stay on General: Blizzard's statistic counts creatures too.
- The close button (X) works in combat. It used to do nothing until the fight was over; Escape
  already worked.

## 0.3.5

Hotfix: the Stockade is marked as not counted by Blizzard.

- Hall of Fame dungeons: WoW Forever does not count the Stockade in the statistics yet (neither
  Bazil Thredd nor dungeons entered go up). Its column is grey with a note in the tooltip until a
  member has a kill in it.

## 0.3.4

Hotfix: the dungeon progress shows every dungeon and raid by level.

- Hall of Fame dungeons: every dungeon and raid of Forever has its column, sorted by level (as on
  raidy.app), raids last, even before anybody cleared it. Each column is a small dungeon icon (a
  fitting game icon for the new Forever dungeons); the tooltip shows the name, the level range and the
  end bosses.
- A compact table that fits the smallest window: narrow columns grouped in level bands, the kill count
  as a small number at the check mark, a "cleared" count per member, your own row highlighted and the
  column under the mouse marked. Dungeons the game has no statistic for yet are grey, the new
  Forever dungeons have a green edge.
- From 100 kills the small number shows "99+"; hovering a cell shows member, dungeon and the exact
  count.
- The Guildy window is at least 1130 px wide (was 960), so the dungeon table shows every dungeon and
  raid; a smaller saved size grows on the next opening.
- Dalaran's two end bosses and the Scarlet Monastery's two wings count as one dungeon.
- Blizzard counts an Alliance character's Hall of Thanes end boss as Bazzalan (Ragefire Chasm). For
  the Alliance Guildy counts those kills as Hall of Thanes; Ragefire Chasm stays in the list without
  a statistic (the tooltip says why). For the Horde they stay Ragefire Chasm.

## 0.3.3

Hotfix: the equipment dots show every slot.

- Hall of Fame equipment: one dot per slot in the character window's order (armor, rings and
  trinkets, weapons), so members compare column by column. White, grey and legendary items get their
  own dots, an empty slot is a red ring, the off hand next to a two-hander a dim dot.
- Members whose equipment was read by an older Guildy version keep the old order (by quality) until
  they are read again.
- Smoother dots: Guildy brings its own round textures instead of the game's jagged ones (after
  updating, restart the game once; `/reload` is not enough for new textures).

## 0.3.2

Equipment and statistics of guild members nearby.

- Equipment read nearby is stored only when it is complete. Before, often only the first few items
  arrived and were stored (a too low item level, too few quality dots). Such incomplete entries are
  removed and read again; equipment that members share themselves stays.
- Reading guild members nearby works much farther away than before (no longer only within 28 yards).
- With mouseover reading (`/guildy statmouse`), the equipment is also read when the mouse has already
  moved on: hovering over the member once more within a minute is enough.
- Fix: no more Lua errors from Blizzard's achievement window while Guildy reads statistics.
- `/guildy statreset` lets Guildy read every member again right away (for testing).

## 0.3.1

Hotfix.

- Fix: leaving a dungeon group no longer throws a Lua error. Inside instances the names of other
  players are secret, and Guildy now leaves them alone (statistics reading and the invite suggestion).
- Member tooltips follow the mouse like normal tooltips instead of covering the names above the row.
- Hall of Fame: values and labels of the total tiles are centered vertically.

## 0.3.0

The Hall of Fame gets four pages: General, Economy, Dungeons and Reputation, with equipment.

- General: guild totals (now with mounts and pets) and title cards, plus an equipment table (average
  item level compared to the level with a bar, one dot per epic, rare and uncommon item, growth this
  month) and new titles (Best equipped, Stable master, Animal friend).
- Economy: gold earned and spent, auctions posted and bought, where the gold comes from (quests, loot,
  vendors, auction house) and where it goes (flights, postage, talent resets, barber), gold per member
  and gold titles (Bargain hunter, Frequent flyer, Undecided, ...).
- Dungeons: end bosses defeated, dungeons cleared, dungeon visits and deaths, titles (Dungeon veteran,
  Boss hunter, Cannon fodder) and the dungeon progress table.
- Reputation: factions met and at friendly, honored, revered or exalted, titles (Diplomat, Highly
  regarded, Welcome everywhere, Well connected) and reputation per member with one dot per faction.
- Guildy reads your equipment when you change it, and the equipment of guild members right after
  their statistics (same rules: target in inspect range, not in combat, once an hour), and shares it
  with the statistics. Older Guildy versions relay it but don't show it.
- `/guildy statshow` without a name shows your own character, now with the equipment.
- Tidier top bar: pages on the left, the period dropdown (all time, this month, last month) and "All
  statistics" / "Back" on the right, on every page. The member counts moved into the title's tooltip.
  In WoW Forever's launch month "this month" counts from the launch and "last month" is greyed out.
- Opening Guildy comes back to the tab that was open last (before: always the chat tab).
- Fix: resizing the window no longer jumps to the maximum size when the window was centered.

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
