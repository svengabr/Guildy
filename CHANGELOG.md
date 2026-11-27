# Changelog

## 1.17.0

- New: right-clicking a member offers "Remove from guild" (for officers who may remove them), so you no
  longer have to open each member's page to remove them. Guildy still asks before removing anyone.
- New: right-clicking a player outside the guild (in the chat or on their portrait) offers "Invite to
  guild". It opens a small box with "/ginvite Name": Ctrl+C, then Ctrl+V in the chat and Enter. The game
  blocks invites an addon fills in, so the last step stays yours.

## 1.16.0

- New: Guildy's creator has a "Guildy Creator" line in the tooltip.

## 1.15.0

- New: the Events tab shows event times in your own time zone, and you enter new events in it too. Where it
  differs from the server's, the server time stands beside it. Guild chat announcements and reminders stay
  in server time, since everyone reads those, and so does Blizzard's calendar.

## 1.14.0

- New: "Not mine" under Options > Members > "Characters on this account". A WTF folder copied from
  someone else's PC brings their characters along, and Guildy then announced them all as your twinks.
  "Not mine" takes such a character out, replaces the wrong list in the guild and sends the corrected
  ones. Logging in with the character adds it back.
- New: "Wrong?" beside the Family box on a member's page. Its tooltip explains where family links come
  from (your own characters, other Guildy users' lists, notes like "Alt, Name") and a click opens the
  options page that fixes them.
- Fixed: in controller mode Guildy took L1 and R1 for its tabs, and after every fight it took them again
  even with the window closed. That broke them for the game and for controller addons like Controller
  Forever. Guildy no longer binds L1 and R1; the tabs are reached with the cursor.
- Fixed: closing the guild window in controller mode could report Guildy for a blocked
  SetPreferredGamepadInteractTarget.
- Fixed: in controller mode a big guild froze for seconds after opening the window. Blizzard's hidden
  member list, which Guildy uses for notes, now only grows once you go to edit a note.

## 1.13.0

Basic controller support: Guildy now works with the game's built-in controller interface (turned on in
the game's options under Controller). This is a first batch: rearranging the layout, moving and resizing
the window and right-click menus still need the mouse.

- New: L1 and R1 switch between the bottom tabs while the guild window is open, as on Blizzard's own
  windows with tabs. They go back to their normal use when the window closes or combat starts.
- New: the cursor starts on the tab you're looking at when the window opens, usually Chat.
- New: dropdown menus (channel, sorting, class and rank filters, the time of an event, the options) open
  as the game's own menus: the cursor jumps in, Circle closes just the menu, and the cursor goes back to
  the button.
- New: the options window, confirmation dialogs, the title picker and the copy box take the cursor while
  they're open, and Circle closes just them.
- Fixed: buttons that use Blizzard's guild functions did nothing on Cross: closing the window, inviting,
  accepting or declining a community invite, editing the guild info and ranks, removing a member. They
  now work like with the mouse.
- Fixed: the cursor moved onto Blizzard's guild window hidden under Guildy, onto buttons and lists you
  couldn't see. It now only reaches what you see.
- Fixed: moving around went to the wrong place in several spots. Left and right now go along the bottom
  tabs, the toolbar and the column headings in the order shown (also after you rearrange columns), up
  from the tabs goes to the chat line and down from it back to the tabs, and list rows are reached at the
  member's name instead of a value inside the row.
- Fixed: a member's card flashed up for a moment and vanished when the cursor moved onto their row. It now
  stays while the cursor is on the row.
- Fixed: the cursor could get stuck on things that only work with the mouse: the window's resize corner,
  the chat's timeline bar and the character model on the member page. It now skips them; the day marks
  on the timeline can still be reached.

## 1.12.0

- New: with EllesmereUI installed, Guildy takes on its look. The window, its options, boxes, buttons,
  tabs, input fields, checkboxes and scroll bars follow your EllesmereUI theme and its accent color.
  Guildy appears in EllesmereUI's options under Blizzard Skins+ > Window Skins > Third-Party Addons,
  where you can switch this off. Without EllesmereUI nothing changes.

## 1.11.3

- Fixed: in guilds of around 1000 members, the game could still freeze every 10 to 15 seconds while you
  pointed at members with Guildy's window open. Blizzard's hidden member list behind Guildy rebuilt all
  of its rows whenever you pointed at a member, and every row also re-read its member on each roster
  update. In guilds over 200 members the list and its rows now stay idle. The list only rebuilds when
  you point at a member it doesn't know yet, such as someone who just joined.
- Fixed: in big guilds, the first time you pointed at a member could freeze the game while Blizzard's
  hidden list made a row for every member at once. It now fills up a few rows per frame, starting a
  second after the window opens, and stays filled while the window is open.
- Fixed: a profession specialization you just learned (such as Transmutation or Dragonscale) showed up
  nowhere until your next skill-up. Guildy now reads it from your spell book right away.
- `/guildy perf` now also lists frames that took longer than 100 ms, whoever spent the time, named by
  what Guildy did just before, and says when the time went to Lua's garbage collection.

## 1.11.2

- Fixed: in guilds of around 1000 members, the game still froze for a moment every few seconds while
  Guildy's window was open. Blizzard's hidden member list behind Guildy re-read and re-sorted every
  member on each roster update, and in a guild that big an update comes every second or two. In guilds
  over 200 members that list now stays idle. It refreshes once when you point at a member, and at most
  every 10 seconds after that.

## 1.11.1

- Fixed: in big guilds (several hundred members), the game stuttered while Guildy's window was open and
  lagged badly while moving it. Guildy now reads the roster with far less work, waits longer between
  reads the bigger the guild is (up to 10 seconds), and keeps Blizzard's hidden member list short in
  guilds over 200 members, so the game no longer redraws a row for every member on each roster update.
  While you move the window, Blizzard's hidden window behind it now follows once when you let go.

## 1.11.0

- New: an Events tab with your guild's calendar events. The picked event shows who signed up, in three
  columns for tanks, healers and damage (by the talents Guildy knows of them), and below them who is
  tentative, on standby, declined or out. Answer with one click: sign up or tentative, and withdraw
  again. Ranks who may edit the event set their own status the way Blizzard's calendar does.
- New: create guild events in Guildy's own form: name, type, date, time, description and lock. For
  dungeons and raids, pick from all of WoW Forever's dungeons with their picture and level range. These
  are real events of the game's calendar, so members without Guildy see and answer them there.
- New: edit and delete events in Guildy. Ranks who may edit an event right-click a name to set that
  player's status, make them a moderator, remove them or invite them to the group.
- New: tick the box in the form and Guildy announces the new event in guild chat. 30 minutes before an
  event starts, Guildy reminds you in your chat (unless you declined) and posts one reminder in guild
  chat for the whole guild, sent by one Guildy user. WoW Forever lets addons write in guild chat only
  while you press a key, so these lines go out with your next key press (moving, jumping). Both
  reminders can be switched off in the options.
- New: the Events tab glows while there is an event you have neither seen nor answered.
- New: hide profession cooldowns your guild does not track (Iron to Gold and the other transmutes) in
  the options, on the Professions page. They disappear from the member tooltip and the Professions
  tab; Guildy still reads and shares them.
- Changed: the tabs are ordered by use: Chat, Members, Events, Overview, Professions, Bank, Hall of
  Fame, Info & Log, Ranks, Blacklist.

## 1.10.2

- Fixed: with the game's gamepad interface, Guildy's entries in other players' right-click menus
  ("Add to Guildy blacklist", "Discard professions and read anew") broke the menu, and actions such as
  Interact or Set Focus stopped working. Guildy no longer adds entries to the game's menus while the
  gamepad interface is on.
- Fixed: with the gamepad interface, a right-click on a member in Guildy opened an empty menu at the edge
  of the screen. It now opens Guildy's own member menu (character page, whisper, invite, copy name,
  discard professions).
