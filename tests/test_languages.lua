-- The language choice in the loaded addon: the saved setting applies at ADDON_LOADED, nothing reads a
-- text before that, and what Guildy understands of the game does not follow its own language.
local T = ...

local function World(language, more)
  local opts = more or {}
  local setup = opts.setup
  opts.setup = function(env)
    if language ~= nil then env.GuildyDB = { settings = { language = language } } end
    if setup then setup(env) end
  end
  local world = dofile(T.testsDir .. "/wow.lua")(T, opts)
  world.Start = function()
    world.Fire("ADDON_LOADED", "Guildy")
    world.Fire("PLAYER_LOGIN")
    world.Fire("GUILD_ROSTER_UPDATE")
    world.RunTimers()
  end
  return world
end
T.LanguageWorld = World

T.describe("Language", function()
  T.it("applies the saved language", function()
    local world = World("enUS")
    T.eq(world.ns.Locale.current, "deDE") -- the stub client's, while the files load
    world.Fire("ADDON_LOADED", "Guildy")
    T.eq(world.ns.Locale.current, "enUS")
    T.eq(world.ns.L.TAB_MEMBERS, "Members")
    T.eq(world.errors, {})
  end)

  T.it("falls back to the client for an unknown saved language", function()
    local world = World("xxXX")
    world.Fire("ADDON_LOADED", "Guildy")
    T.eq(world.ns.Locale.current, "deDE")
    T.eq(world.errors, {})
  end)

  T.it("reads no text while the files load", function()
    local early = {}
    World(nil, { afterFile = function(file, ns)
      if file ~= "Locales/Locales.lua" then return end
      local meta = getmetatable(ns.L)
      local index = meta.__index
      meta.__index = function(self, key)
        early[#early + 1] = key
        return index(self, key)
      end
    end })
    T.eq(early, {})
  end)

  T.it("knows the game's profession names under every Guildy language", function()
    local world = World("enUS")
    world.Start()
    local ns = world.ns
    for _, code in ipairs(ns.Locale.Languages()) do
      for skillLine, key in pairs(ns.Professions.SKILL_LINES) do
        local name = ns.LocaleTables[code]["PROF_" .. key]
        T.eq(ns.TradeSkill.SkillByName(name), skillLine, code .. " " .. name)
      end
    end
  end)

  T.it("anonymous chat follows Guildy's language", function()
    local function First(language)
      local world = World(language)
      world.Start()
      world.ns.Anon.Enable(true)
      return world.ns.Anon.Lines({ { sender = "A", text = "x" } })[1].text
    end
    T.eq(First("deDE"), "moin zusammen")
    T.truthy(First("enUS") ~= "moin zusammen", "English lines under English")
  end)
end)
