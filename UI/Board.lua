-- A board: the boxes of a tab on a grid the player arranges (Core/Grid.lua has the rules). Twelve cells
-- wide and twelve rows tall to start with. A box added below everything adds rows, and the window grows
-- by them (opts.grow) so nothing has to scroll; taking the rows away gives the height back. Only where
-- the screen has no more room the rows get lower, and at last the tab scrolls.
--
--   local board = UI.Board(parent, { load = function() return saved layout or nil end,
--     save = function(layout or nil) end, default = function() return layout end,
--     onChange = function() fill the boxes that show end,
--     grow = function(px) make the window taller (lower for a negative px) end })
--   board.Content                      parent of every box
--   board:Add(key, box, { name, about, size = { w, h }, min = { w, h } or function(o) ..., options = { { key, label } } })
--   board:Controls(page, presets)      "Customize" (and the presets) into a page's toolbar
--   board:Apply()                      places the boxes; board.placed[key] = item for those that show
--
-- A box reads its own options from box.opts (the item's o; an option is on unless it is false).
-- In edit mode every box is covered by a handle: drag it to move the box, drag its corner to size it,
-- "Options" has its options, the x removes it. Every free place among the boxes carries a "+", and a
-- bar at the bottom of the tab adds below everything: a click lists the boxes that are not on the tab,
-- and the one under the mouse shows as it will look, right at the free place, or over the lower part
-- of the tab when it is to go below.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI
local G = ns.Grid

local MIN_ROW = 30   -- px a row is tall at least: lower than that the tab scrolls
local BAR = 14       -- room for the scroll bar while there is something to scroll
local ADD_H = 30     -- the bar "add a box below" at the bottom of the tab in edit mode

function UI.Board(parent, opts)
  local L = ns.L
  local board = CreateFrame("Frame", nil, parent)
  board:SetAllPoints()
  board.defs, board.order, board.placed = {}, {}, {}
  board.Scroll = CreateFrame("ScrollFrame", nil, board, "UIPanelScrollFrameTemplate")
  board.Scroll:SetPoint("TOPLEFT", 0, 0)
  board.Scroll:SetPoint("BOTTOMRIGHT", 0, 0)
  board.Content = CreateFrame("Frame", nil, board.Scroll)
  board.Content:SetSize(1, 1)
  board.Scroll:SetScrollChild(board.Content)
  W.SlimScrollBar(board.Scroll, 4)
  board.Empty = W.Text(board, "GameFontDisable", L.BOARD_EMPTY)
  board.Empty:SetPoint("CENTER")
  local content = board.Content

  local function Least(key, o)
    local def = board.defs[key]
    if not def then return nil end
    if type(def.min) == "function" then return def.min(o or {}) end
    return def.min
  end

  function board:Add(key, box, def)
    def.box = box
    self.defs[key] = def
    self.order[#self.order + 1] = key
    box.opts = {}
  end

  function board:Layout()
    return G.Clean(opts.load(), Least) or G.Copy(opts.default())
  end

  -- width and height of a cell: the rows share the tab's height. Whether they got too low for that
  -- and the tab scrolls instead.
  local function Cells(rows)
    local height = (board:GetHeight() or 0) - (board.editing and ADD_H or 0) + W.GAP
    local ch = height / rows
    local scrolls = ch < MIN_ROW
    if scrolls then ch = MIN_ROW end
    local width = (board:GetWidth() or 0) - (scrolls and BAR or 0) + W.GAP
    return width / G.COLS, ch, scrolls
  end

  local function Put(frame, item, cw, ch)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", content, "TOPLEFT", item.x * cw, -item.y * ch)
    frame:SetSize(math.max(1, item.w * cw - W.GAP), math.max(1, item.h * ch - W.GAP))
  end

  local slots, picker = {}, nil
  local Slot, ClosePicker

  -- The mouse wheel anywhere on the tab while customizing: scrolls the tab
  local function Wheel(_, delta)
    local scroll = board.Scroll
    if not (scroll.GetVerticalScroll and scroll.GetVerticalScrollRange) then return end
    local range = scroll:GetVerticalScrollRange() or 0
    local to = (scroll:GetVerticalScroll() or 0) - delta * (board.ch or MIN_ROW) * 2
    scroll:SetVerticalScroll(math.max(0, math.min(range, to)))
  end

  -- to the end of the tab, where a box added below stands (the range is known a frame later)
  local function ScrollToEnd()
    local scroll = board.Scroll
    local function Go()
      if scroll.SetVerticalScroll and scroll.GetVerticalScrollRange then scroll:SetVerticalScroll(scroll:GetVerticalScrollRange() or 0) end
    end
    Go()
    C_Timer.After(0, Go)
  end

  -- the bar at the bottom of the tab in edit mode: add a box below everything
  board.AddBar = CreateFrame("Button", nil, board)
  board.AddBar:SetPoint("BOTTOMLEFT", 0, 0)
  board.AddBar:SetPoint("BOTTOMRIGHT", 0, 0)
  board.AddBar:SetHeight(ADD_H - 4)
  board.AddBar.Fill = board.AddBar:CreateTexture(nil, "BACKGROUND")
  board.AddBar.Fill:SetAllPoints()
  board.AddBar.Fill:SetColorTexture(W.GOLD[1] * 0.25, W.GOLD[2] * 0.25, W.GOLD[3] * 0.25, 0.95)
  board.AddBar.Edge = board.AddBar:CreateTexture(nil, "BORDER")
  board.AddBar.Edge:SetPoint("TOPLEFT")
  board.AddBar.Edge:SetPoint("TOPRIGHT")
  board.AddBar.Edge:SetHeight(1)
  board.AddBar.Edge:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.6)
  board.AddBar:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  board.AddBar.Label = W.Text(board.AddBar, "GameFontNormalSmall", "+  " .. L.BOARD_SLOT_BELOW)
  board.AddBar.Label:SetPoint("CENTER")
  board.AddBar:SetScript("OnClick", function(self) board:Pick(self) end)
  board.AddBar:Hide()

  function board:Apply()
    local layout = self:Layout()
    local rows = math.max(G.PAGE, G.Rows(layout))
    local base = rows
    local cw, ch, scrolls = Cells(rows)
    self.cw, self.ch = cw, ch
    self.Scroll:ClearAllPoints()
    self.Scroll:SetPoint("TOPLEFT", 0, 0)
    self.Scroll:SetPoint("BOTTOMRIGHT", scrolls and -BAR or 0, self.editing and ADD_H or 0)
    content:SetSize(math.max(1, G.COLS * cw - W.GAP), math.max(1, rows * ch - W.GAP))
    local bar = self.Scroll.ScrollBar
    if type(bar) == "table" and bar.SetShown then bar:SetShown(scrolls) end
    for key in pairs(self.placed) do self.placed[key] = nil end
    for _, item in ipairs(layout) do
      local def = self.defs[item.k]
      self.placed[item.k] = item
      def.box.opts = item.o or {}
      Put(def.box, item, cw, ch)
      def.box:SetAlpha(1)
      if def.raised then
        def.raised = nil
        def.box:SetFrameStrata(self:GetFrameStrata())
      end
      def.box:Show()
    end
    -- the box the picker is about to add: shown where it will stand
    local preview = self.preview
    if preview and not self.placed[preview.k] then
      local def = self.defs[preview.k]
      self.placed[preview.k] = preview
      def.box.opts = {}
      -- a box that will go below everything: shown over the lower part of the tab, on top of what is there
      local at, below = preview, preview.y + preview.h > rows
      if below then
        local h = math.min(preview.h, rows)
        at = { x = preview.x, y = rows - h, w = preview.w, h = h }
        def.raised = true
        def.box:SetFrameStrata("HIGH")
      end
      Put(def.box, at, cw, ch)
      def.box:SetAlpha(below and 1 or 0.8)
      def.box:Show()
    end
    for key, def in pairs(self.defs) do
      if not self.placed[key] then def.box:Hide() end
      if def.Cover then def.Cover:SetShown(self.editing == true and self.placed[key] ~= nil and not (preview and preview.k == key)) end
    end
    -- the free places
    local count = 0
    if self.editing then
      for _, gap in ipairs(G.Gaps(layout, base, 3, 3)) do
        count = count + 1
        local slot = Slot(count)
        slot.gap = gap
        Put(slot, gap, cw, ch)
        slot:SetShown(not (preview and self.pickGap and self.pickGap.x == gap.x and self.pickGap.y == gap.y))
      end
      -- under everything there is always room: the bar at the bottom of the tab adds there
      self.AddBar.gap = { x = 0, y = base, w = G.COLS, h = G.MAX_ROWS, tail = true }
    end
    self.AddBar:SetShown(self.editing == true)
    for index = count + 1, #slots do slots[index]:Hide() end
    self.slotCount = count
    self.Empty:SetShown(#layout == 0 and not self.editing)
  end
  board:SetScript("OnSizeChanged", function() board:Apply() end)

  function board:Rows()
    return math.max(G.PAGE, G.Rows(self:Layout()))
  end

  -- The layout has other rows than `before`: the window grows or gives back that much height
  function board:RowsChanged(before)
    local rows = self:Rows()
    if rows ~= before and opts.grow and self.ch then opts.grow((rows - before) * self.ch) end
  end

  local function Changed(layout)
    local before = board:Rows()
    board.preview, board.pickGap = nil, nil
    ClosePicker()
    opts.save(layout)
    board:RowsChanged(before)
    board:Apply()
    opts.onChange()
  end

  function board:Remove(key)
    local layout = {}
    for _, item in ipairs(self:Layout()) do
      if item.k ~= key then layout[#layout + 1] = item end
    end
    Changed(layout)
  end

  -- The item a box would be in a free place: as large as usual where there is room, never smaller
  -- than it works at; nil when the place is too small
  local function InGap(key, gap)
    local def = board.defs[key]
    local least = Least(key, {})
    if gap.tail then return { k = key, x = gap.x, y = gap.y, w = math.max(def.size[1], least[1]), h = math.max(def.size[2], least[2]) } end
    if least[1] > gap.w or least[2] > gap.h then return nil end
    return { k = key, x = gap.x, y = gap.y, w = math.min(gap.w, math.max(def.size[1], least[1])),
      h = math.min(gap.h, math.max(def.size[2], least[2])) }
  end

  -- Where a box would go: into the place, else under everything. Returns the item and whether it fits the place.
  function board:Candidate(key, gap)
    local layout = self:Layout()
    local item = gap and InGap(key, gap)
    if item and G.Fits(layout, item) then return item, true end
    local def, least = self.defs[key], Least(key, {})
    return G.Spot(layout, key, math.max(def.size[1], least[1]), math.max(def.size[2], least[2]), least[1], least[2]), false
  end

  -- Puts a box on the tab (gap: the free place it was picked for); false when there is no room at all
  function board:Insert(key, gap)
    if not self.defs[key] or (self.placed[key] and not (self.preview and self.preview.k == key)) then return false end
    local item = self:Candidate(key, gap)
    if not item then
      ns.Print(L.BOARD_FULL)
      return false
    end
    local layout = self:Layout()
    local below = item.y >= G.Rows(layout)
    layout[#layout + 1] = item
    Changed(layout)
    if below then ScrollToEnd() end
    return true
  end

  function board:Preset(layout)
    Changed(layout and G.Copy(layout) or nil)
  end

  -- Switches an option of a box; a box that needs more room for it grows, or the option stays as it was
  function board:Toggle(key, option)
    local layout = self:Layout()
    for i, item in ipairs(layout) do
      if item.k == key then
        local o = {}
        for name, value in pairs(item.o or {}) do o[name] = value end
        if o[option] == false then o[option] = nil else o[option] = false end
        local least = Least(key, o)
        local grown = { k = key, x = item.x, y = item.y, w = math.max(item.w, least[1]), h = math.max(item.h, least[2]), o = next(o) and o or nil }
        grown.x = math.min(grown.x, G.COLS - grown.w)
        if not G.Fits(layout, grown) then
          ns.Print(L.BOARD_FULL)
          return false
        end
        layout[i] = grown
        Changed(layout)
        return true
      end
    end
    return false
  end

  function board:OptionItems(key)
    local def, item = self.defs[key], self.placed[key]
    local items = { { text = def.name, isTitle = true } }
    for _, option in ipairs(def.options or {}) do
      items[#items + 1] = { text = option[2], checked = not (item and item.o and item.o[option[1]] == false),
        onClick = function() board:Toggle(key, option[1]) end }
    end
    return items
  end

  -- Moving and sizing: the box follows the mouse as an outline on the grid, green where it may stand
  board.Ghost = CreateFrame("Frame", nil, content)
  board.Ghost:SetFrameLevel((content:GetFrameLevel() or 1) + 80)
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
    local dx = math.floor((x / scale - drag.x) / self.cw + 0.5)
    local dy = math.floor((drag.y - y / scale) / self.ch + 0.5)
    local from = drag.from
    local least = Least(from.k, from.o)
    local item = { k = from.k, x = from.x, y = from.y, w = from.w, h = from.h, o = from.o }
    -- within the rows there are: more of them come with a box added below (the bar at the bottom)
    local rows = math.max(G.PAGE, G.Rows(drag.layout))
    if drag.kind == "move" then
      item.x = math.max(0, math.min(G.COLS - item.w, from.x + dx))
      item.y = math.max(0, math.min(rows - item.h, from.y + dy))
    else
      item.w = math.max(least[1], math.min(G.COLS - item.x, from.w + dx))
      item.h = math.max(least[2], math.min(rows - item.y, from.h + dy))
    end
    drag.item, drag.ok = item, G.Fits(drag.layout, item)
    Put(self.Ghost, item, self.cw, self.ch)
    if drag.ok then self.Ghost.Fill:SetColorTexture(0.25, 0.88, 0.25, 0.28) else self.Ghost.Fill:SetColorTexture(1, 0.35, 0.29, 0.28) end
    self.Ghost:Show()
  end

  -- kind: "move" or "size"
  function board:Start(kind, key)
    ClosePicker()
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

  local function StopDrag()
    if not drag then return end
    drag.ok = false
    Drop()
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
    cover.Hint = W.Text(cover, "GameFontDisableSmall", L.BOARD_DRAG)
    cover.Hint:SetPoint("TOP", cover.Name, "BOTTOM", 0, -4)
    cover:SetScript("OnMouseDown", function(_, button)
      if button == "LeftButton" then board:Start("move", key) end
    end)
    cover:EnableMouseWheel(true)
    cover:SetScript("OnMouseWheel", Wheel)
    cover.Remove = W.Button(cover, "x", function() board:Remove(key) end, 24, { small = true, pad = 10 })
    cover.Remove:SetPoint("TOPRIGHT", -4, -4)
    W.Tooltip(cover.Remove, L.BOARD_REMOVE)
    if def.options then
      cover.Gear = W.MenuButton(cover, L.BOARD_OPTIONS, function() return board:OptionItems(key) end, 90, 160)
      cover.Gear:SetPoint("RIGHT", cover.Remove, "LEFT", -4, 0)
    end
    cover.Grip = CreateFrame("Button", nil, cover)
    cover.Grip:SetSize(20, 20)
    cover.Grip:SetPoint("BOTTOMRIGHT", -2, 2)
    cover.Grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    cover.Grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    cover.Grip:SetScript("OnMouseDown", function(_, button)
      if button == "LeftButton" then board:Start("size", key) end
    end)
    W.Tooltip(cover.Grip, L.BOARD_SIZE)
    def.Cover = cover
  end

  -- A free place: a faint field with a "+"; a click opens the picker beside it
  Slot = function(index)
    local slot = slots[index]
    if slot then return slot end
    slot = CreateFrame("Button", nil, content)
    slot.Fill = slot:CreateTexture(nil, "BACKGROUND")
    slot.Fill:SetAllPoints()
    slot.Fill:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.07)
    for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
      { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
      local line = slot:CreateTexture(nil, "BORDER")
      line:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.45)
      line:SetPoint(edge[1])
      line:SetPoint(edge[2])
      if edge[3] then line:SetHeight(1) else line:SetWidth(1) end
    end
    slot:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    slot.Plus = W.Text(slot, "GameFontNormalHuge", "+")
    slot.Plus:SetPoint("CENTER", 0, 8)
    slot.Label = W.Text(slot, "GameFontDisableSmall", L.BOARD_SLOT)
    slot.Label:SetPoint("TOP", slot.Plus, "BOTTOM", 0, -2)
    slot:SetScript("OnClick", function(self) board:Pick(self) end)
    slot:EnableMouseWheel(true)
    slot:SetScript("OnMouseWheel", Wheel)
    slots[index] = slot
    return slot
  end

  function board:Slots()
    local shown = {}
    for index = 1, self.slotCount or 0 do shown[index] = slots[index] end
    return shown
  end

  -- The picker: every box that is not on the tab, those that fit the place first. The one under the
  -- mouse shows in its place; a click puts it there.
  local PICK_ROW = 46
  local function Picker()
    if picker then return picker end
    picker = W.Box(board, 0.06, 0.9)
    picker:SetFrameStrata("DIALOG")
    picker:SetClampedToScreen(true)
    picker:EnableMouse(true)
    picker:SetWidth(330)
    picker.Title = W.Text(picker, "GameFontNormal", L.BOARD_PICK)
    picker.Title:SetPoint("TOPLEFT", 10, -8)
    picker.Close = W.Button(picker, "x", function() ClosePicker() end, 24, { small = true, pad = 10 })
    picker.Close:SetPoint("TOPRIGHT", -4, -4)
    picker.None = W.Text(picker, "GameFontDisable", L.BOARD_PICK_NONE)
    picker.None:SetPoint("TOPLEFT", 12, -34)
    picker.Rows = {}
    picker:Hide()
    return picker
  end

  local function PickRow(index)
    local row = picker.Rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, picker)
    row:SetHeight(PICK_ROW - 4)
    row:SetPoint("TOPLEFT", 6, -30 - (index - 1) * PICK_ROW)
    row:SetPoint("RIGHT", -6, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.Name = W.Text(row, "GameFontHighlightSmall")
    row.Name:SetPoint("TOPLEFT", 6, -4)
    row.About = W.Text(row, "GameFontDisableSmall")
    row.About:SetPoint("TOPLEFT", 6, -18)
    row.About:SetPoint("RIGHT", -6, 0)
    row.About:SetJustifyV("TOP")
    row.About:SetHeight(24)
    row:SetScript("OnEnter", function(self)
      local item, fits = board:Candidate(self.key, board.pickGap)
      board.preview = item
      board:Apply()
      opts.onChange()
      if item and not fits then ScrollToEnd() end -- (only where the tab had to scroll)
    end)
    row:SetScript("OnLeave", function()
      if not board.preview then return end
      board.preview = nil
      board:Apply()
    end)
    row:SetScript("OnClick", function(self) board:Insert(self.key, board.pickGap) end)
    picker.Rows[index] = row
    return row
  end

  ClosePicker = function()
    if picker then picker:Hide() end
    board.pickGap = nil
    if board.preview then
      board.preview = nil
      board:Apply()
    end
  end

  -- What the picker offers for a free place: { key, fits } with the boxes that fit it first
  function board:Offers(gap)
    local fit, rest = {}, {}
    for _, key in ipairs(self.order) do
      if not self.placed[key] or (self.preview and self.preview.k == key) then
        if InGap(key, gap) then fit[#fit + 1] = { key = key, fits = true } else rest[#rest + 1] = { key = key, fits = false } end
      end
    end
    for _, offer in ipairs(rest) do fit[#fit + 1] = offer end
    return fit
  end

  function board:Pick(slot)
    local frame = Picker()
    if frame:IsShown() and self.pickGap == slot.gap then return ClosePicker() end
    ClosePicker()
    self.pickGap = slot.gap
    local offers = self:Offers(slot.gap)
    for i, offer in ipairs(offers) do
      local row, def = PickRow(i), self.defs[offer.key]
      row.key = offer.key
      row.Name:SetText(def.name)
      local least = Least(offer.key, {})
      row.About:SetText(offer.fits and (def.about or "") or ("|cffd67a32" .. L.BOARD_PICK_BELOW:format(least[1], least[2]) .. "|r"))
      row:Show()
    end
    for i = #offers + 1, #frame.Rows do frame.Rows[i]:Hide() end
    frame.None:SetShown(#offers == 0)
    frame:SetHeight(math.max(64, 38 + #offers * PICK_ROW))
    frame:ClearAllPoints()
    -- over the bar at the bottom; beside a free place where there is room, else over its right part
    local right, width = slot:GetRight(), board:GetRight()
    if slot == self.AddBar then
      frame:SetPoint("BOTTOMRIGHT", slot, "TOPRIGHT", -BAR, 6)
    elseif right and width and width - right >= 340 then
      frame:SetPoint("TOPLEFT", slot, "TOPRIGHT", 6, 0)
    elseif slot.gap.x > 3 then
      frame:SetPoint("TOPRIGHT", slot, "TOPLEFT", -6, 0)
    else
      frame:SetPoint("TOPRIGHT", slot, "TOPRIGHT", -6, -6)
    end
    frame:Show()
  end

  function board:PickRows()
    local rows = {}
    if not (picker and picker:IsShown()) then return rows end
    for _, row in ipairs(picker.Rows) do
      if row:IsShown() then rows[#rows + 1] = row end
    end
    return rows
  end

  function board:SetEditing(on)
    self.editing = on and true or false
    if on then
      for _, key in ipairs(self.order) do Cover(key) end
    else
      StopDrag()
      ClosePicker()
    end
    if self.Edit then self.Edit:SetText(on and L.BOARD_DONE or L.BOARD_EDIT) end
    if self.Presets then self.Presets:SetShown(self.editing) end
    self:Apply()
  end
  board:SetScript("OnHide", function()
    StopDrag()
    ClosePicker()
  end)

  -- "Customize" at the right end of a page's toolbar, and the presets while customizing.
  -- presets: { { name, layout or nil for the default } }
  function board:Controls(page, presets)
    self.Edit = page:Right(W.Button(page.Bar, L.BOARD_EDIT, function()
      board:SetEditing(not board.editing)
      opts.onChange()
    end, 80, { small = true, fit = { L.BOARD_EDIT, L.BOARD_DONE } }))
    W.Tooltip(self.Edit, L.BOARD_EDIT, L.BOARD_EDIT_TIP)
    if presets then
      self.Presets = page:Right(W.MenuButton(page.Bar, L.BOARD_PRESET, function()
        local items = {}
        for _, preset in ipairs(presets) do
          items[#items + 1] = { text = preset[1], onClick = function() board:Preset(preset[2]) end }
        end
        return items
      end, 90, 160))
      self.Presets:Hide()
    end
  end

  return board
end