- Fixed: with the gamepad interface, opening Guildy's tabs took up to several seconds. They now open as
  fast as with mouse and keyboard.

## 1.10.1

- Fixed: guild chat lines written in Discord through the guild's Discord integration showed up in
  Guildy as "Former member". They now show the author with the Discord icon in front, like the game's
  own guild window: the character the Discord user last played, or their Discord name if no character
  is known.
- Fixed: Guildy could list a member with a profession they don't have, "via link" and without recipes.
  After you opened another member's recipe book, Guildy saved your own skill levels on that member each
  time one of your skills went up, and shared them with the guild. Your skill levels now stay on your
  own character.
- Fixed: "Discard professions and read anew" could not be reached from the member lists, since a
  right-click there opens the game's guild member menu. The entry is now at the bottom of that menu.
  Use it on members who show a profession they don't have; the next scan reads their professions anew.

## 1.10.0

- New: a Blacklist tab, shared with every Guildy user in your guild. Add players your guild should be
  warned about, of either faction: kill on sight, ninja looters, insults, scammers or other, with a short
  reason. Anyone can add a name and change its kind or reason with a click on it. Officers can remove any
  name; you can rename or remove the names you added yourself, as long as nobody else changed them. Only
  officers can add back a name an officer removed. Every change reaches the other Guildy users at once,
  and whoever was offline gets the list at their next login.
