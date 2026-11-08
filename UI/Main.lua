-- The Guildy window: ButtonFrameTemplate with portrait, a narrow icon bar on the left (guild,
-- Blizzard communities), the tab content area and bottom tabs. Resizable via a grip; size and
-- position are saved. Opening selects the tab that was open last in this session; every login or
-- reload starts on the chat tab.
local _, ns = ...
local W = ns.Widgets

local UI = {}
ns.UI = UI

local tabs = {}      -- {key, label, builder, button, panel, view}
local byKey = {}
local frame
local current
local lastTab -- session only, on purpose not in GuildyDB
local noGuild, forcedAccount -- without a guild only the account tab (UpdateGuildState)

local page    -- a page shown instead of a tab (UI.ShowPage); kept while the window is closed, so
              -- opening it again in this session comes back to the page

-- overview needs ~520 px height; the Hall of Fame's dungeon table needs ~1130 px width for all 32
-- dungeons and raids at 26 px each (UI/TabFame.lua)
UI.MIN_W, UI.MIN_H, UI.MAX_W, UI.MAX_H = 1130, 560, 1600, 1000

-- Tab modules call this at load time; builder(panel) returns a view with Refresh(event) and optional
-- OnShow() / OnHide(). side: no button in the bottom row (reached by a side tab, the account)
function UI.RegisterTab(key, order, label, builder, side)
  local tab = { key = key, order = order, label = label, builder = builder, side = side }
  tabs[#tabs + 1] = tab
  byKey[key] = tab
  table.sort(tabs, function(a, b) return a.order < b.order end)
end

-- Open / close sounds of Blizzard's guild window (SOUNDKIT 839 / 840)
local function PlayPanelSound(name, fallback)
  local kit = rawget(_G, "SOUNDKIT")
  local play = rawget(_G, "PlaySound")
  if play then pcall(play, kit and kit[name] or fallback) end
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
  -- a saved size outside the bounds (older versions, a jumped resize) comes back inside them
  frame:SetSize(math.min(UI.MAX_W, math.max(UI.MIN_W, settings.width or 1000)),
    math.min(UI.MAX_H, math.max(UI.MIN_H, settings.height or 600)))
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
  -- the template's close button calls HideUIPanel, which goes through Blizzard's protected panel
  -- manager and is blocked in combat; hide directly, like Escape does
  local close = frame.CloseButton or rawget(_G, "GuildyFrameCloseButton")
  if type(close) == "table" and close.SetScript then close:SetScript("OnClick", function() frame:Hide() end) end

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
  -- back from the account to the guild tab used last
  frame.GuildTab = SideTab(frame, W.LOGO, ns.L.ICON_GUILD, function() UI.SelectTab(UI.lastGuildTab or "chat") end)
  frame.GuildTab:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, -60)
  frame.GuildTab:SetChecked(true)
  frame.GuildTab.Emblem = TabEmblem(frame.GuildTab)
  -- the account under it: a group of characters (UI/TabAccount.lua)
  local accountIcon = "Interface\\Icons\\INV_Misc_GroupNeedMore"
  if not W.TextureExists(accountIcon) then accountIcon = "Interface\\Icons\\INV_Misc_Book_09" end
  frame.AccountTab = SideTab(frame, accountIcon, ns.L.ICON_ACCOUNT, function() UI.SelectTab("account") end)
  frame.AccountTab:SetChecked(false)
  UpdateTitle()

  -- content area (the portrait overlaps its top-left corner; tabs keep their first row clear of it)
  frame.Content = CreateFrame("Frame", nil, frame)
  frame.Content:SetPoint("TOPLEFT", 12, -30)
  frame.Content:SetPoint("BOTTOMRIGHT", -10, 12)

  local buttons = 0
  for _, tab in ipairs(tabs) do
    tab.panel = CreateFrame("Frame", nil, frame.Content)
    tab.panel:SetAllPoints()
    tab.panel:Hide()
    if not tab.side then
      buttons = buttons + 1
      tab.index = buttons
      tab.button = W.Tab(frame, buttons, tab.label, function() UI.SelectTab(tab.key) end)
    end
  end
  if rawget(_G, "PanelTemplates_SetNumTabs") then pcall(PanelTemplates_SetNumTabs, frame, buttons) end

  W.ResizeGrip(frame, function() SavePosition() end)
  frame:SetScript("OnSizeChanged", function()
    if current and current.view and current.view.OnResize then ns.SafeCall(current.view.OnResize, current.view) end
  end)
  frame:SetScript("OnHide", function()
    if UI.HideOverlay then UI.HideOverlay() end
    -- with a page open the tab was already told it is hidden
    if not page and current and current.view and current.view.OnHide then ns.SafeCall(current.view.OnHide, current.view) end
    if ns.Chat then ns.Chat.Focus(false) end
    PlayPanelSound("IG_CHARACTER_INFO_CLOSE", 840)
  end)
  frame:SetScript("OnShow", function()
    PlayPanelSound("IG_CHARACTER_INFO_OPEN", 839)
    if not page and current and current.view and current.view.OnShow then ns.SafeCall(current.view.OnShow, current.view) end
  end)
  UI.frame = frame
