-- The Guildy window: ButtonFrameTemplate with portrait, a narrow icon bar on the left (guild,
-- Blizzard communities), the tab content area and bottom tabs. Resizable via a grip; size and
-- position are saved. Opening always selects the chat tab.
local _, ns = ...
local W = ns.Widgets

local UI = {}
ns.UI = UI

local tabs = {}      -- {key, label, builder, button, panel, view}
local byKey = {}
local frame
local current

UI.MIN_W, UI.MIN_H, UI.MAX_W, UI.MAX_H = 860, 440, 1600, 1000

-- Tab modules call this at load time; builder(panel) returns a view with Refresh(event) and optional
-- OnShow() / OnHide()
function UI.RegisterTab(key, order, label, builder)
  local tab = { key = key, order = order, label = label, builder = builder }
  tabs[#tabs + 1] = tab
  byKey[key] = tab
  table.sort(tabs, function(a, b) return a.order < b.order end)
end

local function SavePosition()
  local settings = ns.Settings()
  local point, _, relPoint, x, y = frame:GetPoint(1)
  settings.point = { point, relPoint, x, y }
  settings.width, settings.height = frame:GetWidth(), frame:GetHeight()
end

local function ApplyBounds()
  if frame.SetResizeBounds then
    frame:SetResizeBounds(UI.MIN_W, UI.MIN_H, UI.MAX_W, UI.MAX_H)
  else
    if frame.SetMinResize then frame:SetMinResize(UI.MIN_W, UI.MIN_H) end
    if frame.SetMaxResize then frame:SetMaxResize(UI.MAX_W, UI.MAX_H) end
  end
end

local function IconButton(parent, texture, tooltip, onClick)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(36, 36)
  button.Icon = button:CreateTexture(nil, "ARTWORK")
  button.Icon:SetAllPoints()
  button.Icon:SetTexture(texture)
  button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  button.Border = button:CreateTexture(nil, "OVERLAY")
  button.Border:SetPoint("TOPLEFT", -3, 3)
  button.Border:SetPoint("BOTTOMRIGHT", 3, -3)
  button.Border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  button.Border:SetBlendMode("ADD")
  button.Border:SetVertexColor(0.3, 1, 0.3)
  button.Border:Hide()
  button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  button:SetScript("OnClick", onClick)
  W.Tooltip(button, tooltip)
  return button
end

local function UpdateTitle()
  local guildName = IsInGuild() and GetGuildInfo("player") or nil
  local title = guildName and (guildName .. " · Guildy") or "Guildy"
  if frame.SetTitle then frame:SetTitle(title) elseif frame.TitleText then frame.TitleText:SetText(title) end
end

local function Build()
  frame = CreateFrame("Frame", "GuildyFrame", UIParent, "ButtonFrameTemplate")
  local settings = ns.Settings()
  frame:SetSize(math.max(UI.MIN_W, settings.width or 1000), math.max(UI.MIN_H, settings.height or 520))
  local p = settings.point
  if type(p) == "table" and p[1] then
    frame:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
  else
    frame:SetPoint("CENTER", 0, 40)
  end
  frame:SetFrameStrata("HIGH")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:SetResizable(true)
  ApplyBounds()
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
  end)
  if frame.SetPortraitToAsset then
    frame:SetPortraitToAsset(W.LOGO)
  elseif frame.portrait then
    frame.portrait:SetTexture(W.LOGO)
  end
  if rawget(_G, "ButtonFrameTemplate_HideButtonBar") then ButtonFrameTemplate_HideButtonBar(frame) end
  if frame.Inset then frame.Inset:Hide() end
  tinsert(UISpecialFrames, "GuildyFrame")
  UpdateTitle()

  -- icon bar (below the portrait)
  local bar = CreateFrame("Frame", nil, frame)
  bar:SetPoint("TOPLEFT", 10, -66)
  bar:SetPoint("BOTTOMLEFT", 10, 12)
  bar:SetWidth(40)
  frame.GuildButton = IconButton(bar, W.LOGO, ns.L.ICON_GUILD, function() UI.SelectTab("chat") end)
  frame.GuildButton:SetPoint("TOP", 0, 0)
  frame.GuildButton.Border:Show()
  frame.CommunitiesButton = IconButton(bar, "Interface\\Icons\\INV_Letter_15", ns.L.ICON_COMMUNITIES)
  UI.SecureAction(frame.CommunitiesButton, UI.Action.BlizzardWindow, ns.L.ICON_COMMUNITIES)
  frame.CommunitiesButton:SetPoint("TOP", frame.GuildButton, "BOTTOM", 0, -10)

  -- content area
  frame.Content = CreateFrame("Frame", nil, frame)
  frame.Content:SetPoint("TOPLEFT", 58, -30)
  frame.Content:SetPoint("BOTTOMRIGHT", -10, 12)

  for i, tab in ipairs(tabs) do
    tab.panel = CreateFrame("Frame", nil, frame.Content)
    tab.panel:SetAllPoints()
    tab.panel:Hide()
    tab.button = W.Tab(frame, i, tab.label, function() UI.SelectTab(tab.key) end)
    if i == 1 then
      tab.button:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, 2)
    else
      tab.button:SetPoint("LEFT", tabs[i - 1].button, "RIGHT", -14, 0)
    end
  end
  if rawget(_G, "PanelTemplates_SetNumTabs") then pcall(PanelTemplates_SetNumTabs, frame, #tabs) end

  W.ResizeGrip(frame, function() SavePosition() end)
  frame:SetScript("OnSizeChanged", function()
    if current and current.view and current.view.OnResize then ns.SafeCall(current.view.OnResize, current.view) end
  end)
  frame:SetScript("OnHide", function()
    if UI.HideOverlay then UI.HideOverlay() end
    if current and current.view and current.view.OnHide then ns.SafeCall(current.view.OnHide, current.view) end
    if ns.Chat then ns.Chat.Focus(false) end
  end)
  frame:SetScript("OnShow", function()
    if current and current.view and current.view.OnShow then ns.SafeCall(current.view.OnShow, current.view) end
  end)
  UI.frame = frame
end

function UI.SelectTab(key)
  local tab = byKey[key]
  if not tab or not frame then return end
  if current and current ~= tab then
    if current.view and current.view.OnHide then ns.SafeCall(current.view.OnHide, current.view) end
    current.panel:Hide()
  end
  if not tab.view then
    local ok, view = pcall(tab.builder, tab.panel)
    if not ok then
      ns.SafeCall(error, view)
      view = {}
    end
    tab.view = view or {}
  end
  current = tab
  tab.panel:Show()
  for i, t in ipairs(tabs) do
    if t == tab and rawget(_G, "PanelTemplates_SetTab") then pcall(PanelTemplates_SetTab, frame, i) end
  end
  if tab.view.OnShow then ns.SafeCall(tab.view.OnShow, tab.view) end
  if tab.view.Refresh then ns.SafeCall(tab.view.Refresh, tab.view) end
end

function UI.Current()
  return current and current.key
end

function UI.Show()
  if not frame then Build() end
  UpdateTitle()
  if ns.Roster then ns.Roster.Request() end
  frame:Show()
  UI.SelectTab("chat")
end

function UI.Hide()
  if frame then frame:Hide() end
end

function UI.Toggle()
  if frame and frame:IsShown() then UI.Hide() else UI.Show() end
end

function UI.IsShown()
  return frame and frame:IsShown() or false
end

-- Data changes refresh the visible tab
local function Refresh(event, ...)
  if not UI.IsShown() or not current or not current.view or not current.view.Refresh then return end
  ns.SafeCall(current.view.Refresh, current.view, event, ...)
end
for _, event in ipairs({ "ROSTER", "PROFS", "CHAT", "INFO", "HARVEST" }) do
  ns.On(event, function(...) Refresh(event, ...) end)
end
ns.On("ROSTER", function() if frame then UpdateTitle() end end)

-- Shows the members tab with a filter (from overview bars)
function UI.FilterMembers(filter)
  UI.SelectTab("members")
  local tab = byKey.members
  if tab and tab.view and tab.view.SetFilter then tab.view:SetFilter(filter) end
end
