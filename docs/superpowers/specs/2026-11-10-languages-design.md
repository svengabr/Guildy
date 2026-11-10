# Guildy — more languages, and a screenshot run that tests them

Date: 2026-11-10 · Author: Conoar (Sven) · Status: draft for approval

Marks used below: **(Sven)** is what the author decided, **(call)** is a choice made
while writing this document that he has not discussed and may overrule.

## 1. Intent

Guildy speaks English and German today. It should also speak French, Spanish,
Russian and Brazilian Portuguese, so players on those clients get the window in
their own language. **(Sven)**

Translated text is longer or shorter than the English it replaces, and nobody on
the project reads all four new languages. So the existing screenshot mode
(`/guildy shots`) becomes an end-to-end check: one command takes every view in
every language at the smallest window size, and the pictures are looked through
afterwards for text that is cut off, overlaps or runs out of its box. **(Sven)**

Success: a player with a French, Spanish, Russian or Brazilian client sees no
English in Guildy's own texts, and a full screenshot run in all six languages at
the smallest window size shows no layout defect.

## 2. Goals

1. Four new languages: `frFR`, `esES` (also used for `esMX`), `ruRU`, `ptBR`.
   With `enUS` and `deDE` that makes six. **(Sven: "Welle 1")**
2. A language choice in Guildy's options: "Automatic" (the client's language, the
   default) plus the six languages. Changing it reloads the interface once.
   The game's own language is never touched. **(Sven)**
3. `/guildy shots all`: the screenshot run over all six languages, on its own,
   with the window at its smallest size. **(Sven)**
4. The pictures of such a run are collected per language into a folder of their
   own, apart from the gallery pictures. **(call)**
5. Claude looks through the pictures after a run and reports the defects. **(Sven)**
6. The locale tests cover all six languages.

## 3. Non-goals

- Korean and Chinese (other fonts, other text widths; a later wave), Italian
  (unclear whether the Forever client has it).
- Switching language without a reload. Many labels are set once when the window
  is built; a reload takes the same path as a real start in that language, which
  is also what makes the test pictures trustworthy. **(Sven agreed)**
- Translating README, changelog, the CurseForge description or the gallery.
- Translating what comes from the game (class and zone names, Blizzard's own
  dialogs and guild event wording) or from other players (notes, chat, rank
  names). Those stay in the client's language under every Guildy language.
- Translating the made-up names, ranks, notes and chat of the anonymous mode
  (`Core/Anon.lua`). They are stand-in content, not interface text. **(call)**
- A plural engine. **(call)** See 5.2.
- Review of the translations by native speakers. The translations are written by
  Claude; this is said in the changelog entry so players know to report odd
  wording. **(call)**

## 4. Anti-goals

- A player ends up in a language they did not choose, or cannot find the way
  back. The language entry in the options is recognisable in every language
  (each language named in its own language, e.g. "Deutsch", "Français",
  "Русский").
- The screenshot run leaves Guildy changed: after the run, and after an aborted
  or crashed run, language and window size are what they were before.
- A reload loop. A run that was cut off must not keep reloading the interface on
  every login.
- Guildy's language changes what Guildy understands. Reading the game (profession
  names, system messages) and the sync between Guildy users must work the same
  under every language choice, also between players with different languages.

## 5. Design

### 5.1 Which language applies

- Setting `language` in `GuildyDB.settings`: absent means automatic.
- Automatic: the client's `GetLocale()`. `esMX` uses the Spanish table. `enGB`
  and every locale Guildy has no table for use English.
- A key missing in a language falls back to English, as today.
- The saved setting is only known at `ADDON_LOADED`, after every file of the
  addon has run. So `ns.L` stays one table that every file keeps a reference to,
  and it is filled when the saved setting is known. Consequence: **no text may be
  read from `ns.L` while the files load.** Any place that does so today is moved
  to the point where it is used. A test guards this (5.5).

### 5.2 The translations

- One file per language under `Locales/` **(call)**: about 520 texts each, six
  tables in one file would be over 3,000 lines.
