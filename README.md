# Guildy

<img src="https://raw.githubusercontent.com/svengabr/Guildy/main/media/logo.png" alt="Guildy logo" width="128">

The default guild window shows a chat and a plain list. Guildy replaces it with a window that shows your guild at a glance: who's online and where, who's still active, what classes and levels you have, and who can craft what. Press **J** and it opens on the guild chat, in Blizzard's look.

Made for **WoW Forever**.

![Guildy](https://raw.githubusercontent.com/svengabr/Guildy/main/media/gallery/01-overview.jpg)

## What it does

- **Chat first**: J always opens on the guild chat, with history, a bit larger text and an input line. Officer chat is one click away. Join and leave messages show up in the chat.
- **Who's online**: next to the chat, every online member with level, class colour, professions and zone. Hover for rank, notes and skills, click to whisper, right-click for the menu.
- **Members**: search name, zone or note, filter by class, level bracket and profession, sort by any column. The details panel shows notes, rank, last online and professions.
- **Overview**: the census of your guild. Classes, levels and professions of the members who were online in the last month, three months, six months, or all of them. Click a bar to see who it is.
- **Professions**: who has which profession at what skill, and a recipe search ("who can make Elixir of Lion's Strength?"). Click a member to expand their recipes, or open their recipe book.
- **Info & Log**: message of the day, guild information and the guild log.

![Census](https://raw.githubusercontent.com/svengabr/Guildy/main/media/gallery/02-census.jpg)

![Professions](https://raw.githubusercontent.com/svengabr/Guildy/main/media/gallery/03-professions.jpg)

![Members](https://raw.githubusercontent.com/svengabr/Guildy/main/media/gallery/04-members.jpg)

## Where the profession data comes from

- **Your own characters**: open each profession window once and Guildy knows your skill and recipes.
- **Other Guildy users**: everyone with Guildy shares their professions on the guild addon channel, gathering skills included. It's throttled, so nobody lags. You can switch your own sharing off.
- **Read online members**: one button in the Professions tab opens the recipe book of every online member one after another and stores what it finds. Blizzard's window stays hidden while it runs. It works for members who are online and on your server shard (books of other shards don't open on Forever).
- **Profession links**: click someone's profession link in chat and Guildy remembers their recipes.
- **Guild notes**: notes like "Herb/Alch" or "Tank Schmied" count too, marked "from note". Real data always wins.

![Invite and sharing](https://raw.githubusercontent.com/svengabr/Guildy/main/media/gallery/05-invite-sync.jpg)

## Inviting and managing

"inv pls"? **Invite member** opens Blizzard's own invite dialog with your target filled in, and suggests the last people who whispered you.

On Forever, inviting, removing, promoting, notes and the message of the day are reserved for Blizzard's own interface. Addons can't do them, not even through macros. So Guildy opens Blizzard's dialogs for you, and rank changes and notes happen in Blizzard's guild window ("Manage in Blizzard window" in the member menu). The very first J of a session briefly opens and closes Blizzard's guild window in the background, so the invite button works right away.

## Commands

- `/guildy`: open or close the window
- `/guildy sync`: send your profession summary to the guild
- `/guildy debug`: what Guildy knows about your professions and how the last reads went

## Getting started

1. Install it via the [CurseForge](https://www.curseforge.com/wow/addons/guildy) app or drop it into `Interface/AddOns`.
2. Press **J**.
3. Open each of your profession windows once.

That's it. J gives you the guild window back as soon as Guildy is disabled: it only adds a temporary key binding and never touches Blizzard's code.

---

## Deutsch

Das Standard-Gildenfenster zeigt einen Chat und eine schlichte Liste. Guildy ersetzt es durch ein Fenster, das deine Gilde auf einen Blick zeigt: wer online ist und wo, wer noch aktiv ist, welche Klassen und Stufen ihr habt und wer was herstellen kann. **J** öffnet es immer im Gildenchat, im Blizzard-Stil. Gemacht für **WoW Forever**.

**Die Reiter:**

- **Chat**: Gildenchat mit Verlauf und etwas größerer Schrift, Offizierschat mit einem Klick, Beitritte als graue Zeile. Daneben alle Online-Mitglieder mit Stufe, Klassenfarbe, Berufen und Zone. Klick flüstert an, Rechtsklick öffnet das Menü.
- **Mitglieder**: Suche nach Name, Zone oder Notiz, Filter für Klasse, Stufe und Beruf, sortierbare Spalten und eine Detailansicht.
- **Übersicht**: der Census eurer Gilde. Klassen, Stufen und Berufe der Mitglieder, die im letzten Monat, in den letzten drei oder sechs Monaten oder überhaupt online waren. Ein Klick auf einen Balken zeigt, wer es ist.
- **Berufe**: wer welchen Beruf mit welchem Skill hat, und eine Rezeptsuche („wer kann mir das herstellen?“). Ein Klick klappt die Rezepte eines Mitglieds auf, per Rechtsklick öffnest du sein Rezeptbuch.
- **Info & Log**: Nachricht des Tages, Gildeninformation und Gildenlog.

**Woher die Berufe kommen:** aus deinen eigenen Berufsfenstern (einmal öffnen reicht), automatisch von anderen Guildy-Nutzern (inklusive Sammelberufe, abschaltbar), aus angeklickten Berufslinks, aus Gildennotizen wie „Herb/Alch“ und per Knopf „Online-Mitglieder einlesen“. Der öffnet nacheinander die Rezeptbücher aller Online-Mitglieder deines Server-Bereichs und merkt sich die Rezepte.

**Einladen und Verwalten:** „Mitglied einladen“ öffnet Blizzards Einladen-Dialog mit deinem Ziel schon eingetragen und schlägt vor, wer dich zuletzt angeflüstert hat. Auf Forever dürfen nur Blizzards eigene Fenster einladen, entfernen, befördern und Notizen ändern, Addons nicht, auch nicht über Makros. Guildy öffnet dafür Blizzards Dialoge bzw. das Blizzard-Gildenfenster. Das erste J einer Sitzung öffnet Blizzards Gildenfenster dafür einmal kurz im Hintergrund.

**Befehle:** `/guildy` öffnet und schließt das Fenster, `/guildy sync` schickt deine Berufsübersicht an die Gilde, `/guildy debug` zeigt, was Guildy über deine Berufe weiß.

**Unterstützen:** Guildy ist kostenlos und bleibt es auch. Wenn es dir das Spiel ein bisschen leichter macht, kannst du mir [einen Kaffee ausgeben](https://buymeacoffee.com/conoar).

## Support

Guildy is free and always will be. If it made your game a bit nicer, you can [buy me a coffee](https://buymeacoffee.com/conoar).

## License

GPL-3.0-or-later · Download: https://www.curseforge.com/wow/addons/guildy · Source & issues: https://github.com/svengabr/Guildy
