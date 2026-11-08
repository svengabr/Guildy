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
`media/gallery/build.py`. All character names are made up and the guild chat is rewritten. `12-sync.jpg` is
rendered from `media/gallery/sync.html` (a German version is `sync-de.jpg`, not part of the gallery).

Title and description per image (CurseForge allows 255 characters per description).

1. `media/gallery/01-chat.jpg`
   - Title: Chat first
   - Description: Press J and Guildy opens on the guild chat, with history, larger text and an input line. Next to it you see every online member with level, class colour, professions and zone. Invite new members with one click.
2. `media/gallery/02-members.jpg`
   - Title: Members
   - Description: Search names, zones and notes, filter by class, level and profession, and sort by any column. The details panel shows rank, notes, last online and professions. Whisper, invite, promote, demote or remove members from here.
3. `media/gallery/03-overview.jpg`
   - Title: Overview
   - Description: Your guild at a glance: classes, levels and professions of the members active in the last month, three months, six months or ever. Also shows last online, who joined and left in the last 30 days, and a class × level grid.
4. `media/gallery/04-hall-of-fame.jpg`
   - Title: Hall of Fame: General
   - Description: Guild totals from Forever's character statistics: creatures killed, quests, deaths, flight paths, mounts and pets. Title cards crown the top members; the equipment list compares item level and quality and flags who needs an upgrade.
5. `media/gallery/05-hall-of-fame-economy.jpg`
   - Title: Hall of Fame: Economy
   - Description: Where the guild's gold comes from (quests, loot, vendors, auction house) and where it goes (flights, mail). Title cards for the top earners and traders, plus gold earned, spent and auctions per member.
6. `media/gallery/06-hall-of-fame-dungeons.jpg`
   - Title: Hall of Fame: Dungeons
   - Description: Dungeon bosses killed, dungeons cleared and entered, and deaths inside. The progress grid covers all 32 dungeons and raids, grouped by level, and counts each member's clears; click a dungeon for its ranking.
7. `media/gallery/07-hall-of-fame-reputation.jpg`
   - Title: Hall of Fame: Reputation
   - Description: Factions met and standings reached across the guild, with the reputation of every member from Friendly to Exalted. Switch between all time, this month and last month.
8. `media/gallery/08-hall-of-fame-pvp.jpg`
   - Title: Hall of Fame: PvP
   - Description: Honorable kills, duels won and lost, and battlegrounds played across the guild. Title cards for the top fighter and the duel master, plus win rate and this month's kills for every member.
9. `media/gallery/09-professions.jpg`
   - Title: Professions
   - Description: Every profession at a glance: how many members have it and how many are online. Pick one for its members with skill, recipes and data source, and browse a member's recipes right next to it. The search finds who can craft an item.
   - Second image `media/gallery/09-professions-leatherworking.jpg`, Title: Professions: Leatherworking
   - Description: Online members first, then offline, with skill bars and a hint when someone needs a trainer for the next rank. Data comes from Guildy users, profession links in chat, guild notes, or from reading the recipe books of online members.
10. `media/gallery/10-info-log.jpg`
   - Title: Info & Log
   - Description: Message of the day and guild information, both editable right in the window, next to the full guild log: joins, leaves, invites, promotions and demotions. Your sharing settings are here too.
11. `media/gallery/11-ranks.jpg`
   - Title: Ranks
   - Description: Every guild rank with its member count, permissions and members. The guild master edits ranks and permissions in Blizzard's own rank editor, opened right inside the tab.
12. `media/gallery/12-sync.jpg`
   - Title: How sharing works
   - Description: No server, no account: Guildy users swap what they know over the hidden guild addon channel. Newer data replaces older data, members pass on what they've seen, and members without Guildy are read when you target them nearby.

## Links

- Source: https://github.com/svengabr/Guildy
- Issues: https://github.com/svengabr/Guildy/issues

## Releases

Project ID 1785901 (in `Guildy.toc`). A tag `v*` runs `.github/workflows/release.yml`: tests, then the BigWigs
packager uploads to CurseForge (repo secret `CF_API_KEY`) and creates the GitHub release with that version's
`CHANGELOG.md` section (`## <version>`).