- New: when someone from the blacklist shows up near you, you target or hover them, they join your group,
  invite you, whisper you or open a trade, Guildy writes a warning in your chat and plays a sound (at most
  once every 5 minutes per player; you can switch it off in the options). Their tooltip shows why they
  are on the list.
- New: add a player from their right-click menu ("Add to Guildy blacklist") or with /guildy bl on your
  target. Guild members and your own characters can't be added, and only names a character can have
  (first and last name, letters only); Guildy writes them with capitals itself.
- Fixed: "Read online members" on the Professions tab turned off the game's sound effects for the whole
  scan, and if a fight started, the game stayed silent until the scan ended. Sound effects are now only
  off for the moment each recipe book is read, and come back right away when you are in combat.
- Fixed: an error ("Guildy tried to call a protected function") when the Info & Log tab showed the
  message of the day, for example inside a dungeon. Guildy now remembers the message of the day the game
  sends at login and when it changes.

## 1.9.10

- Fixed: when two people play on the same WoW account, Guildy showed all of its characters as one
  player's twinks, and the whole guild saw it that way. The Members tab of the options now has
  "Characters on this account": give each character its player (1, 2 or 3). Guildy sends the
  corrected twink lists to the guild right away, and they replace the wrong ones, also for guild
  members on older Guildy versions.
- New: an FAQ tab in the options, with answers to the questions that come up most: twinks under the
  wrong player, how Guildy finds twinks, why a member's gear or talents are empty, and what Guildy
  shares with your guild.

## 1.9.9

- Changed: Guildy now files your guild under its realm type (PvE, PvP, RP, RP-PvP or Hardcore) instead
  of the realm name, which the game no longer tells addons. Your guild's data moves over by itself the
  next time you log in with a character in that guild; nothing is lost.

## 1.9.8

- Fixed: if you install Guildy fresh after this week's WoW update, or join a guild Guildy hasn't seen
  before, the guild tabs stayed empty. The game no longer tells addons the realm name, and Guildy had
  nothing to file the new guild under. It now uses your server's number from the game instead.
  Guilds Guildy already knows are not affected.

## 1.9.7

- Fixed: since today's WoW update, the Hall of Fame and the other tabs could show your guild empty
  after logging in or a /reload. The game no longer tells addons the realm name, and Guildy looked for
  your guild under a name without it. It now finds your guild by its name, and anything it stored
  under the wrong name in the meantime moves back into your guild. Nothing was lost.
- Fixed: Lua errors in battlegrounds and instances when opening the guild window. The game hides the
  guild chat, communities and member details from addons there. Opening the guild window in a
  battleground or instance now shows Blizzard's own window, which still shows the guild chat. The
  Guildy tab on its right edge brings Guildy back for everything else.
- New: PvP ranks. The Hall of Fame's PvP table has a Rank column, and the character page shows the
  rank next to the name, both with Blizzard's gold rank badges and the game's rank titles, for example
  "(1) Private". Guildy reads your own rank, shares it with other Guildy users and reads it when you
  inspect a guild member nearby.

## 1.9.6

- New: the guild log on the Info & Log tab has filters (thanks for the idea!). All, Joined, Left,
  Invited and Ranks, each with its count, so you can see at a glance who left or who was invited. Every
  line has a colored mark: green for joins, blue for invites, gold and orange for promotions and
  demotions, red for leaving or being removed. The game only keeps the last 100 entries of the log.

## 1.9.5

- Changed: Guildy no longer posts in guild chat when a member reaches level 60 (thanks for the
  feedback: players want to announce it themselves). The banner still shows, only to you, and can be
  turned off under Customize (the cog) → General. Guilds will see the line until everyone has updated.

## 1.9.4

- Fixed: after changing ranks for a while, Blizzard's rank and notes panel could stop working for
  everyone until a reload (thanks for the detailed report!). Guildy re-opened that panel itself after
  Blizzard closed it during a rank change, and that blocked Blizzard's rank menu and note dialog. If
  the panel closes now, click the member again or use "Edit notes" on their page.
