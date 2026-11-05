# Guildy

A modern, Blizzard-styled guild window for **WoW Forever**. Press **J** and Guildy opens instead of the
default "Guild & Communities" window — always on the guild chat.

## Features

- **Chat first**: guild and officer chat with history, larger text, an input line, and an online list
  with level, class colour, professions and zone. Click to whisper, right-click for the member menu.
- **Invite faster**: "Invite member" suggests your unguilded target and the last people who whispered you.
- **Members**: search, filters (class, level bracket, profession, online), sortable columns and a details
  panel with notes, rank, group invite and remove.
- **Overview (census)**: class, level and profession make-up of the members active in the last
  1 / 3 / 6 months or all of them. Click a bar to see who.
- **Professions**: who has which profession at what skill, and a recipe search ("who can craft
  Elixir of Lion's Strength?").
- **Sync**: Guildy users share their professions and recipes automatically on the guild addon channel
  (can be switched off). Profession links posted in chat are picked up too.
- Ranks & permissions and communities stay in Blizzard's window, one click away.

Slash commands: `/guildy` (toggle), `/guildy blizzard` (Blizzard window), `/guildy sync` (send summary).

## Deutsch

Modernes Gildenfenster im Blizzard-Stil für WoW Forever. **J** öffnet Guildy statt des Standardfensters,
immer im Gildenchat. Mit Online-Liste, schnellerem Einladen, Mitgliederliste mit Filtern, Census der aktiven
Mitglieder (1/3/6 Monate), Berufen mit Rezeptsuche und automatischem Abgleich zwischen Guildy-Nutzern.

## Development

- Tests: `luajit tests/run.lua` (unit tests of `Core/`, locale checks, load smoke test).
- Lint: `docker run --rm -v "$PWD:/data" -w /data ghcr.io/lunarmodules/luacheck .`
- Install for testing: directory junction from `Interface\AddOns\Guildy` to this folder.
