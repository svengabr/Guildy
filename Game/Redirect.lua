-- Sends the guild window key (J, TOGGLEGUILDTAB) and the guild micro button to Guildy by wrapping the
-- global ToggleGuildFrame. Safety net: when Blizzard's communities window opens on the guild anyway,
-- it is closed and Guildy opens instead (out of combat only). ns.OpenBlizzard() opens the Blizzard
-- window on purpose (communities, rank editor) without being redirected.
local _, ns = ...

local Redirect = {}
ns.Redirect = Redirect

local bypass = false
local original
local hooked = false

local function GuildClubShown(frame)
  local guildClub = C_Club and ns.Try(C_Club.GetGuildClubId)
  if not guildClub then return false end
  local selected = frame.GetSelectedClubId and ns.Try(frame.GetSelectedClubId, frame)
  return selected == nil or selected == guildClub
end

local function HookCommunities()
  local frame = rawget(_G, "CommunitiesFrame")
  if hooked or not frame then return end
  hooked = true
  frame:HookScript("OnShow", function(self)
    if bypass or not IsInGuild() or InCombatLockdown() then return end
    if not GuildClubShown(self) then return end
    C_Timer.After(0, function()
      if bypass or InCombatLockdown() then return end
      local hide = rawget(_G, "HideUIPanel")
      if hide then pcall(hide, self) else self:Hide() end
      ns.UI.Show()
    end)
  end)
  frame:HookScript("OnHide", function() bypass = false end)
end

function Redirect.Install()
  original = rawget(_G, "ToggleGuildFrame")
  if type(original) == "function" then
    _G.ToggleGuildFrame = function(...)
      if bypass or not IsInGuild() then return original(...) end
      ns.UI.Toggle()
    end
  end
  HookCommunities()
end

-- ADDON_LOADED of Blizzard's load-on-demand communities UI
function Redirect.OnAddonLoaded(name)
  if name == "Blizzard_Communities" then HookCommunities() end
end

function ns.OpenBlizzard()
  bypass = true
  ns.UI.Hide()
  local toggle = rawget(_G, "ToggleCommunitiesFrame") or original
  if toggle then pcall(toggle) end
  HookCommunities()
  local frame = rawget(_G, "CommunitiesFrame")
  if not (frame and frame:IsShown()) then bypass = false end
end

-- Blizzard's rank / permission editor
function ns.OpenGuildControl()
  local load = (C_AddOns and C_AddOns.LoadAddOn) or rawget(_G, "LoadAddOn")
  if load then pcall(load, "Blizzard_GuildControlUI") end
  local frame = rawget(_G, "GuildControlUI")
  local show = rawget(_G, "ShowUIPanel")
  if frame and show then pcall(show, frame) elseif frame then frame:Show() end
end
