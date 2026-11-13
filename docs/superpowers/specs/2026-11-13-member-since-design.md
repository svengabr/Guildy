# Guildy — member since

Date: 2026-11-13 · Author: Conoar (Sven) · Status: approved 2026-11-13

Marks used below: **(Sven)** is what the author approved, **(call)** is a choice made
while writing this document that he has not discussed and may overrule.

## 1. Intent

A user asked on CurseForge for a "member since" date, to see how long members have
been in the guild and who may be due for a promotion. **(Sven)**

## 2. Constraint

The game's roster has no join date. The only source is the guild event log: about
the last 100 events, each with an age. Guildy reads its joins already
(`Game/Roster.lua`) but forgets them at logout. A join that has left the log cannot
be recovered; for such a member Guildy only knows the day it first saw them, which
is a lower bound ("since at least").

## 3. Approaches

1. **Remember the log's joins, fall back to "first seen", share between Guildy
   users** (picked, **(Sven)**). One long-time user fills in everyone's list.
2. Local only, no sharing. Most users would have "first seen" dates for good.
3. Write the date into officer notes. Notes are blocked for addon code on Forever.

## 4. Design

- **Data.** `guild.joined[nameKey] = { d = day, x = true | nil }`. `d` is a day
  number (unix time / 86400, floored), `x` marks a date from the event log. Kept
  apart from the member records, so no record is made for members without
  professions. **(call)** Pruned with a complete roster, like the member records: a
  member who leaves and comes back starts anew.
- **Rules** (`Core/Tenure.lua`, pure):
  - a log date beats a "first seen" date;
  - two "first seen" dates: the earlier one;
  - two log dates: more than two days apart means a rejoin, the later one counts;
    else the earlier one (the log's ages get coarser with time). **(call)**
  - days in the future or not numbers are refused.
- **Roster scan.** After reading the log: every member with a join in the log gets
  that day (exact); every member without any entry gets today ("first seen").
  Members carry `joinedDay` and `joinedExact`.
- **Sharing.** `SUM` carries `j = { n = entries, x = exact ones, s = sum of days }`.
  Whoever sees a summary whose `j` differs from their own offers their dates after
  a random delay, unless someone else sent dates meanwhile, and not twice for the
  same state to the same member. `JOIN { j = { { name, day, 1 | 0 }, ... } }`, at
  most 150 members a message. Older Guildy versions send no `j` and get no offer;
  they ignore `JOIN`. Join dates are guild facts, so `settings.share` (own
  professions) does not switch them off. **(call)**
- **Display.**
  - Members tab: column "Member since" (`joined`), sortable, hidden until the
    player adds it with the + at the headings. Shows the duration: `3 mo`, and
    `3 mo+` for a lower bound.
  - Member tooltip and character page: the date with the duration,
    `02.08.2026 · 3 mo`; a lower bound reads `since at least 02.08.2026`.
  - No setting. **(Sven)**

## 5. Not built

Dates for members who left; an editor to correct a date by hand; promotion rules.
