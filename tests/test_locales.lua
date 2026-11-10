local T = ...
local ns = {}
for _, file in ipairs(T.tocFiles()) do
  if file:match("^Locales/") then T.loadInto(ns, file) end
end
local EN = ns.LocaleTables.enUS

-- "%d", "%s", "%.1f" ... in order; "%%" is not one
local function Directives(text)
  local list = {}
  for d in text:gsub("%%%%", ""):gmatch("%%[%d%.%-]*%a") do list[#list + 1] = d end
  return list
end

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
  T.it("has every language of the list that has a file, and no other", function()
    for code in pairs(ns.LocaleTables) do
      local listed
      for _, known in ipairs(ns.Locale.ORDER) do listed = listed or known == code end
      T.truthy(listed, code .. " is not in Locale.ORDER")
    end
    T.eq(ns.Locale.Languages()[1], "enUS")
  end)
  T.it("has the same keys in every language, none empty", function()
    for _, code in ipairs(ns.Locale.Languages()) do
      local texts = ns.LocaleTables[code]
      for key, text in pairs(EN) do
        T.truthy(texts[key] and (texts[key] ~= "" or text == ""), code .. " is missing " .. key)
      end
      for key in pairs(texts) do T.truthy(EN[key], code .. " has unknown " .. key) end
    end
  end)
  T.it("keeps the placeholders and their order in every language", function()
    for _, code in ipairs(ns.Locale.Languages()) do
      for key, text in pairs(EN) do
        T.eq(Directives(ns.LocaleTables[code][key] or ""), Directives(text), code .. " " .. key)
      end
    end
  end)
  T.it("resolves the language", function()
    local R = ns.Locale.Resolve
    T.eq(R(nil, "deDE"), "deDE")
    T.eq(R("enUS", "deDE"), "enUS")
    T.eq(R(nil, "enGB"), "enUS")
    T.eq(R(nil, "koKR"), "enUS")
    T.eq(R("xxXX", "deDE"), "deDE")
    T.eq(R(42, "deDE"), "deDE")
    T.eq(R(nil, nil), "enUS")
  end)
  T.it("gives Mexican Spanish the Spanish texts once there are any", function()
    local had = ns.LocaleTables.esES
    ns.LocaleTables.esES = had or {}
    T.eq(ns.Locale.Resolve(nil, "esMX"), "esES")
    T.eq(ns.Locale.Resolve("esMX", "deDE"), "esES")
    ns.LocaleTables.esES = had
  end)
  T.it("reads from the applied language, English for a gap, the key for an unknown one", function()
    ns.Locale.Apply("deDE")
    T.eq(ns.Locale.current, "deDE")
    T.eq(ns.L.TAB_MEMBERS, "Mitglieder")
    local kept = ns.LocaleTables.deDE.TAB_MEMBERS
    ns.LocaleTables.deDE.TAB_MEMBERS = nil
    T.eq(ns.L.TAB_MEMBERS, "Members")
    ns.LocaleTables.deDE.TAB_MEMBERS = kept
    T.eq(ns.L.NO_SUCH_KEY, "NO_SUCH_KEY")
    ns.Locale.Apply("enUS")
    T.eq(ns.L.TAB_OVERVIEW, "Overview")
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
end)
