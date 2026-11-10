-- Made-up names for pictures of Guildy (/guildy shots, UI/Shots.lua): while Anon.on, every place
-- that reads a character name, a guild name, a note, the message of the day, the guild information
-- or a chat line shows a stand-in instead. The same character always gets the same made-up name, so
-- the chat, the lists and the character page agree. Levels, classes, zones, professions and
-- statistics stay as they are: they say nothing about a person. The one exception are the PvP
-- statistics, which get sample values (Anon.Stats): a guild that hardly does PvP would show an empty
-- PvP page, and the picture is there to show what the page looks like.
--
-- Nothing is stored under a made-up name: Core/Store.lua hands out records that are not kept while
-- this is on, and the roster scan leaves the saved profession data alone (Game/Roster.lua).
local _, ns = ...

local Anon = {}
ns.Anon = Anon

Anon.on = false

local FIRST = {
  "Alva", "Bero", "Calla", "Doran", "Eska", "Finn", "Greta", "Hauke", "Ilva", "Jorin", "Kessa", "Lorn",
  "Mira", "Nelo", "Orla", "Pell", "Quin", "Rika", "Sten", "Tara", "Ulm", "Vera", "Wim", "Xara",
  "Ylva", "Zeno", "Arno", "Brit", "Cord", "Dana", "Edda", "Falk", "Gesa", "Hanno", "Imke", "Jost",
  "Kira", "Levin", "Maren", "Nika", "Onno", "Runa", "Silas", "Thea", "Uwe", "Vigo", "Wanda", "Yara",
}
local LAST = {
  "Aschenbach", "Birkfeld", "Dornhain", "Eichgrund", "Falkenau", "Grauwacht", "Haselried", "Immergruen",
  "Kupferquell", "Lindental", "Moorweide", "Nebelstein", "Ostwind", "Quellgrund", "Rabenhorst",
  "Silberbach", "Tannhof", "Uferlicht", "Weidenau", "Zunderfels", "Abendrot", "Bruchstein", "Donnerkeil",
  "Erlenbruch", "Fuchsbau", "Glutpfad", "Hagelschlag", "Kiesel", "Lerchenfeld", "Mondsee", "Nordkamm",
  "Pfeilkraut", "Regenfall", "Sturmfeld", "Taubnessel", "Wolkenbruch",
}
local GUILDS = { "Silberwacht", "Die Nachtschicht", "Bund der Wanderer", "Laternenorden", "Eichenrat" }
local GROUPS = { "Kernraid", "Zweitraid", "Freunde", "Twinks", "Neulinge" }
-- by rank index, the guild master first; a guild's own rank names often carry its name
local RANKS = { "Gildenmeister", "Offizier", "Raidleiter", "Veteran", "Stammspieler", "Mitglied", "Freund", "Neuling",
  "Twink", "Gast" }
local NOTES = { "", "", "", "", "Tank", "Heiler", "Kräuter / Alchemie", "Schmied, Bergbau", "Schneider", "ab 20 Uhr online",
  "Leder, Felle", "Verzauberer", "sammelt Rezepte", "" }