- If it still happens, type /guildy notedebug while it's broken and post the output: it now shows
  whether something blocked Blizzard's panel, and what.

## 1.9.3

- Fixed: clicking a member sometimes didn't open Blizzard's panel for their rank and notes (thanks for
  the report!). Clicking a name in Guildy's chat now opens it, as a click in the member list always did.
- New: an "Edit notes" button on the character page opens the panel for pages you reached another
  way, the member menu for example. When Blizzard's guild window can't show the member, it says why.
- Fixed: offline members' rank and notes panel didn't open when Blizzard's roster hid offline members.
  Guildy now has Blizzard's roster list them (takes effect after a /reload).

## 1.9.2

- Faster in big guilds (reported with 1000 members, thanks!). When another Guildy user logs in, dozens
  of records come in over a few seconds, and Guildy redrew the open tab for every one of them. It now
  redraws at most once a second while data comes in; receiving costs almost nothing.
- Roster updates are cheaper: when nothing visible changed, nothing is redrawn, and in a big guild
  Guildy reads the roster at most every few seconds (about every second with 100 members, every five
  with 1000).
- Fixed: in guilds of a few hundred members and more, the summary Guildy sends at login was too long to
  arrive, and everything Guildy wanted to send after it got stuck. It now goes out in parts that each
  fit, so big guilds sync again. Please update everyone: older versions understand the parts, but
  answer them with more than needed.

## 1.9.1

- New: the Members tab's Rank and Class filters can hide values. Right-click a rank, an "Alt" rank for
  example, to leave its members out and see everyone else. Hide as many as you like; the button then
  reads "not Alt". Right-click again to show it, "All" or Reset to clear. A left-click still shows only
  that rank or class.
- Fixed: Escape did not close Guildy's dropdown menus. It now closes the menu, and only the menu.

## 1.9.0

- New: the Bank tab has two pages, switched at the left of its toolbar. "Movements" is the tab as it
  was; "Contents" shows what lies in the bank's tabs. Each page keeps its own boxes and layout.
- Contents: every item once with its count, stacks, tabs and how much of it came in or went out in the
  chosen days, sortable and searchable, for all tabs or one. Or one tab as the game's grid, with the
  search lighting up what it finds. Beside it "Where it lies": the tabs and slots of the item you click.
- A click on a tab in the "Tabs" box shows its contents; a click on an item in the ledger shows where it
  lies now.
- The Contents page shows the gold in the bank above the list. With Auctionator or TSM installed, turn on
  "Auction house value" under Options, Bank, to see what the items would fetch, the bank's total value
  and an AH value column. The prices come from your own scans and are not shared.
- Fixed: buying a bank tab counted its price twice in "Withdrawn", the gold chart and the member list.
- Fixed: in a low window the last line of the "Guild bank" box ran into the box below.

## 1.8.3

- Fixed: Guildy cost CPU time every frame, even with its window closed (in AddonProfiler often the
  addon with the most time). The bodies Guildy keeps ready for the character page's 3D model stayed
  shown, invisibly, and the game animated and drew them all the time. They now wait hidden and show only
  on the character page; the frame rate goes up with it.
- New: `/guildy cpu` measures what the game itself charges Guildy per frame, the number AddonProfiler
  shows. Please add what it prints when you report stutter.

## 1.8.2

- Fixed: a Lua error on WoW Forever ("attempt to compare a secret string value" in Game/Stats.lua) when
  Guildy read a member while the game kept their character ID secret, in instances for example.
- Fixed: "Invite to group" did nothing but raise an error, since WoW Forever does not let addons invite.
  It now puts "/invite Name-Realm" in the chat box; press Enter to send the invite.
- Hall of Fame: "Gold from auctions" and "Most expensive auction sold" carry a note. WoW Forever counts
  both far too low (a Blizzard bug); Guildy shows them as the game reports them.

## 1.8.1

- New look for the member tooltip: Guildy's own dark panel with the gold border, like the item tooltips
  and the activity score. Race, class and talent tree as icons beside the name, online and zone, the
  facts with their labels in a column of their own, professions and cooldowns, each group set apart by a
  thin line. Lines stay on one line as long as there is room.
