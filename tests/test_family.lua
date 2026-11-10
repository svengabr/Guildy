local T = ...
local ns = T.pureNs()
local Family = ns.Family

local function M(key, name, level, note, officerNote)
  return { key = key, name = name, level = level, note = note, officerNote = officerNote }
end

local ROSTER = {
  M("ran fred", "Ran Fred", 32, "Main"),
  M("fredwild", "Fredwild", 27, "Twink von Ran Fred"),
  M("ran", "Ran", 10),
  M("ranfredo", "Ranfredo", 12),
  M("xii lightspark", "Xii Lightspark", 20, "Heal / Tank"),
  M("solo", "Solo", 15, nil, "alt of Xii Lightspark"),
}

T.describe("Family.NoteLinks", function()
  T.it("finds the members a twink note names, the longest name first", function()
    T.eq(Family.NoteLinks("Twink von Ran Fred", "fredwild", ROSTER), { "ran fred" })
    T.eq(Family.NoteLinks("Twinks: Fredwild, Ranfredo", "ran fred", ROSTER), { "fredwild", "ranfredo" })
  end)
  T.it("needs a twink word, whole names and never the owner", function()
    T.eq(Family.NoteLinks("Ran Fred ist cool", "fredwild", ROSTER), {})
    T.eq(Family.NoteLinks("Main: Ranfredox", "solo", ROSTER), {})
    T.eq(Family.NoteLinks("Twink von Ran Fred", "ran fred", ROSTER), {})
    T.eq(Family.NoteLinks(nil, "ran fred", ROSTER), {})
  end)
end)

T.describe("Family.Groups", function()
  T.it("joins shared lists, own characters and notes", function()
    local families = { ["ran fred"] = { ts = 1, chars = { "Ran Fred", "Ranfredo", "Not In Guild" } } }
    local of = Family.Of("ran fred", ROSTER, families, {})
    T.eq(#of, 2)
    T.eq(of[1].name, "Fredwild") -- highest level first
    T.eq(of[2].name, "Ranfredo")
    T.eq(#Family.Of("solo", ROSTER, {}, {}), 1) -- officer note
    T.eq(#Family.Of("ran", ROSTER, {}, { ran = true, solo = true }), 2) -- own characters, plus Solo's note
    T.eq(#Family.Of("ran", ROSTER, {}, {}), 0)
  end)
end)

T.describe("Family records", function()
  T.it("validates, merges newer records and digests", function()
    T.eq(Family.Validate({ ts = 5, c = { "Ran-Fred", "ran fred", 3, "Fredwild" } }).chars, { "Ran Fred", "Fredwild" })
    T.eq(Family.Validate({ ts = 5, c = {} }), nil)
    T.eq(Family.Validate({ c = { "A" } }), nil)
    local guild = {}
    T.truthy(Family.Merge(guild, "Ran Fred", { ts = 5, chars = { "Ran Fred" } }))
    T.eq(Family.Merge(guild, "Ran Fred", { ts = 4, chars = { "Ran Fred" } }), false)
    T.eq(Family.Digest(guild), { ["ran fred"] = 5 })
  end)
  T.it("keeps the own record while the characters stay the same", function()
    local members = { ["ran fred"] = true, fredwild = true }
    local names = { ["ran fred"] = "Ran Fred", fredwild = "Fredwild" }
    local own = Family.Own({ ["ran fred"] = true, fredwild = true, other = true }, members, names, nil, 100)
    T.eq(own, { ts = 100, chars = { "Fredwild", "Ran Fred" } })
    T.eq(Family.Own({ ["ran fred"] = true, fredwild = true }, members, names, own, 200).ts, 100)
    T.eq(Family.Own({ ["ran fred"] = true }, members, names, nil, 200), nil)
  end)
end)

T.describe("Family notes", function()
  T.it("reads any group name after Main and the main after Alt", function()
    T.eq({ Family.ParseNote("Main, Semi Progress Raid") }, { "main", "Semi Progress Raid" })
    T.eq({ Family.ParseNote("main: Friends ") }, { "main", "Friends" })
    T.eq({ Family.ParseNote("Alt, Ran Fred") }, { "alt", "Ran Fred" })
    T.eq({ Family.ParseNote("Main") }, { "main" })
    T.eq(Family.ParseNote("Heal / Tank"), nil)
  end)
  T.it("finds the main of each family", function()
    local roster = {
      M("ran fred", "Ran Fred", 32, "Main, Murloc Raid"),
      M("fredwild", "Fredwild", 40, "Alt, Ran Fred"),
      M("ranfredo", "Ranfredo", 12, "Alt, Ran Fred"),
      M("solo", "Solo", 15),
    }
    local mains = Family.Mains(roster, {}, {})
    T.eq(mains["fredwild"], "ran fred") -- the Main note wins over the higher level
    T.eq(mains["ranfredo"], "ran fred")
    T.eq(mains["ran fred"], "ran fred")
    T.eq(mains["solo"], nil)
  end)
  T.it("remembers the own characters with their details", function()
    local r = Family.OwnRecord(true, { name = "Drache", classFile = "WARLOCK", level = 3, raceFile = "Human",
      female = false, guild = "Katzen" }, 100)
    T.eq(r.name, "Drache")
    T.eq(r.guild, "Katzen")
    T.eq(r.female, false)
    r = Family.OwnRecord(r, { name = "Drache", level = 4 }, 200)
    T.eq(r.level, 4)
    T.eq(r.classFile, "WARLOCK")
    T.eq(r.guild, nil) -- left the guild
    T.eq(r.seen, 200)
  end)
  T.it("lists the own characters outside the shown ones", function()
    local own = {
      ["ran fred"] = { name = "Ran Fred", level = 33, guild = "Murloc Mafia" },
      ["drache"] = { name = "Drache", level = 3, guild = "Katzen" },
      ["old"] = true, -- remembered by an older version, no details
      ["solo"] = { name = "Solo", level = 20 },
    }
    local list = Family.OwnElsewhere(own, { ["ran fred"] = true })
    T.eq(#list, 2)
    T.eq(list[1].name, "Solo")
    T.eq(list[2].guildName, "Katzen")
    T.truthy(list[2].elsewhere)
  end)
end)
