-- The size of the window and its texts (options, general): a scale of the whole window, limited to
-- what fits the screen.
local T = ...

local function World(width, height)
  local world = dofile(T.testsDir .. "/wow.lua")(T, { width = width, height = height })
  world.Fire("ADDON_LOADED", "Guildy")
  world.Fire("PLAYER_LOGIN")
  world.Fire("GUILD_ROSTER_UPDATE")
  world.RunTimers()
  world.env.CommunitiesFrame:Show()
  return world
end

T.describe("Window size", function()
  T.it("sets the size with a slider in fine steps, once the mouse lets go", function()
    local world = World(3000, 2000)
    local ns = world.ns
    ns.UI.ShowOptions("general")
    local panel = ns.UI.Options().Panels.general
    T.eq(panel.ScaleValue:GetText(), "100%")
    local slider = panel.Scale
    slider:GetScript("OnValueChanged")(slider, 1.0731) -- dragging: the number follows, the window waits
    T.eq(panel.ScaleValue:GetText(), "108%")
    T.eq(ns.Settings().scale, nil)
    slider:GetScript("OnMouseUp")(slider)
    T.truthy(math.abs(ns.Settings().scale - 1.08) < 1e-9, tostring(ns.Settings().scale))
    T.eq(panel.ScaleValue:GetText(), "108%")
    slider:GetScript("OnValueChanged")(slider, 9) -- never beyond the slider's ends
    T.eq(panel.ScaleValue:GetText(), "150%")
    slider:GetScript("OnValueChanged")(slider, 0.1)
    T.eq(panel.ScaleValue:GetText(), "80%")
    ns.UI.SetScale(1)
    T.eq(ns.Settings().scale, nil) -- the game's own size is no setting
    ns.UI.SetScale("big")
    T.eq(ns.UI.Scale(), 1)
    T.eq(world.errors, {})
  end)

  T.it("offers no size at which the window would not fit the screen", function()
    local world = World(1500, 800) -- room for 1420 x 780: the smallest window fits 1.25 times
    local ns = world.ns
    ns.UI.ShowOptions("general")
    local panel = ns.UI.Options().Panels.general
    local slider = panel.Scale
    slider:GetScript("OnValueChanged")(slider, 1.5) -- the slider ends where the screen does
    T.eq(panel.ScaleValue:GetText(), "124%")
    ns.UI.SetScale(1.5) -- a saved size beyond that comes back to what fits
    T.truthy(ns.UI.Scale() < 1.26 and ns.UI.Scale() > 1.25, tostring(ns.UI.Scale()))
    T.eq(world.errors, {})
  end)

  T.it("ignores a saved size that is none", function()
    local world = World(3000, 2000)
    world.ns.Settings().scale = 40
    T.eq(world.ns.UI.Scale(), 1)
  end)
end)

-- A board that needs more rows makes the window taller instead of scrolling (UI/Board.lua)
T.describe("Window height follows the Bank tab", function()
  T.it("grows by the rows a box adds below, and gives them back", function()
    local world = World(3000, 2000)
    local ns = world.ns
    local UI = ns.UI
    UI.SelectTab("bank")
    local board = UI.TabView("bank").board
    T.eq(UI.frame:GetHeight(), 600)
    T.eq(board:Rows(), 12)
    local ch = board.ch
    T.eq(board:Insert("balance"), true)
    T.eq(board.placed.balance.y, 12)
    T.eq(board:Rows(), 18)
    T.eq(UI.frame:GetHeight(), 600 + 6 * ch)
    T.eq(ns.Settings().height, 600 + 6 * ch)
    -- (in the game the tab is as tall as the window lets it be, so a row keeps its height and the window
    -- comes back to exactly 600; the stubbed tab has one height whatever the window does)
    local tall, row = UI.frame:GetHeight(), board.ch
    board:Remove("balance")
    T.eq(board:Rows(), 12)
    T.eq(UI.frame:GetHeight(), tall - 6 * row)
    UI.GrowWindow(600 - UI.frame:GetHeight())
    -- never taller than the screen, never lower than the smallest window
    T.eq(UI.GrowWindow(5000), 1980 - 600)
    T.eq(UI.GrowWindow(-5000), UI.MIN_H - 1980)
    T.eq(UI.GrowWindow(0), 0)
    T.eq(world.errors, {})
  end)
end)
