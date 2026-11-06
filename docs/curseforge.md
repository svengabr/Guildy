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

Use `README.md` (the part above "Deutsch" plus the German section and Support). CurseForge renders Markdown;
the images point to GitHub raw URLs and show up as they are.

## Gallery (in this order)

Real in-game screenshots (German client), cut out and placed on a neutral background by
`media/gallery/build.py`; the Hall of Fame images are filled up with made-up members.

Title and description per image (CurseForge allows 255 characters per description).

1. `media/gallery/01-chat.jpg`
   - Title: Chat first
   - Description: Press J and Guildy opens on the guild chat, with history, larger text and an input line. Next to it you see every online member with level, class colour, professions and zone. Invite new members with one click.
2. `media/gallery/02-members.jpg`
   - Title: Members
   - Description: Search names, zones and notes, filter by class, level and profession, and sort by any column. The details panel shows rank, notes, last online and professions. Whisper, invite, promote, demote or remove members from here.
3. `media/gallery/03-overview.jpg`
   - Title: Overview
   - Description: Your guild at a glance: classes, levels and professions of the members active in the last month, three months, six months or ever. Also shows last online, who joined and left in the last 30 days, and a class × level grid. Click any bar to see who it is.
4. `media/gallery/04-hall-of-fame.jpg`
   - Title: Hall of Fame
   - Description: Guild totals from Forever's character statistics: creatures killed, quests, deaths, gold and dungeon bosses. Title cards crown the top members, and a grid shows who has cleared which dungeon. View all time, this month or last month.
5. `media/gallery/05-hall-of-fame-ranking.jpg`
   - Title: Hall of Fame ranking
   - Description: Click any statistic for the full guild ranking, with the guild total, the average and your own place. Each value shows where it came from and how old it is: your own, shared by other Guildy users or read from members nearby.
6. `media/gallery/06-professions.jpg`
   - Title: Professions
   - Description: Who has which profession, at what skill and with how many recipes? Search for a recipe or item to find who can craft it. Data comes from Guildy users, profession links in chat, guild notes, or from reading the recipe books of online members.
7. `media/gallery/07-info-log.jpg`
   - Title: Info & Log
   - Description: Message of the day and guild information, both editable right in the window, next to the full guild log: joins, leaves, invites, promotions and demotions. Your sharing settings are here too.
8. `media/gallery/08-ranks.jpg`
   - Title: Ranks
   - Description: Every guild rank with its member count, permissions and members. The guild master edits ranks and permissions in Blizzard's own rank editor, opened right inside the tab.

## Links

- Source: https://github.com/svengabr/Guildy
- Issues: https://github.com/svengabr/Guildy/issues

## Releases

Project ID 1785901 (in `Guildy.toc`). A tag `v*` runs `.github/workflows/release.yml`: tests, then the BigWigs
packager uploads to CurseForge (repo secret `CF_API_KEY`) and creates the GitHub release with that version's
`CHANGELOG.md` section (`## <version>`).
