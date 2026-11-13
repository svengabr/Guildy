-- The shared activity score panel (UI/ScorePanel.lua): built once, filled on show, used on the
-- character page's score tile, the members tab's score cells and the overview's member lists.
local T = ...

local DETAIL = { rates = { kills = 120, quests = 14 }, presence = 2.5, chars = { "au tsch" }, fromDay = 20400, toDay = 20408 }

local function World()
  local w = dofile(T.testsDir .. "/wow.lua")(T)
  w.Fire("ADDON_LOADED", "Guildy")
  w.Fire("PLAYER_LOGIN")
  w.Fire("GUILD_ROSTER_UPDATE")
  w.RunTimers()
  w.env.CommunitiesFrame:Show()
  -- Au Tsch has 60, Ran Fred 35, Makira none
  local scores = { ["au tsch"] = 60, ["ran fred"] = 35 }
  w.ns.GameActivity.ScoreOf = function(key)
    local score = scores[key]
    if not score then return nil end
    return score, { presence = 15, playing = score - 15 }, DETAIL
  end
  function w.Panel() return w.ns.UI.ScorePanel.Frame() end
  return w
end

-- the members tab with the score column shown, and the row of key
local function MembersRow(w, key)
  w.ns.UI.SelectTab("members")
  local view = w.ns.UI.TabView("members")
  view:SetFilter({ scoreBucket = w.ns.Activity.Bucket(60) }) -- shows the score column
  for _, row in pairs(view.List.rows) do
    if row.member and row.member.key == key and row:IsShown() then return row, view end
  end
end

T.describe("Shared activity score panel", function()
  T.it("shows the panel with that member's score when the mouse enters a members tab score cell", function()
    local w = World()
    local row = MembersRow(w, "au tsch")
    T.truthy(row, "Au Tsch listed")
    T.eq(row.ScoreHit:IsShown(), true)
    row.ScoreHit:GetScript("OnEnter")(row.ScoreHit)
    local panel = w.Panel()
    T.truthy(panel and panel:IsShown(), "shown")
    T.eq(panel.Value:GetText(), "60")
    T.truthy(panel.Intro:GetText():find("Au Tsch", 1, true), panel.Intro:GetText())
    row.ScoreHit:GetScript("OnLeave")(row.ScoreHit)
    T.eq(panel:IsShown(), false)
    T.eq(w.errors, {})
  end)

  T.it("keeps the row tooltip for the rest of the row and the click on the score cell", function()
    local w = World()
    local row = MembersRow(w, "au tsch")
    local tipped, clicked
    local tooltip, click = w.ns.UI.MemberTooltip, w.ns.UI.MemberClick
    w.ns.UI.MemberTooltip = function(_, m) tipped = m.key end
    w.ns.UI.MemberClick = function(m) clicked = m.key end
    row:GetScript("OnEnter")(row)
    row.ScoreHit:GetScript("OnMouseUp")(row.ScoreHit, "LeftButton")
    w.ns.UI.MemberTooltip, w.ns.UI.MemberClick = tooltip, click
    T.eq(tipped, "au tsch")
    T.eq(clicked, "au tsch")
    T.eq(w.errors, {})
  end)

  T.it("shows the panel for a member of the overview's comings and goings", function()
    local w = World()
    local box = w.ns.UI.OverviewChangesBox(w.env.UIParent)
    box.List:SetItems({ { kind = "join", name = "Ran Fred", daysAgo = 3 } })
    local row = box.List.rows[1]
    row:GetScript("OnEnter")(row)
    local panel = w.Panel()
    T.truthy(panel and panel:IsShown(), "shown")
    T.eq(panel.Value:GetText(), "35")
    row:GetScript("OnLeave")(row)
    T.eq(panel:IsShown(), false)
    T.eq(w.errors, {})
  end)

  T.it("is built once and reused for every member and place", function()
    local w = World()
    local row = MembersRow(w, "au tsch")
    row.ScoreHit:GetScript("OnEnter")(row.ScoreHit)
    local first = w.Panel()
    w.ns.UI.ShowMember(w.ns.Roster.Find("Ran Fred"))
    local page = w.ns.UI.MemberPage()
    page.Tiles.score:GetScript("OnEnter")(page.Tiles.score)
    T.truthy(w.Panel() == first, "the same frame")
    T.eq(first.Value:GetText(), "35")
    T.truthy(page.ScorePanel == first, "the character page's tile shows it")
    page.Tiles.score:GetScript("OnLeave")(page.Tiles.score)
    T.eq(first:IsShown(), false)
    T.eq(w.errors, {})
  end)
end)
