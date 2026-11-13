-- The banner for a guild member who has reached the top level (Game/Ding.lua). A dark band across the
-- upper middle of the screen, so the texts stand on any scenery, closed by two gold hairlines; on the
-- upper one sits a seal with the level. Under it the name, large and in the class colour, and a line of
-- text. The seal drops in, the hairlines run outward from it, then name and text rise into place. With
-- the game's level-up sound. It hangs on the screen, not on Guildy's window, and is shown whether or not
-- that is open. Several are shown one after the other.
local _, ns = ...

local UI = ns.UI
local W = ns.Widgets

local WIDTH, HEIGHT = 780, 132
local SEAL = 50              -- side of the seal, a square standing on its corner
local SEAL_HALF = SEAL * 0.71 -- half its diagonal: from its middle to a corner
local ENTER, HOLD, FADE_OUT = 1.1, 5, 1
local LEVEL_UP_SOUND = 888 -- SOUNDKIT.LEVEL_UP, for clients without the table
local QUARTER = math.pi / 4
local banner
local queue = {}

local function Large(label, size)
  local font, _, flags = label:GetFont()
  if font then label:SetFont(font, size, flags or "") end -- the font of the language, only larger
end

-- A texture of one colour that fades from alpha a1 (left) to a2 (right)
local function Fade(parent, layer, r, g, b, a1, a2)
  local texture = parent:CreateTexture(nil, layer)
  texture:SetColorTexture(1, 1, 1, 1)
  local color = rawget(_G, "CreateColor")
  if not (color and pcall(texture.SetGradient, texture, "HORIZONTAL", color(r, g, b, a1), color(r, g, b, a2))) then
    -- clients before the colour objects; without either the texture is plain
    if not pcall(texture.SetGradientAlpha, texture, "HORIZONTAL", r, g, b, a1, r, g, b, a2) then
      texture:SetColorTexture(r, g, b, math.max(a1, a2))
    end
  end
  return texture
end

local function Square(parent, layer, sublevel, size, r, g, b)
  local texture = parent:CreateTexture(nil, layer, nil, sublevel)
  texture:SetColorTexture(r, g, b, 1)
  texture:SetSize(size, size)
  texture:SetPoint("CENTER")
  texture:SetRotation(QUARTER)
  return texture
end

-- 0..1 over the time from start to finish, fast first and slower toward the end
local function Ease(t, start, finish)
  if t <= start then return 0 end
  if t >= finish then return 1 end
  return 1 - 2 ^ (-10 * (t - start) / (finish - start))
end

local Next

-- Everything at its place for time t since the banner came up
local function Place(self, t)
  local seal = Ease(t, 0, 0.35)
  self.Seal:SetAlpha(seal)
  self.Seal:SetScale(1.6 - 0.6 * seal)
  local lines = Ease(t, 0.15, 0.9)
  self.Band:SetAlpha(lines)
  for _, line in ipairs(self.Lines) do line:SetWidth(math.max(1, line.full * lines)) end
  local name = Ease(t, 0.3, 0.9)
  self.Name:SetAlpha(name)
  self.Name:SetPoint("TOP", 0, -(SEAL_HALF + 8) - 12 * (1 - name))
  self.Text:SetAlpha(Ease(t, 0.5, ENTER))
end

local function OnUpdate(self, elapsed)
  self.t = self.t + elapsed
  local t = self.t
  if t >= ENTER + HOLD + FADE_OUT then
    self:Hide()
    Next()
    return
  end
  if t <= ENTER + 0.1 then Place(self, t) end
  self:SetAlpha(t < ENTER + HOLD and 1 or 1 - (t - ENTER - HOLD) / FADE_OUT)
end