local CHAT = {
  deDE = {
    "moin zusammen", "moin", "hat jemand Lust auf Todesminen?", "bin dabei, brauche noch 5 Minuten",
    "sucht noch wer einen Heiler?", "gz!", "danke fürs Mitnehmen gestern", "kann jemand Runenstoff gebrauchen?",
    "ich lege mal Tränke in die Bank", "wer kann mir eine Tasche nähen?", "bin heute Abend ab acht da",
    "das Kloster ging richtig schnell", "wo finde ich den Lehrer für Lederverarbeitung?", "in Eisenschmiede, beim Tor",
    "brauche noch zwei für Zul'Farrak", "komme mit dem Twink", "kurz afk, Essen holen", "wb", "bin wieder da",
    "hat noch jemand die Quest in Tanaris offen?", "ja, ich", "dann gleich zusammen?", "gute Nacht euch",
    "bis morgen", "wer hat das Rezept für den großen Heiltrank?", "ich, schick mir die Kräuter",
    "hat jemand einen Tipp für Stufe 30 bis 35?", "Arathihochland und Desolace gingen bei mir gut",
    "danke, probiere ich aus", "suche noch einen Schmied für eine Waffe", "schick mir die Barren, ich mache sie dir",
    "super, sind gleich in der Post", "wer hat Lust auf Schlachtfeld?", "gleich, erst noch abgeben",
    "ich habe endlich mein Reittier", "glückwunsch!", "wurde auch Zeit :D", "sind am Wochenende wieder Raids?",
    "ja, Mittwoch und Sonntag", "trag dich bitte im Kalender ein", "mache ich", "braucht jemand Verzauberungen?",
    "ich hätte Kräuter übrig, liegen in der Bank", "nehme ich gern", "wo ist der Flugpunkt in Desolace?",
    "im Norden, bei der Nachtelfensiedlung", "gefunden, danke", "ich bin dann mal im Bett", "schlaf gut",
    "wer ist morgen früh online?", "ich ab neun", "dann bis morgen", "kann mich jemand durch die Höhlen ziehen?",
    "komme gleich mit dem Großen", "ihr seid die Besten", "Suppe ist fertig, bin kurz weg", "lass es dir schmecken",
  },
  enUS = {
    "morning all", "hi", "anyone up for Deadmines?", "I'm in, give me five minutes", "still need a healer?",
    "gz!", "thanks for the run yesterday", "does anyone need runecloth?", "putting some potions in the bank",
    "who can sew me a bag?", "I'll be on from eight tonight", "the monastery went really fast",
    "where is the leatherworking trainer?", "in Ironforge, by the gate", "need two more for Zul'Farrak",
    "I'll bring my alt", "afk for a bit", "wb", "back", "anyone still on the Tanaris quest?", "yes, me",
    "then let's do it together", "good night", "see you tomorrow", "who has the greater healing potion recipe?",
    "me, send me the herbs",
    "any tips for level 30 to 35?", "Arathi Highlands and Desolace worked well for me", "thanks, I'll try that",
    "looking for a blacksmith for a weapon", "send me the bars and I'll make it", "great, they're in the mail",
    "anyone up for a battleground?", "in a minute, turning in first", "I finally have my mount", "congrats!",
    "about time :D", "are there raids again this weekend?", "yes, Wednesday and Sunday",
    "please sign up in the calendar", "will do", "does anyone need enchants?", "I have spare herbs, they're in the bank",
    "I'll gladly take them", "where is the flight point in Desolace?", "in the north, at the night elf village",
    "found it, thanks", "I'm off to bed", "sleep well", "who is on tomorrow morning?", "me, from nine",
    "see you tomorrow then", "can someone run me through the caverns?", "coming with my main",
    "you are the best", "dinner is ready, back soon", "enjoy",
  },
}

local names, used = {}, {}    -- name key -> made-up name; made-up names taken
local guilds, guildCount = {}, 0
local groups, groupCount = {}, 0
local ranks = {}              -- real rank name -> stand-in

local function Hash(text)
  local h = 5381
  for i = 1, #text do h = (h * 33 + text:byte(i)) % 2147483647 end
  return h
end

-- Switching it on or off forgets nothing: the same name gets the same stand-in for the session
function Anon.Enable(on)
  Anon.on = on and true or false
end

