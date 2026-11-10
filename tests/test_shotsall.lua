-- /guildy shots all in the loaded addon: language by language over interface reloads (the stub counts
-- them, nothing reloads), waiting for the player to open Guildy, and always putting things back.
local T = ...
local NOW = 1700000000 -- the stub's GetServerTime

local function World(db, more)
  local opts = more or {}
  opts.setup = function(env) env.GuildyDB = db end
  local world = dofile(T.testsDir .. "/wow.lua")(T, opts)
  world.taken = 0
  world.env.Screenshot = function() world.taken = world.taken + 1 end
  world.Start = function()
    world.Fire("ADDON_LOADED", "Guildy")
    world.Fire("PLAYER_LOGIN")
    world.Fire("GUILD_ROSTER_UPDATE")
    world.RunTimers()
  end
  world.OpenGuildy = function() world.env.CommunitiesFrame:Show() end -- J
  return world
end

local function Running(queue, touched)
  return { settings = { language = "ruRU", width = 1300, height = 700 },
    shotRun = { queue = queue, language = false, width = 1300, height = 700, touched = touched or NOW } }
end

T.describe("Shots in all languages", function()
  T.it("starts with the first language", function()
    local world = World(nil)
    world.Start()
    local ns = world.ns
    world.env.SlashCmdList.GUILDY("shots all")
    T.eq(ns.Settings().language, "enUS")
    T.eq(#ns.DB().shotRun.queue, #ns.Locale.Languages() - 1)
    T.eq(world.calls.reloads, 1)
    world.env.SlashCmdList.GUILDY("shots all") -- a second one while it runs: refused
    T.eq(world.calls.reloads, 1)
    T.eq(world.errors, {})
  end)

  T.it("continues after a reload once Guildy is open, at the smallest size", function()
    local world = World(Running({ "ptBR" }))
    world.Start()
    local ns = world.ns
    T.eq(ns.Locale.current, "ruRU")
    world.RunTimers(10)
    T.eq(world.taken, 0) -- waits for J
    world.OpenGuildy()
    world.RunTimers(10)
    T.eq(world.taken, #ns.UI.SHOTS)
    T.eq({ ns.UI.frame:GetWidth(), ns.UI.frame:GetHeight() }, { ns.UI.MIN_W, ns.UI.MIN_H })
    T.eq(ns.Settings().width, 1300) -- the run's size is not saved
    T.eq(ns.Settings().language, "ptBR")
    T.eq(world.calls.reloads, 1)
    T.eq(world.errors, {})
  end)

  T.it("ends after the last language and restores language and size", function()
    local world = World(Running({}))
    world.Start()
    local ns = world.ns
    world.OpenGuildy()
    world.RunTimers(10)
    T.eq(world.taken, #ns.UI.SHOTS)
    T.eq(ns.Settings().language, nil)
    T.eq({ ns.Settings().width, ns.Settings().height }, { 1300, 700 })
    T.eq({ ns.UI.frame:GetWidth(), ns.UI.frame:GetHeight() }, { 1300, 700 })
    T.eq(ns.DB().shotRun, nil)
    T.eq(world.calls.reloads, 1) -- back to the client's language
    T.eq(world.errors, {})
  end)

  T.it("drops a cut-off run without reloading", function()
    local world = World(Running({ "ptBR" }, NOW - 181))
    world.Start()
    local ns = world.ns
    T.eq(ns.Locale.current, "deDE") -- the language from before the run, in force right away
    T.eq(ns.Settings().language, nil)
    T.eq(ns.DB().shotRun, nil)
    world.OpenGuildy()
    world.RunTimers(10)
    T.eq(world.taken, 0)
    T.eq(world.calls.reloads, nil)
    T.eq(world.errors, {})
  end)

  T.it("gives up when Guildy is not opened", function()
    local world = World(Running({ "ptBR" }))
    world.Start()
    world.RunTimers(130)
    T.eq(world.taken, 0)
    T.eq(world.ns.Settings().language, nil)
    T.eq(world.ns.DB().shotRun, nil)
    T.eq(world.calls.reloads, 1)
    T.eq(world.errors, {})
  end)

  T.it("gives up without a guild roster", function()
    local world = World(Running({ "ptBR" }), { roster = {} })
    world.Start()
    world.OpenGuildy()
    world.RunTimers(30)
    T.eq(world.taken, 0)
    T.eq(world.ns.Settings().language, nil)
    T.eq(world.ns.DB().shotRun, nil)
    T.eq(world.errors, {})
  end)

  T.it("stops on request, also in the middle of the pictures", function()
    local world = World(Running({ "ptBR" }))
    world.Start()
    local ns = world.ns
    world.OpenGuildy()
    world.RunTimers(1) -- the pictures are scheduled
    world.env.SlashCmdList.GUILDY("shots stop")
    T.eq(ns.DB().shotRun, nil)
    T.eq(ns.Settings().language, nil)
    world.RunTimers(10)
    T.eq(world.taken, 0)
    T.eq(ns.Settings().language, nil) -- the stopped pictures do not move on to the next language
    T.eq(world.errors, {})
  end)

  T.it("leaves language and size alone for the plain run", function()
    local world = World({ settings = { width = 1300, height = 700 } })
    world.Start()
    local ns = world.ns
    world.OpenGuildy()
    world.env.SlashCmdList.GUILDY("shots")
    world.RunTimers(3)
    T.eq(world.taken, #ns.UI.SHOTS)
    T.eq(ns.Settings().language, nil)
    T.eq(ns.UI.frame:GetWidth(), 1300)
    T.eq(world.calls.reloads, nil)
    T.eq(world.errors, {})
  end)
end)