local function Build()
  local L = ns.L
  local gold = W.GOLD
  banner = CreateFrame("Frame", "GuildyDing", UIParent)
  banner:SetSize(WIDTH, HEIGHT)
  banner:SetPoint("TOP", 0, -150)
  banner:SetFrameStrata("HIGH")
  banner:EnableMouse(false)
  banner:Hide()

  -- the band: dark in the middle, gone at both ends
  banner.Band = CreateFrame("Frame", nil, banner)
  banner.Band:SetAllPoints()
  local left = Fade(banner.Band, "BACKGROUND", 0, 0, 0, 0, 0.72)
  left:SetPoint("TOPLEFT")
  left:SetPoint("BOTTOMRIGHT", banner.Band, "BOTTOM")
  local right = Fade(banner.Band, "BACKGROUND", 0, 0, 0, 0.72, 0)
  right:SetPoint("TOPRIGHT")
  right:SetPoint("BOTTOMLEFT", banner.Band, "BOTTOM")

  -- everything else lies on a frame of its own above the band: a child frame is drawn over what its
  -- parent holds, so on the banner itself the band would cover the texts
  local content = CreateFrame("Frame", nil, banner)
  content:SetAllPoints()
  content:SetFrameLevel(banner.Band:GetFrameLevel() + 1)

  -- four hairlines, each growing from the middle outward: the upper two start at the seal's corners
  banner.Lines = {}
  local function Line(point, relPoint, x, full, a1, a2)
    local line = Fade(content, "ARTWORK", gold[1], gold[2], gold[3], a1, a2)
    line:SetHeight(2)
    line:SetPoint(point, banner, relPoint, x, 0)
    line.full = full
    banner.Lines[#banner.Lines + 1] = line
  end
  Line("RIGHT", "TOP", -SEAL_HALF - 6, WIDTH / 2 - SEAL_HALF - 6, 0, 1)
  Line("LEFT", "TOP", SEAL_HALF + 6, WIDTH / 2 - SEAL_HALF - 6, 1, 0)
  Line("RIGHT", "BOTTOM", 0, WIDTH / 2 - 90, 0, 0.6)
  Line("LEFT", "BOTTOM", 0, WIDTH / 2 - 90, 0.6, 0)

  -- the seal: a gold square on its corner, dark inside, the level in it
  banner.Seal = CreateFrame("Frame", nil, content)
  banner.Seal:SetSize(SEAL, SEAL)
  banner.Seal:SetPoint("CENTER", banner, "TOP")
  Square(banner.Seal, "BORDER", 0, SEAL, gold[1], gold[2], gold[3])
  Square(banner.Seal, "BORDER", 1, SEAL - 5, 0.07, 0.06, 0.05)
  banner.Level = W.Text(banner.Seal, "GameFontNormalLarge", tostring(ns.Census.MAX_LEVEL))
  banner.Level:SetPoint("CENTER", 0, -1)
  banner.Level:SetTextColor(1, 0.86, 0.45)
  Large(banner.Level, 24)

  banner.Name = W.Text(content, "GameFontNormalHuge")
  banner.Name:SetPoint("TOP", 0, -(SEAL_HALF + 8))
  banner.Name:SetJustifyH("CENTER")
  banner.Name:SetShadowOffset(2, -2)
  banner.Name:SetShadowColor(0, 0, 0, 0.9)
  Large(banner.Name, 46)
  banner.Text = W.Text(content, "GameFontHighlightLarge", L.DING_TEXT)
  banner.Text:SetPoint("TOP", banner.Name, "BOTTOM", 0, -6)
  banner.Text:SetJustifyH("CENTER")
  banner.Text:SetTextColor(0.93, 0.88, 0.76) -- the gold's own light tone, not plain white
  Large(banner.Text, 17)
  banner:SetScript("OnUpdate", OnUpdate)
end

function Next()
  local m = table.remove(queue, 1)
  if not m then return end
  if not banner then Build() end
  banner.Name:SetText(m.name or "")
  banner.Name:SetTextColor(W.ClassColor(m.classFile))
  banner.t = 0
  Place(banner, 0)
  banner:SetAlpha(1)
  banner:Show()
  local play, kit = rawget(_G, "PlaySound"), rawget(_G, "SOUNDKIT")
  if play then pcall(play, kit and kit.LEVEL_UP or LEVEL_UP_SOUND, "Master") end
end

-- Shows the banner for member m (name, classFile), after the ones already waiting
function UI.ShowDing(m)
  if type(m) ~= "table" then return end
  queue[#queue + 1] = m
  if not (banner and banner:IsShown()) then Next() end
end
