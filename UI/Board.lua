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
--   board:Add(key, box, { name, about, size = { w, h }, min = { w, h } or function(o) ..., options = { { key, label } },
--     parts = function(o) return { part, ... } end, canAdd = function() ... end, onAdd = function(anchor) ... end,
--     bare = true })   bare: a box without a title row of its own (a row of tiles)
--   board:Controls(page, presets)      "Customize" (and the presets) into a page's toolbar
--   board:Apply()                      places the boxes; board.placed[key] = item for those that show
--   board:LayoutParts()                the handles over the parts anew (a tab whose parts changed)
--
-- A box reads its own options from box.opts (the item's o; an option is on unless it is false).
--
-- Customizing looks and works the same for every box of every tab:
--   * The box keeps its look, a little darker, under a strip with its name. The strip lies over the
--     box's own title row, so the name stands there once; a box without a title row (bare) is that
--     much lower while customizing and has the strip above it. Drag it anywhere to move it,
--     drag its corner to size it (the boxes in its way move down, every box moves up into room that
--     got free). The x in the strip removes it.
--   * The parts of a box (tiles, title cards, the headings of its columns) each carry a handle: its x
--     takes the part away, a click on it changes it where the box has something to choose from.
--     A part is { frame, option = key } for one that an option of the box switches, or
--     { frame, onClick = function(handle) end, onRemove = function() end or nil, open = true or nil }.
--   * The + in the strip adds a part: the ones that are switched off, or what onAdd offers.
--   * "Options" in the strip has what is no part (how a chart draws).
--   * Every free place among the boxes carries a "+", and a bar at the bottom of the tab adds below
--     everything: a click lists the boxes that are not on the tab, and the one under the mouse shows as
--     it will look, right at the free place, or over the lower part of the tab when it is to go below.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI
local G = ns.Grid

local MIN_ROW = 30   -- px a row is tall at least: lower than that the tab scrolls
local BAR = 14       -- room for the scroll bar while there is something to scroll
local ADD_H = 30     -- the bar "add a box below" at the bottom of the tab in edit mode
local STRIP = 24     -- the strip with its name and buttons on top of every box in edit mode

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

  -- A box. While customizing, one without a title row of its own starts below its strip (see Cover).
  local function Inset(key)
    local def = board.defs[key]
    return board.editing and def and def.bare and STRIP or 0
  end
  local function PutBox(box, item, cw, ch)
    local top = Inset(item.k)
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", content, "TOPLEFT", item.x * cw, -item.y * ch - top)
    box:SetSize(math.max(1, item.w * cw - W.GAP), math.max(1, item.h * ch - W.GAP - top))
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
      PutBox(def.box, item, cw, ch)
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
      at.k = preview.k
      PutBox(def.box, at, cw, ch)
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
    if drag then drag.cell = nil end -- placed anew under a drag: its next step moves the boxes again
    self.Empty:SetShown(#layout == 0 and not self.editing)
    self:LayoutParts()
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

  -- layout: nil for the default; first: the box that was just placed (the others make room for it)
  local function Changed(layout, first)
    local before = board:Rows()
    board.preview, board.pickGap = nil, nil
    ClosePicker()
    opts.save(layout and G.Compact(layout, first) or nil)
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
    Changed(layout, key)
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
        layout[i] = grown -- a box that needs more room for it takes it: the others move
        Changed(layout, key)
        return true
      end
    end
    return false
  end

  -- The parts a box names (def.parts) for the options it stands with
  local function PartSpecs(key, o)
    local def = board.defs[key]
    return def.parts and def.parts(o or {}) or {}
  end

  -- The options of a box that switch one of its parts ({ option = true }): those are taken away at the
  -- part and brought back with the +, the others stand under "Options"
  local function PartOptions(key)
    local set = {}
    for _, spec in ipairs(PartSpecs(key, {})) do
      if spec.option then set[spec.option] = true end
    end
    return set
  end

  -- "Options" of a box: what it can be switched in that is no part of it
  function board:OptionItems(key)
    local def, item = self.defs[key], self.placed[key]
    local parts = PartOptions(key)
    local items = { { text = def.name, isTitle = true } }
    for _, option in ipairs(def.options or {}) do
      if not parts[option[1]] then
        items[#items + 1] = { text = option[2], checked = not (item and item.o and item.o[option[1]] == false),
          onClick = function() board:Toggle(key, option[1]) end }
      end
    end
    return items
  end

  -- The + of a box: its parts that are switched off
  function board:AddItems(key)
    local def, item = self.defs[key], self.placed[key]
    local parts = PartOptions(key)
    local items = { { text = def.name, isTitle = true } }
    for _, option in ipairs(def.options or {}) do
      if parts[option[1]] and item and item.o and item.o[option[1]] == false then
        items[#items + 1] = { text = option[2], onClick = function() board:Toggle(key, option[1]) end }
      end
    end
    return items
  end

  -- Whether the + of a box has something to add
  function board:CanAdd(key)
    local def = self.defs[key]
    if def.canAdd then return def.canAdd() == true end
    return #self:AddItems(key) > 1
  end

  -- The handles over the parts of every box: where its parts are, with an x on those that can go
  local partHandles = {}
  local function PartHandle(key, index)
    local list = partHandles[key]
    if list[index] then return list[index] end
    local cover = board.defs[key].Cover
    local handle = W.Handle(cover, function(self) if self.spec and self.spec.onRemove then self.spec.onRemove() end end)
    handle:SetFrameLevel((cover:GetFrameLevel() or 1) + 2)
    handle.Mark = handle:CreateTexture(nil, "BORDER") -- under the part whose list is open
    handle.Mark:SetPoint("BOTTOMLEFT", 4, 2)
    handle.Mark:SetPoint("BOTTOMRIGHT", -4, 2)
    handle.Mark:SetHeight(2)
    handle.Mark:SetColorTexture(1, 0.82, 0, 0.9)
    -- a click changes the part (where there is something to choose), dragging moves its box
    handle:SetScript("OnMouseDown", function(self, mouse)
      if mouse ~= "LeftButton" then return end
      self.downX, self.downY = GetCursorPosition()
      board:Start("move", key)
    end)
    handle:SetScript("OnMouseUp", function(self, mouse)
      if mouse ~= "LeftButton" or not self.downX then return end
      local x, y = GetCursorPosition()
      local still = math.abs(x - self.downX) < 6 and math.abs(y - self.downY) < 6
      self.downX = nil
      if still and self.spec and self.spec.onClick then self.spec.onClick(self) end
    end)
    list[index] = handle
    return handle
  end

  function board:LayoutParts()
    for _, key in ipairs(self.order) do
      local def, item = self.defs[key], self.placed[key]
      local list = partHandles[key] or {}
      partHandles[key] = list
      local count = 0
      if self.editing and def.Cover and item and not (self.preview and self.preview.k == key) then
        for _, spec in ipairs(PartSpecs(key, item.o)) do
          local part = spec
          if spec.option then
            -- a part an option switches: there while the option is on, its x switches it off
            part = not (item.o and item.o[spec.option] == false)
              and { frame = spec.frame, onRemove = function() board:Toggle(key, spec.option) end } or nil
          end
          if part then
            count = count + 1
            local handle = PartHandle(key, count)
            handle.spec = part
            handle:ClearAllPoints()
            handle:SetPoint("TOPLEFT", part.frame, "TOPLEFT", -2, 2)
            handle:SetPoint("BOTTOMRIGHT", part.frame, "BOTTOMRIGHT", 2, -2)
            handle.Remove:SetShown(part.onRemove ~= nil)
            handle.Mark:SetShown(part.open == true)
            handle:Show()
          end
        end
        def.Cover.Add:SetShown(self:CanAdd(key))
        def.Cover.Gear:SetShown(#self:OptionItems(key) > 1)
        def.Cover.Gear:ClearAllPoints()
        def.Cover.Gear:SetPoint("RIGHT", def.Cover.Add:IsShown() and def.Cover.Add or def.Cover.Remove, "LEFT", -4, 0)
      end
      for index = count + 1, #list do list[index]:Hide() end
      list.count = count
    end
  end

  -- The handles that show over the parts of a box
  function board:Parts(key)
    local shown, list = {}, partHandles[key] or {}
    for index = 1, list.count or 0 do shown[index] = list[index] end
    return shown
  end

  -- Moving and sizing, as it happens: the box itself follows the mouse, a gold field marks the cells it
  -- will land on, and the other boxes move out of its way right away (Grid.Compact), so what letting
  -- go will do is on the tab before it is done.
  board.Ghost = CreateFrame("Frame", nil, content)
  board.Ghost:SetFrameLevel((content:GetFrameLevel() or 1) + 80)
  board.Ghost.Fill = board.Ghost:CreateTexture(nil, "BACKGROUND")
  board.Ghost.Fill:SetAllPoints()
  board.Ghost.Fill:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.22)
  for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
    { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
    local line = board.Ghost:CreateTexture(nil, "BORDER")
    line:SetColorTexture(1, 0.82, 0, 0.9)
    line:SetPoint(edge[1])
    line:SetPoint(edge[2])
    if edge[3] then line:SetHeight(2) else line:SetWidth(2) end
  end
  board.Ghost:Hide()
  local drag

  local function Drop()
    board:SetScript("OnUpdate", nil)
    board.Ghost:Hide()
    local done = drag
    drag = nil
    local from, lands = done and done.from, done and done.lands
    local same = from and lands and from.x == lands.x and from.y == lands.y and from.w == lands.w and from.h == lands.h
    if not (done and done.ok and done.item and done.result) or same then
      board:Apply() -- every box back to where it stands (a click that moved nothing stores nothing)
      return
    end
    Changed(done.result, done.item.k) -- what the tab showed while the box was held
  end

  -- The layout as it would be if the mouse let go now (while a box is dragged), else nil
  function board:Dragging()
    return drag and drag.result or nil
  end

  function board:Track()
    if not drag then return end
    if not IsMouseButtonDown("LeftButton") then return Drop() end
    local scale = self:GetEffectiveScale() or 1
    local x, y = GetCursorPosition()
    x, y = x / scale, y / scale
    local cw, ch = self.cw, self.ch
    local dx = math.floor((x - drag.x) / cw + 0.5)
    local dy = math.floor((drag.y - y) / ch + 0.5)
    local from = drag.from
    local least = Least(from.k, from.o)
    local item = { k = from.k, x = from.x, y = from.y, w = from.w, h = from.h, o = from.o }
    -- within the rows that show: what it pushes down adds rows by itself
    local rows = math.max(G.PAGE, G.Rows(drag.layout))
    if drag.kind == "move" then
      item.x = math.max(0, math.min(G.COLS - item.w, from.x + dx))
      item.y = math.max(0, math.min(rows - item.h, from.y + dy))
    else
      item.w = math.max(least[1], math.min(G.COLS - item.x, from.w + dx))
      item.h = math.max(least[2], math.min(math.max(from.h, rows - item.y), from.h + dy))
    end
    -- another cell than before: the other boxes take the places they would have. Sideways within its
    -- row the box changes places with its neighbours (Grid.Shift); up and down the others make room.
    local cell = item.x .. "," .. item.y .. "," .. item.w .. "," .. item.h
    if cell ~= drag.cell then
      drag.cell = cell
      local trial = {}
      if drag.kind == "move" then
        trial, item = G.Shift(drag.layout, from, item)
      else
        for i, other in ipairs(drag.layout) do trial[i] = other.k == item.k and item or other end
      end
      drag.item, drag.ok = item, true
      drag.result = G.Compact(trial, item.k)
      for _, placed in ipairs(drag.result) do
        if placed.k == item.k then
          Put(self.Ghost, placed, cw, ch)
          drag.lands = placed
        else
          PutBox(self.defs[placed.k].box, placed, cw, ch)
        end
      end
    end
    -- the box itself: under the mouse while it is moved, in its new size while it is sized
    local box = self.defs[from.k].box
    if drag.kind == "move" then
      box:ClearAllPoints()
      box:SetPoint("TOPLEFT", content, "TOPLEFT", from.x * cw + (x - drag.x), -from.y * ch + (y - drag.y) - Inset(from.k))
    else
      PutBox(box, { k = from.k, x = from.x, y = (drag.lands or from).y, w = item.w, h = item.h }, cw, ch)
    end
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
    -- the box in hand lies over the others; the free places are for adding, not for now
    local def = self.defs[key]
    def.raised = true
    def.box:SetFrameStrata("HIGH")
    def.box:SetAlpha(0.9)
    for index = 1, self.slotCount or 0 do slots[index]:Hide() end
    self:SetScript("OnUpdate", function() board:Track() end)
  end

  local function StopDrag()
    if not drag then return end
    drag.ok = false
    Drop()
  end

  -- What every box carries while customizing: a light shade, and on top a strip with its name and,
  -- from the right, the x that removes it, the + that adds a part and "Options"
  local function Cover(key)
    local def = board.defs[key]
    if def.Cover then return end
    local cover = CreateFrame("Button", nil, def.box)
    cover:SetAllPoints()
    local level = (def.box:GetFrameLevel() or 1) + 40
    cover:SetFrameLevel(level)
    cover.Shade = cover:CreateTexture(nil, "BACKGROUND")
    cover.Shade:SetAllPoints()
    cover.Shade:SetColorTexture(0, 0, 0, 0.25)
    cover:SetScript("OnMouseDown", function(_, button)
      if button == "LeftButton" then board:Start("move", key) end
    end)
    cover:EnableMouseWheel(true)
    cover:SetScript("OnMouseWheel", Wheel)
    -- the strip: over the title row of the box, which it stands for while customizing; above a box
    -- that has none, in the room that box gives up (PutBox). Dragging it moves the box.
    cover.Strip = CreateFrame("Button", nil, cover)
    cover.Strip:SetPoint(def.bare and "BOTTOMLEFT" or "TOPLEFT", cover, "TOPLEFT", 0, 0)
    cover.Strip:SetPoint(def.bare and "BOTTOMRIGHT" or "TOPRIGHT", cover, "TOPRIGHT", 0, 0)
    cover.Strip:SetHeight(STRIP)
    cover.Strip:SetFrameLevel(level + 4)
    cover.Strip:SetScript("OnMouseDown", function(_, button)
      if button == "LeftButton" then board:Start("move", key) end
    end)
    cover.Strip:EnableMouseWheel(true)
    cover.Strip:SetScript("OnMouseWheel", Wheel)
    cover.Strip.Fill = cover.Strip:CreateTexture(nil, "BACKGROUND")
    cover.Strip.Fill:SetAllPoints()
    cover.Strip.Fill:SetColorTexture(W.GOLD[1] * 0.22, W.GOLD[2] * 0.22, W.GOLD[3] * 0.22, 1) -- (nothing shows through)
    for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
      local line = cover.Strip:CreateTexture(nil, "BORDER")
      line:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.6)
      line:SetPoint(edge[1])
      line:SetPoint(edge[2])
      if edge[3] then line:SetHeight(1) else line:SetWidth(1) end
    end
    cover.Remove = W.Button(cover.Strip, "x", function() board:Remove(key) end, 24, { small = true, pad = 10 })
    cover.Remove:SetPoint("RIGHT", -2, 0)
    W.Tooltip(cover.Remove, L.BOARD_REMOVE)
    cover.Add = W.Button(cover.Strip, "+", function(self)
      if def.onAdd then return def.onAdd(self) end
      W.OpenMenu(self, board:AddItems(key), 180)
    end, 24, { small = true, pad = 10 })
    cover.Add:SetPoint("RIGHT", cover.Remove, "LEFT", -4, 0)
    W.Tooltip(cover.Add, L.BOARD_ADD)
    cover.Gear = W.MenuButton(cover.Strip, L.BOARD_OPTIONS, function() return board:OptionItems(key) end, 90, 160)
    cover.Gear:SetPoint("RIGHT", cover.Add, "LEFT", -4, 0)
    cover.Name = W.Text(cover.Strip, "GameFontNormalSmall", def.name)
    cover.Name:SetPoint("LEFT", 8, 0)
    cover.Name:SetPoint("RIGHT", cover.Gear, "LEFT", -6, 0)
    cover.Name:SetJustifyH("LEFT")
    cover.Name:SetWordWrap(false)
    cover.Grip = CreateFrame("Button", nil, cover)
    cover.Grip:SetSize(20, 20)
    cover.Grip:SetPoint("BOTTOMRIGHT", -2, 2)
    cover.Grip:SetFrameLevel(level + 6)
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

  -- Closes the picker and takes back what it showed (a tab that changes what its boxes are)
  function board:Close()
    ClosePicker()
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
    if self.Tools then self.Tools:Set(self.editing) end
    self:Apply()
  end
  board:SetScript("OnHide", function()
    StopDrag()
    ClosePicker()
  end)

  -- "Customize" at the right end of a page's toolbar, and the presets while customizing (W.EditTools).
  -- presets: { { name, layout or nil for the default, what else it does (a function) or nil } }
  function board:Controls(page, presets)
    self.Tools = W.EditTools(page, function()
      board:SetEditing(not board.editing)
      opts.onChange()
    end, presets and function()
      local items = {}
      for _, preset in ipairs(presets) do
        items[#items + 1] = { text = preset[1], onClick = function()
          if preset[3] then preset[3]() end
          board:Preset(preset[2])
        end }
      end
      return items
    end or nil, L.BOARD_EDIT_TIP)
    self.Edit, self.Presets = self.Tools.Edit, self.Tools.Presets
  end

  return board
end
