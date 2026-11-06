-- Small UI toolkit shared with Raidy and KeepOrSell (same author): dark boxes with a gold border,
-- Morpheus headings, Blizzard atlases with a plain fallback, a pooled scroll list, a lightweight
-- dropdown menu and bottom tabs. Guildy additions at the end: bars, segmented control, resize grip.
local _, ns = ...

local W = {}
ns.Widgets = W

W.LOGO = "Interface\\Icons\\INV_Shirt_GuildTabard_01"
-- Morpheus has no Cyrillic glyphs; the client's quest title font is Morpheus in western clients and the
-- matching Cyrillic face in ruRU, so take it from there.
W.HEADER_FONT = (QuestTitleFont and QuestTitleFont.GetFont and QuestTitleFont:GetFont()) or "Fonts\\MORPHEUS.TTF"
W.GOLD = { 0.79, 0.64, 0.29 }
W.PARCHMENT = { 0.95, 0.89, 0.71 }
W.ICON_YES = "Interface\\RaidFrame\\ReadyCheck-Ready"
W.ICON_NO = "Interface\\RaidFrame\\ReadyCheck-NotReady"
W.ICON_WAIT = "Interface\\RaidFrame\\ReadyCheck-Waiting"

local BACKDROP = {
  bgFile = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- Dark box with a gold-tinted border, like the panels of the quest log
function W.Box(parent, shade, border)
  local box = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  shade, border = shade or 0.08, border or 0.7
  if box.SetBackdrop then
    box:SetBackdrop(BACKDROP)
    box:SetBackdropColor(shade, shade * 0.85, shade * 0.6, 0.95)
    box:SetBackdropBorderColor(W.GOLD[1] * border, W.GOLD[2] * border, W.GOLD[3] * border)
  end
  return box
end

function W.SetAtlasOr(texture, atlas, r, g, b)
  if C_Texture and C_Texture.GetAtlasExists and C_Texture.GetAtlasExists(atlas) then
    texture:SetAtlas(atlas)
  else
    texture:SetColorTexture(r, g, b, 0.8)
  end
end

-- Whether a texture file ships with the client; unknown (no GetFileIDFromPath) counts as yes
function W.TextureExists(path)
  local lookup = rawget(_G, "GetFileIDFromPath")
  if not lookup then return true end
  local ok, id = pcall(lookup, path)
  return ok and id ~= nil
end

-- Small square button with an icon (header menu): looks like a panel button, tooltip on hover
function W.IconButton(parent, texture, size, onClick, title, tip)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetSize(size or 28, size or 28)
  button:SetText("")
  button.Icon = button:CreateTexture(nil, "OVERLAY")
  button.Icon:SetSize((size or 28) - 10, (size or 28) - 10)
  button.Icon:SetPoint("CENTER")
  button.Icon:SetTexture(texture)
  button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  button:SetScript("OnClick", onClick)
  if title then W.Tooltip(button, title, tip) end
  return button
end

-- Heading in the quest book font with an ornamental divider below
function W.Heading(parent, text, size, width)
  local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  label:SetFont(W.HEADER_FONT, size or 16, "")
  label:SetTextColor(unpack(W.PARCHMENT))
  label:SetText(text)
  local divider = parent:CreateTexture(nil, "ARTWORK")
  W.SetAtlasOr(divider, "Campaign-QuestLog-LoreDivider", unpack(W.GOLD))
  divider:SetSize(width or 300, (size or 16) > 16 and 10 or 6)
  divider:SetPoint("TOP", label, "BOTTOM", 0, -2)
  label.Divider = divider
  return label
end

function W.Text(parent, template, text)
  local label = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
  label:SetJustifyH("LEFT")
  if text then label:SetText(text) end
  return label
end

-- Width in px of the widest of texts in a font (a font object or its global name), at least min,
-- plus pad. Measured on one hidden font string; 0 for texts the client can't measure.
local measure
function W.FitWidth(font, texts, min, pad)
  if not measure then
    measure = UIParent:CreateFontString(nil, "ARTWORK")
    measure:Hide()
  end
  local object = type(font) == "string" and rawget(_G, font) or font
  if object then measure:SetFontObject(object) end
  local width = 0
  for _, text in ipairs(texts) do
    measure:SetText(text)
    width = math.max(width, measure:GetStringWidth() or 0)
  end
  return math.max(min or 0, math.ceil(width) + (pad or 0))
end

-- opts: {small = true (small font, for buttons in list rows), fit = {texts}: the button is as wide as
-- the longest of them from the start, so it keeps its width when its text changes between them}
function W.Button(parent, text, onClick, width, opts)
  opts = opts or {}
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  local pad = opts.small and 20 or 24
  if opts.small then
    for setter, font in pairs({
      SetNormalFontObject = "GameFontNormalSmall", SetHighlightFontObject = "GameFontHighlightSmall",
      SetDisabledFontObject = "GameFontDisableSmall",
    }) do
      local object = rawget(_G, font)
      if object and button[setter] then button[setter](button, object) end
    end
  end
  local base = width or 120
  if opts.fit then base = W.FitWidth(opts.small and "GameFontNormalSmall" or "GameFontNormal", opts.fit, base, pad) end
  button:SetSize(base, 22)
  -- the given width is a minimum: longer texts (also set later) widen the button instead of overflowing
  local function Fit()
    local label = button:GetFontString()
    local textWidth = label and label:GetStringWidth()
    if textWidth then button:SetWidth(math.max(base, math.ceil(textWidth) + pad)) end
  end
  if hooksecurefunc then hooksecurefunc(button, "SetText", Fit) end
  button:SetText(text)
  button:SetScript("OnClick", onClick)
  return button
end

function W.Tooltip(frame, title, text)
  frame:SetScript("OnEnter", function(self)
    if self.sideTab then -- side tabs: beside the tab
      GameTooltip:SetOwner(self, "ANCHOR_NONE")
      GameTooltip:SetPoint("LEFT", self, "RIGHT", 6, 0)
    else
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    end
    GameTooltip:SetText(type(title) == "function" and title() or title)
    local body = type(text) == "function" and text() or text
    if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Hover area over a cut-off list cell: shows the full text, plus an optional explanation from
-- hint() (returns nil for none). Without a hint it only shows when the text doesn't fit.
function W.CellHint(cell, title, hint)
  local area = CreateFrame("Frame", nil, cell:GetParent())
  area:SetAllPoints(cell)
  area:EnableMouse(true)
  area:SetScript("OnEnter", function(self)
    if not cell:IsShown() then return end
    local text = cell:GetText()
    local extra = hint and hint()
    local truncated = cell.IsTruncated and cell:IsTruncated()
    if not text or text == "" or not (truncated or extra) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(title)
    GameTooltip:AddLine(text, 1, 1, 1, true)
    if extra then GameTooltip:AddLine(extra, 0.8, 0.8, 0.8, true) end
    GameTooltip:Show()
  end)
  area:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return area
end

-- Hover area for a list row's icon + item name: only there the item tooltip shows (the rest of the
-- row stays free for buttons and their own tooltips). The tooltip uses row.itemId.
function W.ItemArea(row, width)
  local area = CreateFrame("Frame", nil, row)
  area:SetPoint("TOPLEFT", 0, 0)
  area:SetPoint("BOTTOMLEFT", 0, 0)
  area:SetWidth(width)
  area:EnableMouse(true)
  area:SetScript("OnEnter", function(self)
    if not row.itemId then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink("item:" .. row.itemId)
    GameTooltip:Show()
  end)
  area:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return area
end

-- Item icon with a thin border; returns the icon texture
function W.Icon(parent, size)
  local border = parent:CreateTexture(nil, "BORDER")
  border:SetSize(size + 2, size + 2)
  border:SetColorTexture(unpack(W.GOLD))
  local icon = parent:CreateTexture(nil, "ARTWORK")
  icon:SetSize(size, size)
  icon:SetPoint("CENTER", border)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  icon.Border = border
  return icon
end

function W.ClassColor(class)
  if type(class) ~= "string" then return 1, 1, 1 end
  local colors = rawget(_G, "RAID_CLASS_COLORS")
  local color = colors and colors[class:upper()]
  if color then return color.r, color.g, color.b end
  return 1, 1, 1
end

function W.EditBox(parent, width, numeric)
  local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  box:SetSize(width or 120, 20)
  box:SetAutoFocus(false)
  if numeric then box:SetNumeric(true) end
  box:SetScript("OnEscapePressed", box.ClearFocus)
  box:SetScript("OnEnterPressed", box.ClearFocus)
  return box
end

-- Scroll list with pooled rows ----------------------------------------------------------------------
-- createRow(row) builds a row once, updateRow(row, item, index) fills it on every refresh.

function W.ScrollList(parent, rowHeight, createRow, updateRow)
  local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  local content = CreateFrame("Frame", nil, scroll)
  scroll:SetScrollChild(content)
  content:SetSize(1, 1)
  scroll.rows = {}
  scroll.rowHeight = rowHeight
  scroll:SetScript("OnSizeChanged", function(_, width) content:SetWidth(math.max(1, width or 1)) end)

  function scroll:SetItems(items)
    local width = self:GetWidth() or 0
    if width > 1 then content:SetWidth(width) end
    for i, item in ipairs(items) do
      local row = self.rows[i]
      if not row then
        row = CreateFrame("Frame", nil, content)
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
        row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        if i % 2 == 0 then
          local stripe = row:CreateTexture(nil, "BACKGROUND")
          stripe:SetAllPoints()
          stripe:SetColorTexture(1, 1, 1, 0.03)
        end
        createRow(row)
        self.rows[i] = row
      end
      row:Show()
      updateRow(row, item, i)
    end
    for i = #items + 1, #self.rows do self.rows[i]:Hide() end
    content:SetHeight(math.max(1, #items * rowHeight))
  end

  return scroll
end

-- Dropdown menu ---------------------------------------------------------------------------------------
-- One shared menu; a full-screen catcher behind it closes it on any click outside.

local menu, catcher
local MENU_ROW = 18

local function CloseMenu()
  if menu then menu:Hide() end
  if catcher then catcher:Hide() end
end
W.CloseMenu = CloseMenu

local function BuildMenu()
  catcher = CreateFrame("Button", nil, UIParent)
  catcher:SetAllPoints(UIParent)
  catcher:SetFrameStrata("FULLSCREEN")
  catcher:RegisterForClicks("AnyUp")
  catcher:SetScript("OnClick", CloseMenu)
  catcher:Hide()
  menu = W.Box(UIParent, 0.06, 0.9)
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  menu:SetClampedToScreen(true)
  menu:EnableMouse(true)
  menu.buttons = {}
  menu:Hide()
end

-- items: {{text, onClick, checked, disabled, isTitle, color = {r, g, b}}}
function W.OpenMenu(anchor, items, width)
  if not menu then BuildMenu() end
  width = width or 220
  for i, item in ipairs(items) do
    local button = menu.buttons[i]
    if not button then
      button = CreateFrame("Button", nil, menu)
      button:SetHeight(MENU_ROW)
      button:SetPoint("TOPLEFT", 6, -6 - (i - 1) * MENU_ROW)
      button:SetPoint("RIGHT", -6, 0)
      button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      button.Check = button:CreateTexture(nil, "ARTWORK")
      button.Check:SetSize(14, 14)
      button.Check:SetPoint("LEFT", 2, 0)
      button.Check:SetTexture(W.ICON_YES)
      button.Label = W.Text(button, "GameFontHighlightSmall")
      button.Label:SetPoint("LEFT", 20, 0)
      button.Label:SetPoint("RIGHT", -4, 0)
      -- items with an action (Blizzard guild buttons) get the secure overlay while hovered (UI/Commands.lua)
      button:HookScript("OnEnter", function(self)
        if self.action and self:IsEnabled() and ns.UI and ns.UI.ShowOverlay then ns.UI.ShowOverlay(self, self.action()) end
      end)
      menu.buttons[i] = button
    end
    button.Label:SetText(item.text)
    if item.isTitle then
      button.Label:SetTextColor(1, 0.82, 0)
    elseif item.color then
      button.Label:SetTextColor(unpack(item.color))
    elseif item.disabled then
      button.Label:SetTextColor(0.5, 0.5, 0.5)
    else
      button.Label:SetTextColor(1, 1, 1)
    end
    button.Check:SetShown(item.checked == true)
    button:SetEnabled(not item.disabled and not item.isTitle)
    button.action = item.action
    button:SetScript("OnClick", function()
      if item.action then
        ns.Print(ns.L.NOT_IN_COMBAT) -- only reachable when the overlay could not be shown
        return
      end
      CloseMenu()
      if item.onClick then item.onClick() end
    end)
    button:Show()
  end
  for i = #items + 1, #menu.buttons do menu.buttons[i]:Hide() end
  menu:SetSize(width, #items * MENU_ROW + 12)
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  catcher:Show()
  menu:Show()
end

-- Button that opens a menu built on click
function W.MenuButton(parent, text, buildItems, width)
  local button
  button = W.Button(parent, text, function()
    if menu and menu:IsShown() then CloseMenu() return end
    W.OpenMenu(button, buildItems(), math.max(width or 120, 180))
  end, width)
  return button
end

-- Bottom tabs ------------------------------------------------------------------------------------------

function W.Tab(frame, index, text, onClick)
  local name = frame:GetName() .. "Tab" .. index
  local ok, tab = pcall(CreateFrame, "Button", name, frame, "PanelTabButtonTemplate")
  if not ok then tab = CreateFrame("Button", name, frame, "UIPanelButtonTemplate") end
  tab:SetID(index)
  tab:SetText(text)
  tab:SetScript("OnClick", onClick)
  if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) else tab:SetSize(110, 24) end
  return tab
end


-- Guildy additions ------------------------------------------------------------------------------------

-- Horizontal bar row: label (left), bar, count (right). row:SetData(label, value, max, r, g, b)
function W.BarRow(parent, labelWidth)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(16)
  row.Label = W.Text(row, "GameFontHighlightSmall")
  row.Label:SetPoint("LEFT", 0, 0)
  row.Label:SetWidth(labelWidth or 90)
  row.Label:SetWordWrap(false)
  row.Count = W.Text(row, "GameFontNormalSmall")
  row.Count:SetPoint("RIGHT", 0, 0)
  row.Count:SetWidth(28)
  row.Count:SetJustifyH("RIGHT")
  row.Track = row:CreateTexture(nil, "BACKGROUND")
  row.Track:SetPoint("LEFT", row.Label, "RIGHT", 6, 0)
  row.Track:SetPoint("RIGHT", row.Count, "LEFT", -6, 0)
  row.Track:SetHeight(10)
  row.Track:SetColorTexture(0.13, 0.11, 0.08, 1)
  row.Fill = row:CreateTexture(nil, "ARTWORK")
  row.Fill:SetPoint("LEFT", row.Track, "LEFT", 0, 0)
  row.Fill:SetHeight(10)
  row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  function row:SetData(label, value, max, r, g, b)
    self.Label:SetText(label)
    self.Label:SetTextColor(r or 1, g or 1, b or 1)
    self.Count:SetText(value)
    local width = math.max(1, (self.Track:GetWidth() or 100))
    self.Fill:SetWidth(math.max(1, width * ((max and max > 0) and value / max or 0)))
    self.Fill:SetColorTexture(r or 1, g or 0.82, b or 0, 0.85)
    self.fraction = (max and max > 0) and value / max or 0
  end
  row:SetScript("OnSizeChanged", function(self)
    local width = math.max(1, (self.Track:GetWidth() or 100))
    self.Fill:SetWidth(math.max(1, width * (self.fraction or 0)))
  end)
  return row
end

-- Row of toggle buttons; only one is active. options = { {value, text} }; onSelect(value)
function W.Segmented(parent, options, onSelect)
  local group = CreateFrame("Frame", nil, parent)
  group.buttons = {}
  local x = 0
  for i, option in ipairs(options) do
    local button = W.Button(group, option.text, function()
      group:SetValue(option.value)
      onSelect(option.value)
    end, 70, { small = true })
    button:SetPoint("LEFT", x, 0)
    x = x + button:GetWidth() + 2
    button.value = option.value
    group.buttons[i] = button
  end
  group:SetSize(math.max(1, x), 22)
  function group:SetValue(value)
    for _, button in ipairs(self.buttons) do
      local on = button.value == value
      button:SetEnabled(not on)
      local label = button:GetFontString()
      if label then label:SetTextColor(on and 1 or 1, on and 1 or 0.82, on and 1 or 0) end
    end
  end
  return group
end

-- Grip in the bottom-right corner that resizes frame (SetResizable is set by the caller)
function W.ResizeGrip(frame, onDone)
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -4, 4)
  grip:SetFrameLevel(frame:GetFrameLevel() + 20)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function()
    -- a frame anchored at its center grows to both sides and runs away from the cursor up to the
    -- maximum size: anchor it at its top left corner first (same place on screen)
    local left, top = frame:GetLeft(), frame:GetTop()
    if left and top then
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
    frame:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    if onDone then onDone(frame:GetWidth(), frame:GetHeight()) end
  end)
  return grip
end

-- Small profession icon with tooltip; icon:SetSkill(skillLine, text)
function W.ProfIcon(parent, size)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(size, size)
  holder.Icon = holder:CreateTexture(nil, "ARTWORK")
  holder.Icon:SetAllPoints()
  holder.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  return holder
end

-- "r, g, b" of a class file for text
function W.ClassHex(classFile)
  local r, g, b = W.ClassColor(classFile)
  return string.format("ff%02x%02x%02x", r * 255, g * 255, b * 255)
end

-- Class-colored name
function W.ClassName(name, classFile)
  return "|c" .. W.ClassHex(classFile) .. (name or "?") .. "|r"
end
-- Multiline input (guild info editor)
function W.InputArea(parent)
  local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  local box = CreateFrame("EditBox", nil, scroll)
  box:SetMultiLine(true)
  box:SetAutoFocus(false)
  box:SetFontObject("ChatFontNormal")
  box:SetMaxLetters(0)
  box:SetWidth(400)
  box:SetScript("OnEscapePressed", box.ClearFocus)
  scroll:SetScrollChild(box)
  -- clicks on the empty area below the text should still focus the box
  scroll:EnableMouse(true)
  scroll:SetScript("OnMouseDown", function() box:SetFocus() end)
  scroll.EditBox = box
  return scroll
end