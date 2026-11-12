-- The board of the Bank tab: its boxes ("widgets") stand on a grid of Bank.COLS x Bank.ROWS cells that
-- fills the tab (Core/Bank.lua: the grid rules). Where each stands and how large it is, is the player's
-- (settings.bank.layout, nil: the ledger preset). In edit mode every box is covered by a handle: drag
-- it to move the box, drag its corner to size it, the x removes it; boxes never overlap.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI
local B = ns.Bank

local function Copy(layout)
  local out = {}
  for i, item in ipairs(layout) do out[i] = { k = item.k, x = item.x, y = item.y, w = item.w, h = item.h } end
  return out
end

-- onChange(): the layout changed (the tab fills what is shown now)
function UI.BankBoard(parent, onChange)
  local L = ns.L
  local board = CreateFrame("Frame", nil, parent)
  board:SetAllPoints()
  board.defs, board.order, board.placed = {}, {}, {}
  board.Empty = W.Text(board, "GameFontDisable", L.BANK_EDIT_EMPTY)
  board.Empty:SetPoint("CENTER")
  local mins = {}

  -- size = { w, h } a new box gets, min = { w, h } it needs, in cells
  function board:Add(key, box, name, size, min)
    self.defs[key] = { box = box, name = name, size = size, min = min }
    self.order[#self.order + 1] = key
    mins[key] = min
  end

  function board:Layout()
    return B.GridClean(UI.BankSetting("layout"), mins) or Copy(UI.BANK_PRESETS.ledger)
  end

  function board:Cell()
    return ((self:GetWidth() or 0) + W.GAP) / B.COLS, ((self:GetHeight() or 0) + W.GAP) / B.ROWS
  end

  local function Put(frame, item, cw, ch)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", board, "TOPLEFT", item.x * cw, -item.y * ch)
    frame:SetSize(math.max(1, item.w * cw - W.GAP), math.max(1, item.h * ch - W.GAP))
  end

  function board:Apply()
    local layout = self:Layout()
    local cw, ch = self:Cell()
    for key in pairs(self.placed) do self.placed[key] = nil end
    for _, item in ipairs(layout) do
      self.placed[item.k] = item
      Put(self.defs[item.k].box, item, cw, ch)
      self.defs[item.k].box:Show()
    end
    for key, def in pairs(self.defs) do
      if not self.placed[key] then def.box:Hide() end
      if def.Cover then def.Cover:SetShown(self.editing == true and self.placed[key] ~= nil) end
    end
    self.Empty:SetShown(#layout == 0)
  end
  board:SetScript("OnSizeChanged", function() board:Apply() end)

  local function Changed(layout)
    UI.SetBankSetting("layout", layout)
    board:Apply()
    onChange()
  end

  function board:Remove(key)
    local layout = {}
    for _, item in ipairs(self:Layout()) do
      if item.k ~= key then layout[#layout + 1] = item end
    end
    Changed(layout)
  end

  -- Puts a box on the first free spot; false when there is none
  function board:Insert(key)
    local def = self.defs[key]
    if not def or self.placed[key] then return false end
    local layout = self:Layout()
    local item = B.GridSpot(layout, key, def.size[1], def.size[2], def.min[1], def.min[2])
    if not item then
      ns.Print(L.BANK_EDIT_FULL)
      return false
    end
    layout[#layout + 1] = item
    Changed(layout)
    return true
  end

  function board:Preset(name)
    local preset = UI.BANK_PRESETS[name]
    if preset then Changed(name ~= "ledger" and Copy(preset) or nil) end
  end

  -- Moving and sizing: the box follows the mouse as an outline on the grid, green where it may stand
  board.Ghost = CreateFrame("Frame", nil, board)
  board.Ghost:SetFrameLevel((board:GetFrameLevel() or 1) + 80)
  board.Ghost.Fill = board.Ghost:CreateTexture(nil, "OVERLAY")
  board.Ghost.Fill:SetAllPoints()
  board.Ghost:Hide()
  local drag

  local function Drop()
    board:SetScript("OnUpdate", nil)
    board.Ghost:Hide()
    local done = drag
    drag = nil
    if not (done and done.ok and done.item) then return end
    local layout = done.layout
    for i, item in ipairs(layout) do
      if item.k == done.item.k then layout[i] = done.item end
    end
    Changed(layout)
  end

  function board:Track()
    if not drag then return end
    if not IsMouseButtonDown("LeftButton") then return Drop() end
    local scale = self:GetEffectiveScale() or 1
    local x, y = GetCursorPosition()
    local cw, ch = self:Cell()
    local dx = math.floor((x / scale - drag.x) / cw + 0.5)
    local dy = math.floor((drag.y - y / scale) / ch + 0.5)
    local from, min = drag.from, self.defs[drag.from.k].min
    local item = { k = from.k, x = from.x, y = from.y, w = from.w, h = from.h }
    if drag.kind == "move" then
      item.x = math.max(0, math.min(B.COLS - item.w, from.x + dx))
      item.y = math.max(0, math.min(B.ROWS - item.h, from.y + dy))
    else
      item.w = math.max(min[1], math.min(B.COLS - item.x, from.w + dx))
      item.h = math.max(min[2], math.min(B.ROWS - item.y, from.h + dy))
    end
    drag.item, drag.ok = item, B.GridFits(drag.layout, item)
    Put(self.Ghost, item, cw, ch)
    if drag.ok then self.Ghost.Fill:SetColorTexture(0.25, 0.88, 0.25, 0.28) else self.Ghost.Fill:SetColorTexture(1, 0.35, 0.29, 0.28) end
    self.Ghost:Show()
  end

  -- kind: "move" or "size"
  function board:Start(kind, key)
    local layout = self:Layout()
    local from
    for _, item in ipairs(layout) do
      if item.k == key then from = item end
    end
    if not from then return end
    local scale = self:GetEffectiveScale() or 1
    local x, y = GetCursorPosition()
    drag = { kind = kind, from = from, layout = layout, x = x / scale, y = y / scale }
    self:SetScript("OnUpdate", function() board:Track() end)
  end

  local function Cover(key)
    local def = board.defs[key]
    if def.Cover then return end
    local cover = CreateFrame("Button", nil, def.box)
    cover:SetAllPoints()
    cover:SetFrameLevel((def.box:GetFrameLevel() or 1) + 40)
    cover.Shade = cover:CreateTexture(nil, "BACKGROUND")
    cover.Shade:SetAllPoints()
    cover.Shade:SetColorTexture(0, 0, 0, 0.6)
    cover.Name = W.Text(cover, "GameFontNormal", def.name)
    cover.Name:SetPoint("CENTER", 0, 6)
    cover.Hint = W.Text(cover, "GameFontDisableSmall", L.BANK_EDIT_DRAG)
    cover.Hint:SetPoint("TOP", cover.Name, "BOTTOM", 0, -4)
    cover:SetScript("OnMouseDown", function(_, button)
      if button == "LeftButton" then board:Start("move", key) end
    end)
    cover.Remove = W.Button(cover, "x", function() board:Remove(key) end, 24, { small = true, pad = 10 })
    cover.Remove:SetPoint("TOPRIGHT", -4, -4)
    W.Tooltip(cover.Remove, L.BANK_EDIT_REMOVE)
    cover.Grip = CreateFrame("Button", nil, cover)
    cover.Grip:SetSize(20, 20)
    cover.Grip:SetPoint("BOTTOMRIGHT", -2, 2)
    cover.Grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    cover.Grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    cover.Grip:SetScript("OnMouseDown", function(_, button)
      if button == "LeftButton" then board:Start("size", key) end
    end)
    W.Tooltip(cover.Grip, L.BANK_EDIT_SIZE)
    def.Cover = cover
  end

  function board:SetEditing(on)
    self.editing = on and true or false
    if on then
      for _, key in ipairs(self.order) do Cover(key) end
    elseif drag then
      drag.ok = false
      Drop()
    end
    self:Apply()
  end
  board:SetScript("OnHide", function()
    if drag then
      drag.ok = false
      Drop()
    end
  end)

  return board
end
