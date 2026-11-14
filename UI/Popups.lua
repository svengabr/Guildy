-- Member context menu (whisper, group invite, rank, removal, notes in Blizzard's window), the member tooltip and the
-- guild-invite box with suggestions.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

-- "84/150", or "laut Notiz" for professions only known from a guild note
function UI.ProfLevel(prof)
  if prof.rank then return prof.rank .. (prof.max and ("/" .. prof.max) or "") end
  if prof.src == "note" then return "|cff999999–|r" end
  return "?"
end

local function SpecId(prof)
  local spec = type(prof) == "table" and prof.spec
  return type(spec) == "table" and type(spec.id) == "number" and spec.id > 0 and spec.id or nil
end

-- Short tag of a profession's specialization ("Goblin"), nil when none is known
function UI.SpecTag(prof)
  local id = SpecId(prof)
  if not id then return nil end
  local key = "SPEC_" .. id
  local text = ns.L[key]
  return text ~= key and text or nil
end

-- Full name of a profession's specialization in the client's language (the spell's name)
function UI.SpecName(prof)
  local id = SpecId(prof)
  return id and (ns.TradeSkill.RecipeName(id) or UI.SpecTag(prof)) or nil
end

-- Time left on a cooldown: "ready" in green, else "in 14 h"
function UI.CooldownLeft(entry)
  local L = ns.L
  if entry.left <= 0 then return "|cff4ce64c" .. L.CD_READY .. "|r" end
  local unit, count = ns.Cooldowns.Span(entry.left)
  return L.CD_LEFT:format((unit == "m" and L.CD_M or unit == "h" and L.CD_H or L.SPAN_D):format(count))
end

-- A member's cooldowns { { spell, readyAt, left } }, of one profession or all (skillLine nil), and when
-- they were read; nil when nothing is known of them
function UI.CooldownsOf(m, skillLine)
  local guild = ns.GuildData()
  local book = guild and guild.cooldowns
  local list = book and ns.Cooldowns.Of(book, m.key, ns.Now())
  if not list then return nil end
  local watched = ns.Cooldowns.Watched(ns.DB() and ns.DB().cooldownSpells)
  local out = {}
  for _, entry in ipairs(list) do
    if not skillLine or watched[entry.spell] == skillLine then out[#out + 1] = entry end
  end
  return out, book[m.key].ts
end

-- "as of 3 h ago" for a reading older than an hour, nil for a fresh one
function UI.CooldownAge(ts)
  local age = ns.Now() - (ts or 0)
  if age < 3600 then return nil end
  return ns.L.CD_AS_OF:format(ns.Roster.LastOnlineText({ online = false, daysOffline = age / 86400 }))
end

function UI.Whisper(name)
  local tell = rawget(_G, "ChatFrame_SendTell") or (ChatFrameUtil and ChatFrameUtil.SendTell)
  if tell then pcall(tell, name) end
end

-- A 1x1 frame at the mouse, for menus opened where no frame sits (names in the chat)
local cursorAnchor
function UI.CursorAnchor()
  cursorAnchor = cursorAnchor or CreateFrame("Frame", nil, UIParent)
  cursorAnchor:SetSize(1, 1)
  local x, y = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale() or 1
  cursorAnchor:ClearAllPoints()
  cursorAnchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (x or 0) / scale, (y or 0) / scale)
  return cursorAnchor
end

-- WoW has no clipboard access: a small box with the text selected, Ctrl+C copies and closes it
local copyBox
function UI.CopyText(text)
  local L = ns.L
  if not copyBox then
    copyBox = W.Box(UIParent, 0.06, 0.95)
    copyBox:SetFrameStrata("DIALOG")
    copyBox:SetSize(260, 74)
    copyBox:EnableMouse(true)
    copyBox.Title = W.Text(copyBox, "GameFontNormalSmall", L.COPY_HINT)
    copyBox.Title:SetPoint("TOP", 0, -12)
    copyBox.Edit = W.EditBox(copyBox, 220)
    copyBox.Edit:SetPoint("TOP", copyBox.Title, "BOTTOM", 0, -10)
    copyBox.Edit:SetScript("OnEscapePressed", function() copyBox:Hide() end)
    copyBox.Edit:SetScript("OnEnterPressed", function() copyBox:Hide() end)
    -- typing must not change the text: put it back and select it again
    copyBox.Edit:SetScript("OnTextChanged", function(self, user)
      if user and self:GetText() ~= copyBox.text then self:SetText(copyBox.text); self:HighlightText() end
    end)
    copyBox.Edit:SetScript("OnKeyDown", function(_, key)
      if key == "C" and IsControlKeyDown() then C_Timer.After(0, function() copyBox:Hide() end) end
    end)
    copyBox:SetScript("OnHide", function() copyBox.Edit:ClearFocus() end)
    tinsert(UISpecialFrames, "GuildyCopyBox")
    _G.GuildyCopyBox = copyBox
  end
  copyBox.text = text
  copyBox:ClearAllPoints()
  copyBox:SetPoint("TOPLEFT", UI.CursorAnchor(), "TOPLEFT", -20, 20)
  copyBox:SetClampedToScreen(true)
  copyBox:Show()
  copyBox.Edit:SetText(text)
  copyBox.Edit:SetFocus()
  copyBox.Edit:HighlightText()
end

-- Left click on a member anywhere: the character page; shift-click whispers
function UI.MemberClick(m)
  if not m then return end
  if IsShiftKeyDown() then UI.Whisper(m.fullName) else UI.ShowMember(m) end
end

-- Context menu for a roster member (right click anywhere). Officers get one step up and one step down,
-- each naming the rank it leads to (one rank per click, see UI/Commands.lua). anchor defaults to the
-- mouse position.
function UI.MemberMenu(m, anchor)
  local L, R = ns.L, ns.Roster
  local can = R.Can()
  local items = {
    { text = W.ClassName(m.name, m.classFile), isTitle = true },
    { text = L.MEMBER_OPEN_PAGE, onClick = function() UI.ShowMember(m) end },
    { text = L.WHISPER, onClick = function() UI.Whisper(m.fullName) end, disabled = not m.online },
    { text = L.GROUP_INVITE, onClick = function() R.GroupInvite(m) end, disabled = not m.online },
    { text = L.COPY_NAME, onClick = function() UI.CopyText(m.name) end },
  }
  -- professions that are wrong: thrown away, the next reading starts from nothing
  items[#items + 1] = { text = L.MEMBER_FORGET_PROFS, onClick = function()
    if ns.TradeSkill.Forget(m) then ns.Print(L.MEMBER_FORGOT_PROFS:format(m.name)) end
  end }
  local rights = R.Rights(m)
  -- rank and notes: Blizzard's own member panel beside the character page (UI/Notes.lua)
  if can.editPublic or can.editOfficer then
    -- notes are edited on the character page (UI/Notes.lua)
    items[#items + 1] = { text = L.NOTES_IN_BLIZZARD, onClick = function() UI.ShowMember(m) end }
  end
  -- removal last and red, always behind a confirmation
  if can.remove then
    items[#items + 1] = { text = L.REMOVE, disabled = not rights.remove, color = { 1, 0.25, 0.2 },
      onClick = function() UI.ConfirmRemove(m) end }
  end
  W.OpenMenu(anchor or UI.CursorAnchor(), items, 210)
end

-- Where a member's tooltip stands (settings.tooltipAnchor, Guildy's options):
--   "cursor"  = at the mouse (default)
--   "window"  = beside Guildy's window at the row's height, so it never covers the list
--   "row"     = beside the hovered row
--   "default" = the game's own spot
UI.TOOLTIP_ANCHORS = { "cursor", "window", "row", "default" }
function UI.TooltipAnchor()
  local chosen = ns.Settings().tooltipAnchor
  for _, known in ipairs(UI.TOOLTIP_ANCHORS) do
    if chosen == known then return chosen end
  end
  return "cursor"
end

-- The member tooltip: a panel of Guildy's own (W.FloatingPanel, the look of the score panel and the item
-- tooltips), laid out like a card. One column: name, who and where, the facts with their labels in a
-- column of their own, professions, cooldowns, the click hint, with hairlines between the groups. Every
-- caller hides it with GameTooltip:Hide() (hooked below), as it did when it was the game's tooltip.
local TIP_PAD, TIP_MIN, TIP_MAX = 12, 290, 460
local MUTED, DIM, HEAD = { 0.60, 0.56, 0.47 }, { 0.47, 0.44, 0.37 }, { 1, 0.82, 0 }
local tip

-- The icon of each class's three talent trees in tab order, and of the feral druid's two forms
local TREE_ICONS = {
  WARRIOR = { "Ability_Rogue_Eviscerate", "Ability_Warrior_InnerRage", "INV_Shield_06" },
  PALADIN = { "Spell_Holy_HolyBolt", "Spell_Holy_DevotionAura", "Spell_Holy_AuraOfLight" },
  HUNTER = { "Ability_Hunter_BeastTaming", "Ability_Marksmanship", "Ability_Hunter_SwiftStrike" },
  ROGUE = { "Ability_Rogue_Eviscerate", "Ability_BackStab", "Ability_Stealth" },
  PRIEST = { "Spell_Holy_WordFortitude", "Spell_Holy_HolyBolt", "Spell_Shadow_ShadowWordPain" },
  SHAMAN = { "Spell_Nature_Lightning", "Spell_Nature_LightningShield", "Spell_Nature_MagicImmunity" },
  MAGE = { "Spell_Holy_MagicalSentry", "Spell_Fire_FireBolt02", "Spell_Frost_FrostBolt02" },
  WARLOCK = { "Spell_Shadow_DeathCoil", "Spell_Shadow_Metamorphosis", "Spell_Shadow_RainOfFire" },
  DRUID = { "Spell_Nature_StarFall", "Ability_Racial_BearForm", "Spell_Nature_HealingTouch" },
}
local FORM_ICONS = { DRUID_CAT = "Ability_Druid_CatForm", DRUID_BEAR = "Ability_Racial_BearForm" }
UI.TREE_ICONS = TREE_ICONS

-- The talent spec of m as an icon and the tree's name, nil when it is not known (Game/Talents.lua)
function UI.TalentSpec(m)
  local guild = ns.GuildData()
  local tal = guild and type(guild.talents) == "table" and guild.talents[m.key] or nil
  if type(tal) ~= "table" or not ns.GameGear then return nil end
  local rec = type(guild.gear) == "table" and guild.gear[m.key] or nil
  local spec, tree = ns.GameGear.SpecFor(m, rec, tal)
  if not spec then return nil end
  local icons = TREE_ICONS[m.classFile]
  local icon = FORM_ICONS[spec] or (icons and icons[tree])
  local name = ns.GameTalents and ns.GameTalents.TreeName(m.classFile, tree)
  if name and spec == "DRUID_CAT" then name = ns.L.TALENT_CAT:format(name)
  elseif name and spec == "DRUID_BEAR" then name = ns.L.TALENT_BEAR:format(name) end
  return { icon = icon and ("Interface\\Icons\\" .. icon) or nil, name = name }
end

local function Acquire(pool, make)
  pool.used = pool.used + 1
  local object = pool[pool.used]
  if not object then
    object = make()
    pool[pool.used] = object
  end
  object:Show()
  return object
end

local function Tip()
  if tip then return tip end
  tip = W.FloatingPanel(W.Box(UIParent))
  tip:Hide()
  tip.texts, tip.icons, tip.rules = { used = 0 }, { used = 0 }, { used = 0 }
  -- gone with the mouse: callers hide the game's tooltip on leave; this is the net under that
  tip:SetScript("OnUpdate", function(self)
    local owner = self.owner
    if owner and (not owner:IsVisible() or (owner.IsMouseOver and not owner:IsMouseOver())) then self:Hide() end
  end)
  local hook = rawget(_G, "hooksecurefunc")
  if hook and GameTooltip then
    hook(GameTooltip, "Hide", function() if not tip.showing then tip:Hide() end end)
    hook(GameTooltip, "SetOwner", function() if not tip.showing then tip:Hide() end end)
  end
  return tip
end
UI.MemberTip = function() return tip end

-- Building the card: rows first, then one layout pass once the width is known
local Card = {}
Card.__index = Card

local function NewCard(frame)
  for _, pool in pairs({ frame.texts, frame.icons, frame.rules }) do
    for i = 1, pool.used do pool[i]:Hide() end
    pool.used = 0
  end
  return setmetatable({ frame = frame, rows = {} }, Card)
end

function Card:Text(text, template, color)
  local frame = self.frame
  local fs = Acquire(frame.texts, function() return W.Text(frame, "GameTooltipText") end)
  fs:SetFontObject(template or "GameTooltipText")
  fs:SetWidth(0)
  fs:SetWordWrap(false)
  fs:SetJustifyH("LEFT")
  fs:SetText(text or "")
  local c = color or { 1, 1, 1 }
  fs:SetTextColor(c[1], c[2], c[3])
  return fs
end

function Card:Icon(path, size, atlas)
  local frame = self.frame
  local icon = Acquire(frame.icons, function() return frame:CreateTexture(nil, "ARTWORK") end)
  if atlas then
    icon:SetAtlas(atlas)
    icon:SetTexCoord(0, 1, 0, 1)
  else
    icon:SetTexture(path)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  end
  icon:SetSize(size, size)
  return icon
end

-- A line: icons, then the left text, a right text at the right edge; gap = space above it, wrap = may
-- take more lines where the tooltip is at its widest, free = does not widen the tooltip
function Card:Line(left, right, opts)
  opts = opts or {}
  self.rows[#self.rows + 1] = { kind = "line", left = left, right = right, icons = opts.icons, gap = opts.gap or 0,
    wrap = opts.wrap, free = opts.free }
end

-- A label in the muted column and its value beside it (wraps)
function Card:Fact(label, value)
  self.rows[#self.rows + 1] = { kind = "fact", left = self:Text(label, "GameTooltipText", MUTED),
    right = self:Text(value), gap = 2 }
end

function Card:Rule()
  self.rows[#self.rows + 1] = { kind = "rule" }
end

local function Width(fs) return fs and fs:GetStringWidth() or 0 end

function Card:Layout()
  local frame, width, labelW = self.frame, TIP_MIN, 0
  for _, row in ipairs(self.rows) do
    if row.kind == "fact" then labelW = math.max(labelW, Width(row.left)) end
  end
  for _, row in ipairs(self.rows) do
    local need = 0
    if row.kind == "fact" then
      need = labelW + 14 + Width(row.right)
    elseif row.kind == "line" and not row.free then
      -- as the layout below places them: icons 4 apart and 2 more before the text, 12 before a right text
      for _, icon in ipairs(row.icons or {}) do need = need + icon:GetWidth() + 4 end
      if row.icons and #row.icons > 0 then need = need + 2 end
      need = need + Width(row.left) + (row.right and (Width(row.right) + 12) or 0)
    end
    width = math.max(width, need + 2 * TIP_PAD + 4) -- (+4: the font's rounding never breaks a line that fits)
  end
  width = math.min(TIP_MAX, math.ceil(width))
  local inner, y = width - 2 * TIP_PAD, -TIP_PAD
  for _, row in ipairs(self.rows) do
    if row.kind == "rule" then
      local rule = Acquire(frame.rules, function()
        local t = frame:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.3)
        t:SetHeight(1)
        return t
      end)
      y = y - 8
      rule:ClearAllPoints()
      rule:SetPoint("TOPLEFT", frame, "TOPLEFT", TIP_PAD, y)
      rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -TIP_PAD, y)
      y = y - 9
    else
      y = y - row.gap
      local x, height = TIP_PAD, 0
      for _, icon in ipairs(row.icons or {}) do
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
        x = x + icon:GetWidth() + 4
        height = math.max(height, icon:GetHeight())
      end
      if x > TIP_PAD then x = x + 2 end
      local rightW = Width(row.right)
      if row.right then
        row.right:ClearAllPoints()
        if row.kind == "fact" then
          row.right:SetPoint("TOPLEFT", frame, "TOPLEFT", TIP_PAD + labelW + 14, y)
          row.right:SetWidth(math.max(1, inner - labelW - 14))
          row.right:SetWordWrap(true)
          height = math.max(height, row.right:GetStringHeight())
        else
          local offset = height > 0 and math.max(0, (height - row.right:GetStringHeight()) / 2) or 0
          row.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -TIP_PAD, y - offset)
        end
      end
      if row.left then
        local room = inner - (x - TIP_PAD) - (rightW > 0 and rightW + 12 or 0)
        if row.kind == "fact" then room = labelW + 4 end
        row.left:SetWidth(math.max(1, room))
        row.left:SetWordWrap(row.wrap == true)
        local offset = height > 0 and math.max(0, (height - row.left:GetStringHeight()) / 2) or 0
        row.left:ClearAllPoints()
        row.left:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y - offset)
        height = math.max(height, row.left:GetStringHeight())
      end
      y = y - height
    end
  end
  frame:SetSize(width, math.ceil(-y + TIP_PAD))