- The member tooltip now opens at the mouse. The other spots (beside the window, beside the row, the
  game's own) are still there under Options, General.
- Hall of Fame: a click on a member in the tables opens their character page, a right click the member
  menu, and the row under the mouse lights up as in the member list.
- The race icon also shows for members the game has not seen yet (from their shared gear) and for races
  beyond the classic ones.
- Fixed: the profession cooldowns listed every enchanting recipe as ready. Right after a cast the
  profession window reports the global cooldown for every recipe, and Guildy took it for a cooldown.
  Such recipes are forgotten once, and readings from older versions keep only the known cooldown crafts
  and cooldowns that really ran.
- Fixed: a member's own gear and talents go out again when someone holds a newer record of them.

## 1.8.0

- New: the character page shows each member's gear slot by slot: item with its random suffix ("of the
  Tiger"), enchantment ("no enchantment" in orange where the slot should have one) and item level as a
  bar. A tick on the bar marks "ready at": the middle item level of the guild's members at the same
  level, once at least five of them are known.
- Where the gear of others comes from: Guildy users in the guild share their own (only while "share my
  data" is on) and pass on what they know of others, and Guildy reads members you target or inspect
  nearby, as for the statistics. One player in the capital fills the page for everyone. Gear and talents
  travel in a new message, so members still on 1.7 or older see them only after updating. A member whose
  gear nobody has seen yet gets one clear message instead of empty rows.
- The character stands in its gear on the page, in front of the dressing room art of its race, turned
  with the mouse and zoomed with the wheel. Your own character and members nearby look as they are;
  other members show their race, sex and gear, with face and hair borrowed. For that Guildy needs a
  player of the member's sex to have been in sight once (target, group, nameplate, mouseover), even with
  the guild window closed, and keeps one body per race and sex your guild needs. For the other sex than
  yours the race portrait stands there until then, with a line saying so.
- New: "Upgrades from the guild" on the character page: up to five better pieces a guild member can
  craft for this member, each with the gain in big green, the crafter and whether they are online. A
  click on the crafter whispers them, and a piece's tooltip stands beside the one it would replace. A
  piece counts when it beats the worn one by 10 % for the member's talent spec, with Guildy's own stat
  weights per class and spec (feral cat or bear by the gear worn); while the spec is unknown it goes by
  the stats of the gear worn. The heading says which it is.
  Stamina alone makes no upgrade, except for tanks. Pieces of a lighter armour type than the one worn,
  pieces the member cannot wear yet and pieces that ask for a reputation, or for a profession or class
  the member lacks, are left out, and so are weapons, off hands, ranged, shirts and tabards for now. When
  nothing beats the gear, the box says so.
- Talents come from your own character, from members Guildy inspects nearby and from other Guildy
  users, the same way as the gear. On Forever Guildy reads the points per talent tree from the game's
  trait tree.
- New: profession specializations. Goblin or gnomish engineer, weapon-, armor-, sword-, hammer- or
  axesmith, dragonscale, elemental or tribal leatherworker: Guildy shows it after the name on the
  Professions tab, in the member tooltip and on the character page, and the profession's tooltip lists
  who has which. Your own comes from the game; for others Guildy reads it from their recipe book
  (engineering) or gets it from Guildy users. Forever has no alchemy or tailoring specializations.
- New: profession cooldowns. Transmutes (Forever's own included), Mooncloth and the Salt Shaker: Guildy
  reads your own and shares them while "share my data" is on, so the Professions tab shows who can
  transmute today. Nobody can read another player's cooldowns; where a member's book has such a craft
  and nobody shared it, Guildy says so.
- New: member since. Guildy remembers when each member joined and shows it in the member tooltip and on
  the character page; the Members tab has a sortable column for it ("Customize", then the + at the
  headings). The game keeps no join date: Guildy reads the guild's event log, which reaches back about a
  hundred events, and Guildy users share what they know. For a member who joined earlier Guildy counts
  from the day it first saw them and marks it with a +: at least that long.
- The activity score is measured in hours of play a week, whatever they are spent on: about 5 hours
  make Active, 15 Very active. Solo play counts as much as group play. A panel explains how a score is
  made (presence and playing per week and what fed them, which characters count, the period); it opens
  from the score tile on the character page, the activity column on the Members tab and the comings and
  goings in the overview.
- The character page's left card is ordered anew: the model in a gold frame, name, race, class, rank
  and zone on one line, member since and last online, the notes, the buttons at the bottom. The
  professions box takes only the room its rows need. The dungeon collection and the medals left the
  page; the dungeons stay in the Hall of Fame.
- The profession icons in the chat's member list are off unless you switch them on in the options.
- For checking: `/guildy gearshow`, `talentprobe`, `upgradeprobe`, `craftprobe`, `modeltest`, `cd` and
  `spec` print what Guildy knows or the game answers.
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