- Terms follow the game's own wording in that language (guild, officer, rank,
  profession names, "whisper", dungeon names), so Guildy reads like part of the
  client.
- Placeholders (`%s`, `%d`) appear in every language in the same order as in
  English: Lua's `format` has no positional arguments.
- Counts: Guildy has pairs like "1 member" / "%d members". Russian needs three
  forms. Instead of a plural engine, Russian texts with a count are worded so
  that one form is correct for every number ("Участников: %d"). **(call)**
- `Guildy.toc` gets a `## Notes-xxXX` line for each new language (`esES` and
  `esMX` both).

### 5.3 What must not follow Guildy's language

- `Game/TradeSkill.lua` (`SkillByName`) matches profession names the game reports
  against, among others, Guildy's own `PROF_*` texts. With a language choice
  those may be in another language than the client. The match uses the
  profession names of **all** languages instead.
- Anonymous chat lines (`Core/Anon.lua`) are picked by client locale today; they
  follow Guildy's language, with English where a language has no lines. **(call)**
- Not checked while writing this: whether anything translated goes over the
  wire in the sync (`Core/Protocol.lua`, `Game/Sync.lua`). The builder checks it;
  only IDs and keys may be sent.

### 5.4 The screenshot run

`/guildy shots` stays as it is (19 pictures, current language, current size).
New:

- `/guildy shots all`: for each of the six languages in a fixed order: set the
  language, reload the interface, wait until the guild roster is there, open
  Guildy, set the window to `UI.MIN_W` × `UI.MIN_H` (1130 × 560), take the 19
  pictures as today. After the last language: restore language and window size,
  one last reload. About five minutes; mouse and keyboard stay untouched.
  "Smallest version" is read as the smallest window size, not the UI scale.
  **(call)**
- `/guildy shots stop` ends a run and restores language and size.
- The run's state (languages left, what to restore, when it started) lives in
  `GuildyDB` so it survives the reloads. A state older than a few minutes is
  treated as a cut-off run at login: restored, not continued.
- Risk: the run reloads the interface and opens Guildy from a timer, not from a
  click. If the client refuses either, the fallback is that the run stops after
  each language and asks for `/reload`, and picks up after it. The builder tries
  the automatic way first.
- Risk: whether a non-Russian client draws Cyrillic in every font Guildy uses
  (Guildy uses the game's font objects, no font files of its own) shows in the
  first run. If glyphs are missing, the Russian pictures say so and the finding
  is reported; fixing it is a separate decision.

### 5.5 Collecting and looking through

- The collecting script takes the newest full run from the game's Screenshots
  folder (six groups of 19, in the fixed language order, which it reads from the
  Lua source like it reads the picture names today) and files them as
  `<language>/<picture name>` in a git-ignored folder. A run with a wrong number
  of pictures is refused, as today.
- The pictures are full screen with a small window in the middle; cropping them
  to the window (`media/gallery/crop.py` exists) makes them easier to look
  through. Left to the builder.
- Claude then reads all pictures and lists per language and view: text cut off,
  text over other elements or outside its box, English left in a translated
  view, missing glyphs. Fixes prefer a layout that holds for every language over
  shortening one translation.
  Stand-in content of the anonymous mode (German or English names, notes, chat)
  and text supplied by the game do not count as "English left".
- Sven starts the run in the game; nothing else can. So the work has two rounds:
  build, then run and review, then fix what the review found. The release comes
  after the second round, since success means a clean run in six languages.
  **(call)**

### 5.6 Tests

- Every language has exactly the keys of English, no empty text, and the same
  placeholders in the same order.
- Language resolution: setting wins over client locale, `esMX` gives Spanish,
  unknown locales give English.
- No text is read from `ns.L` while the addon's files load.
- Profession names of every language are matched by `SkillByName`.

## 6. Left to the builder

- How the locale files are structured and registered, and how `ns.L` is filled.
- Where exactly the language entry sits in the general options and how the
  reload is confirmed.
- The run's timing after a reload, the state's exact shape and the stale limit.
- Folder name and cropping of the collected pictures.