-- The stand-in for a character name ("First Last"), the name itself while off
function Anon.Name(name)
  if not Anon.on or type(name) ~= "string" or name == "" then return name end
  local key = ns.Names.Key(name)
  local made = names[key]
  if made then return made end
  -- first and last name from two hashes of their own: taken from one, the same few last names kept
  -- coming up (seen in the first pictures)
  local first, last = Hash(key), Hash("last name of " .. key)
  for step = 0, #FIRST * #LAST do
    made = FIRST[(first + step) % #FIRST + 1] .. " " .. LAST[(last + step * 7) % #LAST + 1]
    if not used[made] then break end
  end
  names[key], used[made] = made, true
  return made
end

local function FromPool(known, pool, count, text, fallback)
  local made = known[text]
  if not made then
    count = count + 1
    made = pool[count] or (fallback .. " " .. count)
    known[text] = made
  end
  return made, count
end

function Anon.Guild(name)
  if not Anon.on or type(name) ~= "string" or name == "" then return name end
  local made
  made, guildCount = FromPool(guilds, GUILDS, guildCount, name, "Gilde")
  return made
end

-- The group a guild sorts its members into in the notes ("Main, Murloc Raid")
function Anon.Group(name)
  if not Anon.on or type(name) ~= "string" or name == "" then return name end
  local made
  made, groupCount = FromPool(groups, GROUPS, groupCount, name, "Gruppe")
  return made
end

-- A rank name. index: its place among the ranks, 0 for the guild master (the roster and the rank
-- list know it); without one (the guild log names ranks only) the stand-in given before.
function Anon.Rank(name, index)
  if not Anon.on or type(name) ~= "string" or name == "" then return name end
  if type(index) == "number" then ranks[name] = RANKS[index + 1] or ("Rang " .. (index + 1)) end
  return ranks[name] or "Mitglied"
end

-- A member's note: "Main, <group>" keeps its form with a made-up group, "Alt, <name>" becomes "Alt",
-- anything else a harmless note (most members: none). who: the member's name, so each keeps theirs.
function Anon.Note(note, who)
  if not Anon.on then return note end
  if type(note) ~= "string" or note == "" then return note end
  local kind, rest = ns.Family.ParseNote(note)
  if kind == "main" then return rest and ("Main, " .. Anon.Group(rest)) or "Main" end
  if kind == "alt" then return "Alt" end
  return NOTES[Hash(ns.Names.Key(who or "") .. "note") % #NOTES + 1]
end

-- A member's statistics for showing: a copy with sample PvP values (honorable kills 588, duels won
-- 319 and lost 320, battlegrounds 839), growing with the level; three in ten members get none.
-- key: the member's name key. Everything else in the record is the real thing.
function Anon.Stats(rec, key, level)
  if not Anon.on or type(rec) ~= "table" or type(rec.v) ~= "table" then return rec end
  local h = Hash(tostring(key) .. " pvp")
  if h % 10 < 3 then return rec end
  local scale = math.max(0.15, (tonumber(level) or 30) / 60)
  local copy, values = {}, {}
  for field, value in pairs(rec) do copy[field] = value end
  for id, value in pairs(rec.v) do values[id] = value end
  values[588] = math.floor((h % 700 + 40) * scale)
  values[319] = math.floor((math.floor(h / 7) % 45 + 3) * scale)
  values[320] = math.floor((math.floor(h / 13) % 40 + 2) * scale)
  values[839] = math.floor((math.floor(h / 17) % 90 + 5) * scale)
  copy.v = values
  return copy
end

function Anon.Motd(text)
  if not Anon.on or type(text) ~= "string" or text == "" then return text end
  return "Raid am Mittwoch und Sonntag um 20 Uhr. Anmeldung im Kalender."
end

function Anon.Info(text)
  if not Anon.on or type(text) ~= "string" or text == "" then return text end
  return "Wir spielen entspannt, helfen uns gegenseitig und raiden zweimal die Woche."
end

-- Chat lines for showing: the senders' stand-ins and other people's words replaced by everyday
-- guild chat. A copy; the lines themselves stay as they are.
function Anon.Lines(lines)
  if not Anon.on or type(lines) ~= "table" then return lines end
  local pool = CHAT[ns.Locale and ns.Locale.current or "enUS"] or CHAT.enUS -- Guildy's language
  local out = {}
  for i, line in ipairs(lines) do
    local copy = {}
    for key, value in pairs(line) do copy[key] = value end
    -- "X has joined the guild" names a member in the game's own wording: left out
    if not line.system then
      copy.sender = Anon.Name(line.sender)
      copy.text = pool[(i - 1) % #pool + 1]
      out[#out + 1] = copy
    end
  end
  return out
end
