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

1. `media/gallery/01-overview.jpg`: Guildy – your guild, at a glance
2. `media/gallery/02-census.jpg`: Overview: who's actually still playing?
3. `media/gallery/03-professions.jpg`: Professions: who can craft this for me?
4. `media/gallery/04-members.jpg`: Members: find anyone in seconds
5. `media/gallery/05-invite-sync.jpg`: Invite and sharing

## Links

- Source: https://github.com/svengabr/Guildy
- Issues: https://github.com/svengabr/Guildy/issues

## Releases

Project ID 1785901 (in `Guildy.toc`). A tag `v*` runs `.github/workflows/release.yml`: tests, then the BigWigs
packager uploads to CurseForge (repo secret `CF_API_KEY`) and creates the GitHub release with that version's
`CHANGELOG.md` section (`## <version>`).