end

local TOOLTIP_ROOM = 320 -- what a member tooltip needs beside the window
local function Place(frame, owner)
  local mode = UI.TooltipAnchor()
  frame:ClearAllPoints()
  if mode == "default" then
    frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -13, 64)
    return
  end
  local window = UI.frame
  local target = mode == "row" and owner or window
  local left, right = target and target:GetLeft(), target and target:GetRight()
  local screen = UIParent:GetWidth()
  if mode == "cursor" or not (window and left and right and screen) then
    -- right of and below the pointer; above it, or left of it, where the screen has no room
    local getCursor = rawget(_G, "GetCursorPosition")
    local x, y
    if getCursor then x, y = getCursor() end
    local scale = UIParent:GetEffectiveScale() or 1
    x, y = (x or 0) / scale, (y or 0) / scale
    local w, h = frame:GetWidth(), frame:GetHeight()
    local px = (screen and x + 18 + w > screen) and (x - 12 - w) or (x + 18)
    local py = (y - 14 - h < 0) and (y + 8 + h) or (y - 14)
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", px, py)
    return
  end
  -- at the row's height; right of the target where there is room (past the window's side tabs), else left
  local top, targetTop = owner:GetTop(), target:GetTop()
  local y = (top and targetTop) and (top - targetTop) or 0
  local scale = target.GetEffectiveScale and UIParent.GetEffectiveScale and target:GetEffectiveScale()
  local base = scale and UIParent:GetEffectiveScale()
  local factor = (type(scale) == "number" and type(base) == "number" and base > 0) and scale / base or 1
  y = y * factor -- the tooltip's units, not the window's (UI.SetScale)
  local gap = mode == "row" and 8 or 66
  if mode == "row" then
    -- a row at the window's right edge (the chat's online list): the tooltip on its left
    if left * factor >= TOOLTIP_ROOM then
      frame:SetPoint("TOPRIGHT", target, "TOPLEFT", -8, y)
    else
      frame:SetPoint("TOPLEFT", target, "TOPRIGHT", 8, y)
    end
  elseif screen - right * factor >= TOOLTIP_ROOM + gap then
    frame:SetPoint("TOPLEFT", target, "TOPRIGHT", gap, y)
  else
    frame:SetPoint("TOPRIGHT", target, "TOPLEFT", -8, y)
  end
