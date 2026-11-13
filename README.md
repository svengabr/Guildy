# Guildy

<img src="https://raw.githubusercontent.com/svengabr/Guildy/main/media/logo.png" alt="Guildy logo" width="128">

On WoW Forever I almost never opened the guild window. It has a chat and a plain list, and I rarely needed either. Guildy is what I built to change that. Press **J** and you land in the guild chat, with tabs next to it for members, professions and guild records.

It runs inside Blizzard's own guild window and keeps Blizzard's look. It comes in English, German, French, Spanish, Russian and Brazilian Portuguese.

![Guildy chat](https://raw.githubusercontent.com/svengabr/Guildy/main/media/gallery/01-chat.jpg)

More screenshots are in the gallery on [CurseForge](https://www.curseforge.com/wow/addons/guildy).

## The tabs

| Tab | What it shows |
| --- | --- |
| Chat | Guild and officer chat with times and a mark for what's new since your last login. Next to it, everyone who is online. |
| Members | Search, filter and sort the roster. Twinks can hang under their main, and you arrange the columns right at their headings: order, width, which ones show. |
| Overview | A census: classes, levels and professions of the members who were online lately. Once the guild is level 60 it switches to an endgame view: an activity score, what the guild did this month, item levels and raids. |
| Professions | Who has which profession, with skill, specialization and recipes, and whose transmute or Mooncloth is ready today. The search answers "who can make Elixir of Lion's Strength?". |
| Hall of Fame | Guild records from Forever's character statistics: kills, quests, deaths (including by Hogger), gold, dungeons, reputation and PvP. Each page is yours to arrange: which boxes, where and how large, which totals and titles. |
| Ranks | Every rank with its members and permissions. The guild master edits them right there. |
| Bank | The guild bank for everyone in the guild: gold over 30 days and a ledger of every deposit, withdrawal and repair, read whenever a Guildy user opens the bank at a guild banker. |
| Info & log | Message of the day, guild information and the guild log. |
| Communities | Your communities with their chat and members. Works without a guild too. |

Click a member for their character page: the character in its gear, every slot with enchantment and item level, the activity score and how it is made, member since, twinks and professions. "Upgrades from the guild" lists better pieces a guild member can craft for them, rated for their talent spec, with the crafter one click away. Inviting, removing, ranks and notes all work from Guildy's window.

## Where the data comes from

An addon can only read its own character, so Guildy collects the rest.

Professions come from your own profession windows (open each one once), from other Guildy users in the guild, from profession links you click in chat and from guild notes like "Herb/Alch". One button in the professions tab also reads the recipe books of members who are online. Cooldowns can't be read from anyone else, so only Guildy users share theirs.

The Hall of Fame, the activity score, gear and talents use your own character, guild members you target, hover or inspect nearby, and what other Guildy users share and pass on. Gear and talents travel between Guildy users from version 1.8 on. The more members use Guildy, the faster the pages fill up.

## Getting started

1. Install it and press **J**.
2. Open each of your profession windows once.

If you disable Guildy, you get Blizzard's window back as it was.

## Feedback

Bugs and wishes go to the [issues](https://github.com/svengabr/Guildy/issues), or send me a DM on [CurseForge](https://www.curseforge.com/members/conoar). I'm especially glad to hear from officers of bigger guilds, because my own guild has about a hundred members and I can't test every size myself. If Guildy stutters for you, type `/guildy perf on`, play a bit, then `/guildy perf` and attach the report.

## About me

I'm Sven. I've been a software developer for over 20 years, and I write and maintain my World of Warcraft addons in my free time. They are free and open source, and they will stay that way.

## Support

Guildy is free and stays free. If it made your game a bit nicer, you can [buy me a coffee](https://buymeacoffee.com/conoar) or send something via [PayPal](https://paypal.me/svengabr).

## License

GPL-3.0-or-later · Source: https://github.com/svengabr/Guildy
