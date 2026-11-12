# CurseForge project texts

Copy these into the CurseForge "Create project" form.

## Project name

Guildy

## Summary (one line, English)

A modern guild window for WoW Forever: chat first, who's online, census of active members, professions and recipe search.

## Class

Addons

## Main category

Guild

## Additional categories

- Chat & Communication
- Professions

## Logo

`media/logo.png` (512×512)

## Description

Use `README.md` without the title, the logo, the chat image and the gallery pointer below it: the CurseForge page
already shows those above the description. CurseForge renders Markdown.

## Gallery (in this order)

Real in-game screenshots (German client) of my own guild, taken by `/guildy shots` in front of a plain backdrop
and cut out by `media/gallery/crop.py` and `gallery.py` (see `media/gallery/README.md`). Nothing is retouched
afterwards: during the run Guildy itself shows made-up character names, guild and community names, notes, message
of the day and chat (`Core/Anon.lua`). Levels, classes, zones, professions and statistics are the real ones,
except the PvP statistics: my guild hardly does PvP, so the PvP page shows sample values.

Title and description per image (CurseForge allows 255 characters per description).

1. `media/gallery/01-chat.jpg` (mark it as the featured image)
   - Title: Chat
   - Description: What J opens: the guild chat with times, a timeline of the days and a mark for what is new since your last login. Next to it everyone who is online, with level, class colour and zone.
2. `media/gallery/02-members.jpg`
   - Title: Members
   - Description: Online members above offline ones. Search names, zones and notes, filter by class and rank, sort by any column. The columns are yours to choose.
3. `media/gallery/03-overview.jpg`
   - Title: Overview
   - Description: Classes, levels and professions of the members who were online in the last month, three months, six months or ever, with who joined and left recently. Click a bar to see who is behind it.
4. `media/gallery/04-hall-of-fame.jpg`
   - Title: Hall of Fame: General
   - Description: Guild totals from Forever's character statistics: creatures killed, quests, deaths, flight paths, mounts. Title cards name the top members, and the list below compares equipment.
5. `media/gallery/05-hall-of-fame-economy.jpg`
   - Title: Hall of Fame: Economy
   - Description: Where the guild's gold comes from and where it goes, with gold earned and spent per member.
6. `media/gallery/06-hall-of-fame-dungeons.jpg`
   - Title: Hall of Fame: Dungeons
   - Description: End bosses killed and a grid of every dungeon and raid with each member's clears.
7. `media/gallery/07-hall-of-fame-reputation.jpg`
   - Title: Hall of Fame: Reputation
   - Description: The reputation of every member per standing, for all time, this month or last month.
8. `media/gallery/08-hall-of-fame-pvp.jpg`
   - Title: Hall of Fame: PvP
   - Description: Honorable kills, duels won and lost, and battlegrounds, with the win rate of every member. The numbers in this picture are sample values.
9. `media/gallery/09-professions.jpg`
   - Title: Professions
   - Description: Every profession with how many members have it. Pick one for its members with skill and recipes, and browse a member's recipes next to it. The search finds who can craft an item.
10. `media/gallery/10-info-log.jpg`
   - Title: Info & Log
   - Description: Message of the day and guild information, both editable in the window, next to the guild log.
11. `media/gallery/11-ranks.jpg`
   - Title: Ranks
   - Description: Every rank with its permissions and members. The guild master edits them in Blizzard's own rank editor, which opens inside the tab.
12. `media/gallery/14-character.jpg`
   - Title: Character page
   - Description: A member's statistics, dungeon collection and professions, with their twinks once Guildy knows them.
13. `media/gallery/15-options-members.jpg`
   - Title: Options: Members
   - Description: The cog in the title bar opens the options next to the window, so you see a change while you make it. Here: how the member list tells online from offline, and whether twinks hang under their main.
14. `media/gallery/16-options-hall-of-fame.jpg`
   - Title: Hall of Fame: Customize
   - Description: Every Hall of Fame page is yours to arrange: move, size, add and remove its boxes. A click on a single tile or title card opens a list right under it to put another statistic or title in its place.
15. `media/gallery/17-bank.jpg`
   - Title: Bank
   - Description: New in 1.6: Guildy reads the guild bank at a banker and keeps it. Gold over time with marks at unusual movements, the ledger of gold and items, the tabs and your own access. Shared with everyone in the guild who uses Guildy.
16. `media/gallery/18-bank-overview.jpg`
   - Title: Bank: Overview
   - Description: The same bank arranged as an overview: the figures of the period in a row, the gold chart, the largest depositors, the ledger and the tabs. With "Customize" every box can be moved, sized, removed or added.
17. `media/gallery/19-members-customize.jpg`
   - Title: Members: Customize
   - Description: "Customize" in the title bar turns the headings of the member list into handles: drag one to move its column, drag its right edge for the width, the x hides a column, the + brings a hidden one back.

The pictures made up to 1.2.0 (`00-guildy`, `09-professions-leatherworking`, `12-sync` and the old look of the
others) are gone from the repository. Remove them from the CurseForge gallery when uploading the new ones.

## Links

- Source: https://github.com/svengabr/Guildy
- Issues: https://github.com/svengabr/Guildy/issues

## Releases

Project ID 1785901 (in `Guildy.toc`). A tag `v*` runs `.github/workflows/release.yml`: tests, then the BigWigs
packager uploads to CurseForge (repo secret `CF_API_KEY`) and creates the GitHub release with that version's
`CHANGELOG.md` section (`## <version>`).