end

-- A page shown in the content area instead of a tab (the character page). It hides the current tab
-- and remembers it; selecting any tab hides the page again.
function UI.ShowPage(newPage)
  if not frame then UI.Show() end
  if page and page ~= newPage then page:Hide() end
  if current and current.panel:IsShown() then
    if current.view and current.view.OnHide then ns.SafeCall(current.view.OnHide, current.view) end
    current.panel:Hide()
  end
  page = newPage
  page:Show()
end

function UI.Content()
  if not frame then Build() end
  return frame.Content
end

function UI.SelectTab(key)
  if noGuild and byKey.account then key = "account" end
  local tab = byKey[key]
  if not tab or not frame then return end
  if page then
    page:Hide()
    page = nil
  end
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
  if key ~= "account" then UI.lastGuildTab = key end
  if frame.GuildTab then frame.GuildTab:SetChecked(key ~= "account") end
  if frame.AccountTab then frame.AccountTab:SetChecked(key == "account") end
  lastTab = key -- opening the window again in this session comes back here; a login or reload starts on chat
  tab.panel:Show()
  -- a side tab (account) leaves no bottom tab selected
  if rawget(_G, "PanelTemplates_SetTab") then pcall(PanelTemplates_SetTab, frame, tab.index or 0) end
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

-- Without a guild only the account tab makes sense: the other tab buttons go away and the window
-- shows the account. Joining a guild brings them back (and the chat, when the account tab was forced).
local function LayoutTabs()
  -- side tabs: guild and account; without a guild only the account, in the guild tab's place
  frame.GuildTab:SetShown(not noGuild)
  frame.AccountTab:ClearAllPoints()
  if noGuild then
    frame.AccountTab:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, -60)
  else
    frame.AccountTab:SetPoint("TOPLEFT", frame.GuildTab, "BOTTOMLEFT", 0, -8)
  end
  -- bottom row: hidden without a guild
  for i, tab in ipairs(tabs) do
    local button = tab.button
    if button then
      button:SetShown(not noGuild)
      if not button.anchored then
        button.anchored = true
        if tab.index == 1 then
          button:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, 2)
        else
          local previous = tabs[i - 1].button
          button:SetPoint("LEFT", previous, "RIGHT", -14, 0)
        end
      end
    end
  end
end

local function UpdateGuildState()
  if not frame then return end
  local was = noGuild
  noGuild = not IsInGuild()
  LayoutTabs()
  if not frame:IsShown() then return end
  if noGuild and UI.Current() ~= "account" then
    forcedAccount = true
    UI.SelectTab("account")
  elseif was and not noGuild and forcedAccount then
    forcedAccount = nil
    UI.SelectTab("chat")
  end
end

function UI.Show()
  if not frame then Build() end
  UpdateTitle()
  if ns.Roster then ns.Roster.Request() end
  frame:Show()
  noGuild = not IsInGuild()
  LayoutTabs()
  if noGuild then
    forcedAccount = UI.Current() ~= "account" or forcedAccount
    UI.SelectTab("account")
    return
  end
  -- back to where the window was left in this session: the open page (character page) or the tab
  if page then
    page:Show()
    if page.Render then ns.SafeCall(page.Render, page) end
    return
  end
  UI.SelectTab(byKey[lastTab] and lastTab or "chat")
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
for _, event in ipairs({ "ROSTER", "PROFS", "CHAT", "INFO", "HARVEST", "STATS", "USERS", "FAMILY", "GUILD" }) do
  ns.On(event, function(...) Refresh(event, ...) end)
end
ns.On("ROSTER", function() if frame then UpdateTitle() end end)
ns.On("GUILD", function()
  if not frame then return end
  UpdateTitle()
  UpdateGuildState()
end)

-- Shows the members tab with a filter (from overview bars)
function UI.FilterMembers(filter)
  UI.SelectTab("members")
  local tab = byKey.members
  if tab and tab.view and tab.view.SetFilter then tab.view:SetFilter(filter) end
end
