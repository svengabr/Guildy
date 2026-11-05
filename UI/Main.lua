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

-- Round side button in a column left of the window, like the server list in Discord, drawn with
-- Blizzard parts: round icon in a gold ring (minimap button style), a gold bar on the left edge for the
-- current place (tall) and on hover (short), ring glow on hover.
local TAB_SIZE = 40

local function SideTab(parent, texture, tooltip, onClick)
  local tab = CreateFrame("CheckButton", nil, parent)
  tab:SetSize(TAB_SIZE, TAB_SIZE)
  tab.Back = tab:CreateTexture(nil, "BACKGROUND")
  tab.Back:SetPoint("TOPLEFT", 2, -2)
  tab.Back:SetPoint("BOTTOMRIGHT", -2, 2)
  tab.Back:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
  tab.Back:SetVertexColor(0.08, 0.07, 0.05, 1)
  if texture then
    tab.Icon = tab:CreateTexture(nil, "ARTWORK")
    tab.Icon:SetPoint("TOPLEFT", 4, -4)
    tab.Icon:SetPoint("BOTTOMRIGHT", -4, 4)
    tab.Icon:SetTexture(texture)
    local mask = tab.CreateMaskTexture and tab:CreateMaskTexture()
    if mask then
      mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      mask:SetAllPoints(tab.Icon)
      tab.Icon:AddMaskTexture(mask)
    end
  end
  -- ring, glow and bar on their own layer above anything placed in the button (the guild emblem)
  tab.Over = CreateFrame("Frame", nil, tab)
  tab.Over:SetAllPoints()
  tab.Over:SetFrameLevel(tab:GetFrameLevel() + 10)
  tab.Over.Ring = tab.Over:CreateTexture(nil, "OVERLAY", nil, 1)
  tab.Over.Ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  tab.Over.Ring:SetSize(TAB_SIZE * 54 / 32, TAB_SIZE * 54 / 32)
  tab.Over.Ring:SetPoint("TOPLEFT", -1, 1)
  tab.Over.Hover = tab.Over:CreateTexture(nil, "OVERLAY", nil, 2)
  tab.Over.Hover:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  tab.Over.Hover:SetBlendMode("ADD")
  tab.Over.Hover:SetAllPoints()
  tab.Over.Hover:Hide()
  tab.Bar = tab.Over:CreateTexture(nil, "OVERLAY", nil, 3)
  tab.Bar:SetColorTexture(1, 0.82, 0, 1)
  tab.Bar:SetWidth(4)
  tab.Bar:SetPoint("RIGHT", tab, "LEFT", -4, 0)
  tab.Bar:Hide()
  local function UpdateBar(self)
    if self:GetChecked() then
      self.Bar:SetHeight(TAB_SIZE - 6)
      self.Bar:Show()
    elseif self.hovered then
      self.Bar:SetHeight(12)
      self.Bar:Show()
    else
      self.Bar:Hide()
    end
  end
  function tab:SetHover(on)
    self.hovered = on
    self.Over.Hover:SetShown(on)
    UpdateBar(self)
  end
  hooksecurefunc(tab, "SetChecked", function(self) UpdateBar(self) end)
  tab:SetScript("OnClick", function(self)
    self:SetChecked(self.keepChecked or false)
    if onClick then onClick(self) end
  end)
  W.Tooltip(tab, tooltip)
  tab:HookScript("OnEnter", function(self) self:SetHover(true) end)
  tab:HookScript("OnLeave", function(self) self:SetHover(false) end)
  return tab
end

