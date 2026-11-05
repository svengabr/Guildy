local T = ...
local ns = T.pureNs()
local Search = ns.Search

local entries = {
  { memberName = "Zed", skillLine = 171, spellID = 1, recipeName = "Elixir of Lion's Strength", online = false },
  { memberName = "Amy", skillLine = 171, spellID = 1, recipeName = "Elixir of Lion's Strength", online = true },
  { memberName = "Bob", skillLine = 171, spellID = 2, recipeName = "Minor Healing Potion" },
  { memberName = "Cat", skillLine = 171, spellID = 3, recipeName = "Strong Troll's Blood Elixir" },
}

local function names(list)
  local out = {}
  for i, e in ipairs(list) do out[i] = e.memberName or e.name end
  return out
end

T.describe("Search.Recipes", function()
  T.it("puts prefix matches and online members first", function()
    T.eq(names(Search.Recipes(entries, "elixir")), { "Amy", "Zed", "Cat" })
  end)
  T.it("treats pattern characters as text", function()
    T.eq(names(Search.Recipes(entries, "[Elixir")), {})
    T.eq(names(Search.Recipes(entries, "%")), {})
    T.eq(names(Search.Recipes(entries, "lion's")), { "Amy", "Zed" })
  end)
  T.it("accepts links", function()
    T.eq(names(Search.Recipes(entries, "|cffffffff|Hitem:3391::::|h[Elixir of Lion's Strength]|h|r")), { "Amy", "Zed" })
  end)
  T.it("returns nothing for an empty query", function()
    T.eq(Search.Recipes(entries, "  "), {})
  end)
end)

local members = {
  { name = "Ran Fred", level = 16, classFile = "DRUID", zone = "Stormwind", online = true, rankIndex = 1 },
  { name = "Makira Farron", level = 16, classFile = "PALADIN", zone = "Ironforge", online = false, daysOffline = 1, rankIndex = 1 },
  { name = "Eziiria Ash", level = 25, classFile = "PALADIN", zone = "Wetlands", online = false, daysOffline = 40, rankIndex = 3, note = "Herb/Alch" },
}
local profs = { ["Eziiria Ash"] = { [182] = true } }
local function profsOf(m) return profs[m.name] end

T.describe("Search.Members", function()
  T.it("filters by class, bracket, profession and online", function()
    T.eq(names(Search.Members(members, { classFile = "PALADIN" })), { "Makira Farron", "Eziiria Ash" })
    T.eq(names(Search.Members(members, { bracket = 3 })), { "Eziiria Ash" })
    T.eq(names(Search.Members(members, { skillLine = 182 }, nil, profsOf)), { "Eziiria Ash" })
    T.eq(names(Search.Members(members, { onlineOnly = true })), { "Ran Fred" })
    T.eq(names(Search.Members(members, { activeDays = 30 })), { "Ran Fred", "Makira Farron" })
  end)
  T.it("searches name, zone and note", function()
    T.eq(names(Search.Members(members, nil, "iron")), { "Makira Farron" })
    T.eq(names(Search.Members(members, nil, "alch")), { "Eziiria Ash" })
  end)
  T.it("sorts by last online with online first", function()
    local list = { members[3], members[2], members[1] }
    T.eq(names(Search.SortMembers(list, "lastOnline")), { "Ran Fred", "Makira Farron", "Eziiria Ash" })
    T.eq(names(Search.SortMembers(list, "level", true)), { "Eziiria Ash", "Makira Farron", "Ran Fred" })
  end)
end)
