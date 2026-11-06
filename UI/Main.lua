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

UI.MIN_W, UI.MIN_H, UI.MAX_W, UI.MAX_H = 960, 560, 1600, 1000 -- overview needs ~520 px

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

-- Side tab exactly like the ones on Blizzard's profession window (LargeSideTabButtonTemplate: rounded tab
-- art, gold frame when selected, hover art), sitting outside the right edge. Falls back to the classic
-- spellbook side tab when the template is missing. tab.sideTab marks it for tooltips beside the tab.
local function SideTab(parent, texture, tooltip, onClick)
  local ok, tab = pcall(CreateFrame, "Frame", nil, parent, "LargeSideTabButtonTemplate")
  if ok and tab and tab.Icon then
    tab.tooltipText = tooltip
    if tab.SetFillToInterior then tab:SetFillToInterior(true) end
    if texture then tab.Icon:SetTexture(texture) end
    if tab.SetCustomOnMouseUpHandler then
      tab:SetCustomOnMouseUpHandler(function(self, button, upInside)
        if button == "LeftButton" and upInside ~= false and onClick then onClick(self) end
      end)
    end
    -- lit from the outside while the secure overlay covers it (UI/Commands.lua)
    function tab:SetHover(on)
      if not self.HighlightTexture then return end
      self.HighlightTexture:SetDrawLayer(on and "OVERLAY" or "HIGHLIGHT")
      self.HighlightTexture:SetShown(true)
    end
  else
    tab = CreateFrame("CheckButton", nil, parent)
    tab:SetSize(32, 32)
    local back = tab:CreateTexture(nil, "BACKGROUND")
    back:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
    back:SetSize(64, 64)
    back:SetPoint("TOPLEFT", -3, 11)
    tab.Icon = tab:CreateTexture(nil, "ARTWORK")
    tab.Icon:SetAllPoints()
    if texture then tab.Icon:SetTexture(texture) end
    tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    tab:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight", "ADD")
    tab:SetScript("OnClick", function(self)
      self:SetChecked(self.keepChecked or false)
      if onClick then onClick(self) end
    end)
    W.Tooltip(tab, tooltip)
  end
  tab.sideTab = true
  return tab
end

-- The guild emblem drawn into a side tab's icon spot, clipped by the tab's own mask
local function TabEmblem(tab)
  local size = 46
  local bg = tab:CreateTexture(nil, "ARTWORK", nil, 1)
  bg:SetTexture("Interface\\GuildFrame\\GuildFrame")
  bg:SetTexCoord(0.63183594, 0.69238281, 0.61914063, 0.74023438)
  bg:SetSize(size, size)
  bg:SetPoint("CENTER", tab.Icon, "CENTER")
  local emblem = tab:CreateTexture(nil, "ARTWORK", nil, 2)
  emblem:SetSize(size * 56 / 60, size * 64 / 60)
  emblem:SetPoint("CENTER", tab.Icon, "CENTER", 0, -1)
  local border = tab:CreateTexture(nil, "ARTWORK", nil, 3)
  border:SetTexture("Interface\\GuildFrame\\GuildFrame")
  border:SetTexCoord(0.63183594, 0.69238281, 0.74414063, 0.86523438)
  border:SetSize(size, size * 59 / 60)
  border:SetPoint("CENTER", tab.Icon, "CENTER")
  if tab.Mask then
    for _, texture in ipairs({ bg, emblem, border }) do texture:AddMaskTexture(tab.Mask) end
  end
  local holder = { Background = bg, Emblem = emblem, Border = border }
  function holder:Update()
    local set = rawget(_G, "SetLargeGuildTabardTextures")
    self.ok = set ~= nil and IsInGuild() and (pcall(set, "player", self.Emblem, self.Background, self.Border)) or false
    for _, texture in ipairs({ self.Background, self.Emblem, self.Border }) do texture:SetShown(self.ok) end
    tab.Icon:SetShown(not self.ok)
  end
  holder:Update()
  return holder
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
  frame:SetSize(math.max(UI.MIN_W, settings.width or 1000), math.max(UI.MIN_H, settings.height or 600))
  local p = settings.point
  if type(p) == "table" and p[1] then
    frame:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
  else
    frame:SetPoint("CENTER", 0, 40)
  end
  frame:SetFrameStrata("HIGH")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:SetClampRectInsets(0, 60, 0, 0) -- keep the side tabs right of the window on screen
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

  -- side tab outside the right edge, exactly like Blizzard's profession window: Guildy with the guild
  -- emblem. (A communities tab was dropped: creating communities is broken on Forever; Blizzard's guild
  -- window stays reachable from the member menu, the info tab and the micro menu.)
  frame.GuildTab = SideTab(frame, W.LOGO, ns.L.ICON_GUILD, function() UI.SelectTab("chat") end)
  frame.GuildTab:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, -60)
  frame.GuildTab.keepChecked = true
  frame.GuildTab:SetChecked(true)
  frame.GuildTab.Emblem = TabEmblem(frame.GuildTab)
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

-- The view of a tab once it was built (tests, cross-tab calls)
function UI.TabView(key)
  local tab = byKey[key]
  return tab and tab.view
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
for _, event in ipairs({ "ROSTER", "PROFS", "CHAT", "INFO", "HARVEST", "STATS" }) do
  ns.On(event, function(...) Refresh(event, ...) end)
end
ns.On("ROSTER", function() if frame then UpdateTitle() end end)

-- Shows the members tab with member m selected (from the ranks tab)
function UI.ShowMember(m)
  UI.SelectTab("members")
  local tab = byKey.members
  if tab and tab.view and tab.view.Select then tab.view:Select(m) end
end

-- Shows the members tab with a filter (from overview bars)
function UI.FilterMembers(filter)
  UI.SelectTab("members")
  local tab = byKey.members
  if tab and tab.view and tab.view.SetFilter then tab.view:SetFilter(filter) end
end