-- The guild's emblem drawn with Blizzard's SetLargeGuildTabardTextures (background, emblem, border).
-- holder.ok is false when the client lacks the function (then the caller keeps its own icon).
function UI.GuildEmblem(parent, size)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(size, size)
  holder.Background = holder:CreateTexture(nil, "BACKGROUND", nil, 1)
  holder.Background:SetTexture("Interface\\GuildFrame\\GuildFrame")
  holder.Background:SetTexCoord(0.63183594, 0.69238281, 0.61914063, 0.74023438)
  holder.Background:SetAllPoints()
  holder.Emblem = holder:CreateTexture(nil, "BACKGROUND", nil, 2)
  holder.Emblem:SetSize(size * 56 / 60, size * 64 / 60)
  holder.Emblem:SetPoint("CENTER", holder, "TOPLEFT", size * 30 / 60, -size * 31 / 60)
  holder.Border = holder:CreateTexture(nil, "BACKGROUND", nil, 3)
  holder.Border:SetTexture("Interface\\GuildFrame\\GuildFrame")
  holder.Border:SetTexCoord(0.63183594, 0.69238281, 0.74414063, 0.86523438)
  holder.Border:SetPoint("TOPLEFT", 0, -1)
  holder.Border:SetSize(size, size * 59 / 60)
  local mask = holder.CreateMaskTexture and holder:CreateMaskTexture()
  if mask then
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints()
    for _, texture in ipairs({ holder.Background, holder.Emblem, holder.Border }) do texture:AddMaskTexture(mask) end
  end
  function holder:Update()
    local set = rawget(_G, "SetLargeGuildTabardTextures")
    self.ok = set ~= nil and IsInGuild() and (pcall(set, "player", self.Emblem, self.Background, self.Border)) or false
    self:SetShown(self.ok)
  end
  holder:Update()
  return holder
end

local function UpdateTitle()
  local guildName = IsInGuild() and GetGuildInfo("player") or nil
  local title = guildName and (guildName .. " · Guildy") or "Guildy"
  if frame.SetTitle then frame:SetTitle(title) elseif frame.TitleText then frame.TitleText:SetText(title) end
  if frame.Emblem then frame.Emblem:Update() end
  if frame.GuildTab and frame.GuildTab.Emblem then frame.GuildTab.Emblem:Update() end
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
  frame:SetClampRectInsets(-(TAB_SIZE + 14), 0, 0, 0) -- keep the button column left of the window on screen
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

  -- guild emblem in the portrait (Blizzard's own drawing; the grey helmet when the guild has none)
  frame.Emblem = UI.GuildEmblem(frame, 60)
  frame.Emblem:SetPoint("TOPLEFT", -5, 8)
  frame.Emblem:SetFrameLevel(frame:GetFrameLevel() + 300)
  if frame.Emblem.ok then
    local portrait = frame.PortraitContainer and frame.PortraitContainer.portrait or frame.portrait
    if portrait then portrait:SetAlpha(0) end
  end

  -- round buttons in a column left of the window (like Discord's server list): Guildy, Blizzard's window
  frame.GuildTab = SideTab(frame, nil, ns.L.ICON_GUILD, function() UI.SelectTab("chat") end)
  frame.GuildTab:SetPoint("TOPRIGHT", frame, "TOPLEFT", -6, -66)
  frame.GuildTab.Emblem = UI.GuildEmblem(frame.GuildTab, TAB_SIZE - 6)
  frame.GuildTab.Emblem:SetPoint("CENTER")
  frame.GuildTab.keepChecked = true
  frame.GuildTab:SetChecked(true)
  if not frame.GuildTab.Emblem.ok then
    frame.GuildTab.Emblem:Hide()
    local icon = frame.GuildTab:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 4, -4)
    icon:SetPoint("BOTTOMRIGHT", -4, 4)
    icon:SetTexture(W.LOGO)
  end
  frame.CommunitiesTab = SideTab(frame, "Interface\\Icons\\achievement_guildperk_havegroup willtravel", ns.L.ICON_COMMUNITIES)
  frame.CommunitiesTab:SetPoint("TOP", frame.GuildTab, "BOTTOM", 0, -10)
  UI.SecureAction(frame.CommunitiesTab, UI.Action.BlizzardWindow, ns.L.ICON_COMMUNITIES)
  UpdateTitle()

  -- content area (the portrait overlaps its top-left corner; tabs keep their first row clear of it)
  frame.Content = CreateFrame("Frame", nil, frame)
  frame.Content:SetPoint("TOPLEFT", 12, -30)
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
