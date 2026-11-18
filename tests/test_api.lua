-- GuildyAPI (Core/API.lua): name formatters of other addons
local T = ...

local function World()
  local world = dofile(T.testsDir .. "/wow.lua")(T)
  return world, world.env.GuildyAPI, world.ns
end

local function Colored(ns, name, classFile)
  return "|c" .. ns.Widgets.ClassHex(classFile) .. name .. "|r"
end

T.describe("GuildyAPI", function()
  T.it("is a global and changes nothing without a formatter", function()
    local _, api, ns = World()
    T.eq(api.version, 1)
    T.eq(ns.DisplayName("Ran Fred"), "Ran Fred")
    T.eq(ns.Widgets.ClassName("Ran Fred", "MAGE"), Colored(ns, "Ran Fred", "MAGE"))
    T.eq(ns.Widgets.ClassName(nil, "MAGE"), Colored(ns, "?", "MAGE"))
  end)

  T.it("shows what a formatter returns in class-colored names", function()
    local _, api, ns = World()
    api.RegisterNameFormatter("Test", function(name) if name == "Ran Fred" then return "Freddy" end end)
    T.eq(ns.Widgets.ClassName("Ran Fred", "MAGE"), Colored(ns, "Freddy", "MAGE"))
    T.eq(ns.Widgets.ClassName("Au Tsch", "MAGE"), Colored(ns, "Au Tsch", "MAGE"))
  end)

  T.it("keeps plain text only", function()
    local _, api, ns = World()
    api.RegisterNameFormatter("Test", function(name)
      if name == "A" then return "x|y" end
      if name == "B" then return "|" end
      return 42
    end)
    T.eq(ns.DisplayName("A"), "xy")
    T.eq(ns.DisplayName("B"), "B") -- nothing left: the name
    T.eq(ns.DisplayName("C"), "C") -- not a string: the name
  end)

  T.it("asks the formatters in order until one gives a name", function()
    local _, api, ns = World()
    api.RegisterNameFormatter("First", function(name) if name == "A" then return "first" end end)
    api.RegisterNameFormatter("Second", function() return "second" end)
    T.eq(ns.DisplayName("A"), "first")
    T.eq(ns.DisplayName("B"), "second")
  end)

  T.it("replaces the formatter of the same owner and removes it", function()
    local _, api, ns = World()
    api.RegisterNameFormatter("Test", function() return "old" end)
    api.RegisterNameFormatter("Test", function() return "new" end)
    T.eq(ns.DisplayName("A"), "new")
    api.UnregisterNameFormatter("Test")
    T.eq(ns.DisplayName("A"), "A")
    api.UnregisterNameFormatter("Unknown") -- no error
  end)

  T.it("reports a failing formatter once and drops it", function()
    local world, api, ns = World()
    api.RegisterNameFormatter("Broken", function() error("boom") end)
    api.RegisterNameFormatter("Good", function() return "good" end)
    T.eq(ns.DisplayName("A"), "good")
    T.eq(ns.DisplayName("B"), "good")
    T.eq(#world.errors, 1)
    T.truthy(world.errors[1]:find("Broken", 1, true), "the error names the owner")
  end)

  T.it("leaves secret values and made-up names alone", function()
    local world, api, ns = World()
    local calls = 0
    api.RegisterNameFormatter("Test", function() calls = calls + 1 return "alias" end)
    T.truthy(ns.DisplayName(world.SECRET) == world.SECRET, "a secret value passes untouched")
    ns.Anon.Enable(true)
    T.eq(ns.DisplayName("Ran Fred"), "Ran Fred")
    ns.Anon.Enable(false)
    T.eq(calls, 0)
    T.eq(ns.DisplayName("Ran Fred"), "alias")
  end)

  T.it("redraws when the formatters change", function()
    local _, api, ns = World()
    local redraws = 0
    ns.On("NAMES", function() redraws = redraws + 1 end)
    local function fn() return "x" end
    api.RegisterNameFormatter("Test", fn)
    api.Refresh()
    api.UnregisterNameFormatter("Test")
    T.eq(redraws, 3)
  end)

  T.it("rejects bad arguments", function()
    local _, api = World()
    T.eq((pcall(api.RegisterNameFormatter, "", function() end)), false)
    T.eq((pcall(api.RegisterNameFormatter, "Test", "not a function")), false)
  end)

  T.it("draws the open chat tab with the new names", function()
    local world, api, ns = World()
    world.Fire("ADDON_LOADED", "Guildy")
    world.Fire("PLAYER_LOGIN")
    world.Fire("GUILD_ROSTER_UPDATE")
    world.RunTimers()
    ns.UI.Show()
    api.RegisterNameFormatter("Test", function(name) return name .. " (alias)" end)
    T.eq(world.errors, {})
  end)
end)
