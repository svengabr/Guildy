-- Debug commands for gear on the character page (docs/superpowers/specs/2026-11-13-gear-character-page-design.md):
--   /guildy modeltest [raceID sex]  which model calls Forever has, and whether a custom race wears the own gear
--   /guildy craftprobe              whether the game names what a recipe makes without its window
--   /guildy gearshow [name]         the gear slot by slot and the enchant text the tooltip gives
-- They print only when typed.
local _, ns = ...

local GearProbe = {}
ns.GearProbe = GearProbe

local MODEL_CALLS = { "SetUnit", "SetCustomRace", "Undress", "TryOn", "SetSheathed", "SetFacing", "SetPortraitZoom" }
local RACES = { 1, 2, 3, 4, 5, 6, 7, 8, 10, 11 }
local SEXES = { 0, 1, 2, 3 }

local function Say(text) ns.Print(text) end

-- Calls model:method(...) through pcall; prints a failure
local function Call(model, method, ...)
  local fn = model[method]
  if type(fn) ~= "function" then return false end
  local ok, err = pcall(fn, model, ...)
  if not ok then Say(("modeltest: %s failed: %s"):format(method, tostring(err))) end
  return ok
end

local testModel
local cycle = 0 -- a new modeltest stops the running cycle

local function Model()
  if testModel then return testModel end
  local model = CreateFrame("DressUpModel", "GuildyModelTest", UIParent)
  model:SetSize(300, 400)
  model:SetPoint("CENTER")
  model:SetMovable(true)
  model:EnableMouse(true)
  model:RegisterForDrag("LeftButton")
  model:SetScript("OnDragStart", model.StartMoving)
  model:SetScript("OnDragStop", model.StopMovingOrSizing)
  local back = model:CreateTexture(nil, "BACKGROUND")
  back:SetAllPoints()
  back:SetColorTexture(0, 0, 0, 0.6)
  local close = CreateFrame("Button", nil, model, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT")
  close:SetScript("OnClick", function()
    cycle = cycle + 1
    model:Hide()
  end)
  testModel = model
  return model
end

-- Dresses model in the own equipped items (slots 1..19)
local function DressOwn(model)
  local getLink = rawget(_G, "GetInventoryItemLink")
  local count = 0
  for slot = 1, 19 do
    local link = getLink and ns.Try(getLink, "player", slot)
    if link and not ns.IsSecret(link) and Call(model, "TryOn", link) then count = count + 1 end
  end
  return count
end

local function Dress(model, race, sex)
  local ok = Call(model, "SetCustomRace", race, sex)
  Call(model, "Undress")
  local items = DressOwn(model)
  Say(("modeltest: race %d, sex %d: SetCustomRace %s, %d items tried on"):format(race, sex, ok and "ok" or "failed", items))
end

function GearProbe.ModelTest(args)
  local model = Model()
  model:Show()
  cycle = cycle + 1
  local parts = {}
  for _, method in ipairs(MODEL_CALLS) do
    parts[#parts + 1] = method .. " " .. (type(model[method]) == "function" and "yes" or "no")
  end
  Say("modeltest: " .. table.concat(parts, ", "))
  local race, sex = tostring(args or ""):match("^%s*(%d+)%s+(%d+)")
  if race then return Dress(model, tonumber(race), tonumber(sex)) end
  -- without arguments: every race and sex value in turn, 3 s each, to see which gender values work
  local mine, step = cycle, 0
  local function Next()
    if mine ~= cycle or not model:IsShown() then return end
    step = step + 1
    local r, s = RACES[math.floor((step - 1) / #SEXES) + 1], SEXES[(step - 1) % #SEXES + 1]
    if not r then return Say("modeltest: cycle done") end
    Dress(model, r, s)
    C_Timer.After(3, Next)
  end
  Next()
end

-- Equippable: GetItemInfoInstant's 4th return (equip location) is not empty
local function EquipLoc(itemID)
  local instant = (C_Item and rawget(C_Item, "GetItemInfoInstant")) or rawget(_G, "GetItemInfoInstant")
  if not instant then return nil end
  local _, _, _, equipLoc = ns.Try(instant, itemID)
  return equipLoc
end

function GearProbe.CraftProbe()
  local guild, db = ns.GuildData(), ns.DB()
  local own = db and db.ownChars or {}
  local ids, seen = {}, {}
  for key, record in pairs(guild and guild.members or {}) do
    if not own[key] and type(record) == "table" then
      for _, prof in pairs(type(record.profs) == "table" and record.profs or {}) do
        for _, spellID in ipairs(type(prof) == "table" and type(prof.recipes) == "table" and prof.recipes or {}) do
          if #ids < 200 and not seen[spellID] then
            seen[spellID] = true
            ids[#ids + 1] = spellID
          end
        end
      end
    end
  end
  local output = C_TradeSkillUI and rawget(C_TradeSkillUI, "GetRecipeOutputItemData")
  local resolved, equippable, unresolved = 0, 0, {}
  for _, spellID in ipairs(ids) do
    local data = output and ns.Try(output, spellID)
    local itemID = type(data) == "table" and data.itemID
    if type(itemID) == "number" and not ns.IsSecret(itemID) then
      resolved = resolved + 1
      local equipLoc = EquipLoc(itemID)
      if type(equipLoc) == "string" and equipLoc ~= "" then equippable = equippable + 1 end
    elseif #unresolved < 5 then
      unresolved[#unresolved + 1] = tostring(spellID)
    end
  end
  Say(("craftprobe: %d asked, %d resolved (%d %%), %d equippable%s"):format(#ids, resolved,
    #ids > 0 and math.floor(resolved * 100 / #ids + 0.5) or 0, equippable,
    output and "" or " (no C_TradeSkillUI.GetRecipeOutputItemData)"))
  if #unresolved > 0 then Say("craftprobe: not resolved: " .. table.concat(unresolved, ", ")) end
end

-- Left texts of the tooltip of link: { string }, and the path used ("C_TooltipInfo", "GameTooltip" or nil)
local scanTip
function GearProbe.TooltipLines(link)
  local lines = {}
  local info = C_TooltipInfo and rawget(C_TooltipInfo, "GetHyperlink")
  if info then
    local data = ns.Try(info, link)
    if type(data) == "table" and type(data.lines) == "table" then
      for _, line in ipairs(data.lines) do
        local text = type(line) == "table" and line.leftText
        if type(text) == "string" and not ns.IsSecret(text) then lines[#lines + 1] = text end
      end
      return lines, "C_TooltipInfo"
    end
  end
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "GuildyScanTooltip", nil, "GameTooltipTemplate")
  end
  if not (scanTip and scanTip.SetHyperlink) then return lines, nil end
  ns.Try(scanTip.SetOwner, scanTip, UIParent, "ANCHOR_NONE")
  ns.Try(scanTip.ClearLines, scanTip)
  if not pcall(scanTip.SetHyperlink, scanTip, link) then return lines, nil end
  for i = 1, ns.Try(scanTip.NumLines, scanTip) or 0 do
    local region = rawget(_G, "GuildyScanTooltipTextLeft" .. i)
    local text = region and region.GetText and ns.Try(region.GetText, region)
    if type(text) == "string" and not ns.IsSecret(text) then lines[#lines + 1] = text end
  end
  ns.Try(scanTip.Hide, scanTip)
  return lines, "GameTooltip"
end

-- Lines of with that without lacks (duplicates counted)
local function Extra(with, without)
  local count, extra = {}, {}
  for _, text in ipairs(without) do count[text] = (count[text] or 0) + 1 end
  for _, text in ipairs(with) do
    if (count[text] or 0) > 0 then count[text] = count[text] - 1 else extra[#extra + 1] = text end
  end
  return extra
end

-- The unit showing name: "player" for the own character, "target" when the target is that member
local function UnitOf(name)
  if name == "" or ns.Names.Same(name, ns.PlayerName()) then return "player", ns.PlayerName() end
  if UnitExists("target") then
    local targetName = ns.Names.FromUnit(UnitName("target"))
    if targetName ~= "" and ns.Names.Same(targetName, name) then return "target", targetName end
  end
  return nil, name
end

-- Live links of name (self or the target)
function GearProbe.GearShow(name)
  name = tostring(name or ""):match("^%s*(.-)%s*$")
  local unit, shown = UnitOf(name)
  if not unit then
    return Say(("gearshow %s: not the own character and not the target"):format(shown))
  end
  local getLink = rawget(_G, "GetInventoryItemLink")
  local getInfo = rawget(_G, "GetItemInfo") or (C_Item and C_Item.GetItemInfo)
  Say(("gearshow %s (%s, live):"):format(shown, unit))
  local path
  for slot = 1, 19 do
    local link = getLink and ns.Try(getLink, unit, slot)
    if ns.IsSecret(link) then return Say("gearshow: secret link, read stopped") end
    local loaded = link and getInfo and ns.Try(getInfo, link) ~= nil
    Say(("  %d: %s, item info %s"):format(slot, tostring(link), link and (loaded and "yes" or "no") or "-"))
    local id, enchant = type(link) == "string" and link:match("item:(%-?%d+):(%-?%d*)")
    enchant = tonumber(enchant)
    if id and enchant and enchant ~= 0 then
      local with, used = GearProbe.TooltipLines("item:" .. id .. ":" .. enchant)
      local without = GearProbe.TooltipLines("item:" .. id)
      path = path or used
      local extra = Extra(with, without)
      Say(("     enchant %d: %s"):format(enchant, #extra > 0 and table.concat(extra, " | ") or "no line"))
    end
  end
  Say("gearshow: tooltip path " .. tostring(path or "not used"))
end
