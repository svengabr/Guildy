local T = ...
local ns = {}
T.loadInto(ns, "Locales/Locales.lua")
local EN, DE = ns.LocaleTables.enUS, ns.LocaleTables.deDE

-- Keys used in code: L.KEY, plus the dynamic families
local function UsedKeys()
  local used = {}
  for _, file in ipairs(T.tocFiles()) do
    if not file:match("^Libs/") then
      local source = T.readFile(T.addonDir .. "/" .. file)
      for key in source:gmatch("L%.([A-Z][A-Z0-9_]*)") do used[key] = file end
    end
  end
  for _, key in ipairs({ "COL_LEVEL", "COL_NAME", "COL_ZONE", "COL_RANK", "COL_PROFS", "COL_LASTONLINE", "COL_NOTE",
    "SORT_BY_LEVEL", "SORT_BY_NAME", "SORT_BY_ZONE", "EVENT_INVITE", "EVENT_JOIN", "EVENT_PROMOTE", "EVENT_DEMOTE",
    "EVENT_REMOVE", "EVENT_QUIT" }) do
    used[key] = "dynamic"
  end
  return used
end

T.describe("Locales", function()
  T.it("has the same keys in English and German", function()
    for key in pairs(EN) do T.truthy(DE[key], "deDE is missing " .. key) end
    for key in pairs(DE) do T.truthy(EN[key], "enUS has no " .. key) end
  end)
  T.it("defines every key the code uses", function()
    for key, file in pairs(UsedKeys()) do T.truthy(EN[key], file .. " uses undefined L." .. key) end
  end)
  T.it("has the Hall of Fame's page, title and gold flow names", function()
    local S = T.pureNs().Stats
    for _, page in ipairs(S.PAGES) do
      T.truthy(EN["FAME_PAGE_" .. page.key:upper()], "FAME_PAGE_" .. page.key:upper())
      for _, fame in ipairs(page.titles) do T.truthy(EN["FAME_TITLE_" .. fame.key], "FAME_TITLE_" .. fame.key) end
    end
    for _, list in ipairs({ S.INCOME, S.SPENDING }) do
      for _, id in ipairs(list) do T.truthy(EN["FAME_FLOW_" .. id], "FAME_FLOW_" .. id) end
    end
  end)
  T.it("names every dungeon the game has no statistic for", function()
    for _, dungeon in ipairs(T.pureNs().Stats.DUNGEONS) do
      if not dungeon.stats[1] then
        T.truthy(EN["FAME_DUNGEON_" .. dungeon.key:upper()], "FAME_DUNGEON_" .. dungeon.key:upper())
      end
      T.truthy(dungeon.icon or dungeon.art, dungeon.key .. " has no icon")
    end
  end)
  T.it("has a name for every profession", function()
    local pure = T.pureNs()
    for _, key in pairs(pure.Professions.SKILL_LINES) do T.truthy(EN["PROF_" .. key], "PROF_" .. key) end
  end)
  T.it("keeps format placeholders in German", function()
    for key, text in pairs(EN) do
      local _, en = text:gsub("%%[ds]", "")
      local _, de = DE[key]:gsub("%%[ds]", "")
      T.eq(de, en, key)
    end
  end)
end)