end

local function Hex(c) return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255) end

-- Tooltip for a roster member (owner frame given); hint replaces the default click hint
function UI.MemberTooltip(owner, m, hint)
  local L, SEP = ns.L, ns.L.SEP
  -- the click on this member also picks them in Blizzard's list, for their notes (UI/Notes.lua)
  if UI.Notes then UI.Notes.HoverMember(owner, m, hint) end
  local frame = Tip()
  frame.showing = true
  GameTooltip:Hide()
  frame.showing = false
  local card = NewCard(frame)

  -- the name, then race, class and talent tree as icons before "Stufe 60 Priesterin · Offizier" (the tree only as its icon)
  card:Line(card:Text(W.ClassName(m.name, m.classFile), "GameTooltipHeaderText"))
  local icons, who = {}, { L.LEVEL_CLASS:format(m.level or 0, m.className or "") }
  local race = UI.RaceInfo and UI.RaceInfo(m)
  if race and (race.icon or race.atlas) then icons[#icons + 1] = card:Icon(race.icon, 16, race.atlas) end
  local coords = rawget(_G, "CLASS_ICON_TCOORDS")
  local c = m.classFile and coords and coords[m.classFile]
  if c then
    local icon = card:Icon("Interface\\TargetingFrame\\UI-Classes-Circles", 16)
    icon:SetTexCoord(c[1], c[2], c[3], c[4])
    icons[#icons + 1] = icon
  end
  local spec = UI.TalentSpec(m)
  if spec and spec.icon then icons[#icons + 1] = card:Icon(spec.icon, 16) end
  if m.rank and m.rank ~= "" then who[#who + 1] = m.rank end
  card:Line(card:Text(table.concat(who, SEP), "GameTooltipText", MUTED), nil, { icons = icons, gap = 4, wrap = true })
  -- online and where, or when last seen
  local status
  if m.online then
    status = "|cff4ce64c" .. L.ONLINE .. "|r" .. ((m.zone and m.zone ~= "") and (Hex(MUTED) .. SEP .. "|r" .. m.zone) or "")
  else
    status = Hex(MUTED) .. L.LAST_ONLINE .. "|r  " .. ns.Roster.LastOnlineText(m)
  end
  card:Line(card:Text(status), nil, { gap = 4 })

  -- the facts, each only with a value
  local facts = {}
  local since = ns.Roster.TenureText(m, true)
  if since then facts[#facts + 1] = { L.MEMBER_SINCE, since } end
  local guildy = UI.GuildyVersionText and UI.GuildyVersionText(m)
  if guildy then facts[#facts + 1] = { L.COL_GUILDY, guildy } end
  if m.note and m.note ~= "" then facts[#facts + 1] = { L.NOTE, m.note } end
  if m.officerNote and m.officerNote ~= "" and ns.Roster.Can().viewOfficer then
    facts[#facts + 1] = { L.OFFICER_NOTE, m.officerNote }
  end
  if #facts > 0 then
    card:Rule()
    for _, fact in ipairs(facts) do card:Fact(fact[1], fact[2]) end
  end

  local record = ns.TradeSkill.Record(m)
  if record and next(record.profs or {}) then
    card:Rule()
    card:Line(card:Text(L.PROFESSIONS, "GameTooltipText", HEAD))
    for _, skillLine in ipairs(ns.Professions.ORDER) do
      local prof = record.profs[skillLine]
      if prof then
        local tag = UI.SpecTag(prof)
        local full = type(prof.rank) == "number" and type(prof.max) == "number" and prof.rank >= prof.max
        card:Line(card:Text(ns.TradeSkill.Name(skillLine) .. (tag and ("  " .. Hex(DIM) .. tag .. "|r") or "")),
          card:Text(UI.ProfLevel(prof), "GameTooltipText", full and { 1, 1, 1 } or MUTED),
          { icons = { card:Icon(ns.Professions.ICONS[skillLine], 16) }, gap = 5 })
      end
    end
  end

  local cooldowns, readAt = UI.CooldownsOf(m)
  if cooldowns and #cooldowns > 0 then
    card:Line(card:Text(L.COOLDOWNS, "GameTooltipText", HEAD),
      card:Text(UI.CooldownAge(readAt) or "", "GameTooltipTextSmall", DIM), { gap = 10 })
    for _, entry in ipairs(cooldowns) do
      local left = UI.CooldownLeft(entry)
      card:Line(card:Text(ns.TradeSkill.RecipeName(entry.spell) or ("#" .. entry.spell)),
        card:Text(entry.left > 0 and ("|cffff9a5a" .. left .. "|r") or left), { gap = 3 })
    end
  end

  card:Rule()
  card:Line(card:Text(hint or L.MEMBER_CLICK_HINT, "GameTooltipTextSmall", DIM), nil, { wrap = true })
  card:Layout()
  frame.owner = owner
  Place(frame, owner)
  frame:Show()
end

-- Guild invite: Blizzard's invite dialog (UI/Commands.lua) with the unguilded target filled in and
-- recent whisperers as suggestions

local function TargetSuggestion()
  if not UnitExists("target") or not UnitIsPlayer("target") or UnitIsUnit("target", "player") then return nil end
  if GetGuildInfo("target") then return nil end
  local name = (rawget(_G, "GetUnitName") and GetUnitName("target", true)) or UnitName("target")
  if ns.IsSecret(name) then return nil end -- names in instances can be secret
  return name
end

function UI.InviteAction()
  local L = ns.L
  local target = TargetSuggestion()
  local suggestions = {}
  if target then suggestions[#suggestions + 1] = { label = L.INVITE_TARGET:format(ns.Names.Normalize(target)), value = target } end
  for _, w in ipairs(ns.Chat.RecentWhispers()) do
    if #suggestions < 5 and not (target and ns.Names.Same(w.full, target)) then
      suggestions[#suggestions + 1] = { label = L.INVITE_WHISPERED:format(w.name), value = w.full }
    end
  end
  return UI.Action.InviteWith(target, suggestions)
end