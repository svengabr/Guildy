-- Puts Guildy on the guild window key (J) without touching Blizzard's code: every key bound to
-- TOGGLEGUILDTAB gets a temporary override binding that clicks GuildyToggleButton. Override bindings
-- are not saved, so disabling Guildy gives J back.
--
-- GuildyToggleButton is a secure action button. Normally it does nothing itself and its PostClick
-- toggles Guildy. On Forever, guild invites only work through Blizzard's invite button, and the MOTD
-- and guild info only through Blizzard's text editor; both exist only once Blizzard's guild window was
-- opened by the player. So until then (and only for players who may invite or edit) the button is of
-- type "click" on the guild micro button: the first J opens Blizzard's window cleanly, Guildy closes it
-- right away and shows itself. From then on Guildy uses those Blizzard buttons directly.
local _, ns = ...

local Redirect = {}
ns.Redirect = Redirect

local owner = CreateFrame("Frame")
local toggle = CreateFrame("Button", "GuildyToggleButton", UIParent, "SecureActionButtonTemplate")
toggle:RegisterForClicks("AnyUp", "AnyDown")
local pending = false

local function KeyDownMode()
  local get = (C_CVar and C_CVar.GetCVarBool) or rawget(_G, "GetCVarBool")
  return get and get("ActionButtonUseKeyDown") and true or false
end

-- Whether the next J should open Blizzard's window once (to make its invite button available)
local function NeedsPreload()
  if not IsInGuild() or not rawget(_G, "GuildMicroButton") then return false end
  local Action = ns.UI.Action
  if not Action then return false end
  if ns.Try(rawget(_G, "CanGuildInvite")) and not Action.InviteReady() then return true end
  -- the MOTD / guild info editor uses Blizzard's text editor, which also needs the window loaded once
  if ns.Try(rawget(_G, "CanEditMOTD")) and not Action.TextEditReady("motd") then return true end
  if ns.Try(rawget(_G, "CanEditGuildInfo")) and not Action.TextEditReady("info") then return true end
  if ns.Try(rawget(_G, "IsGuildLeader")) and not Action.RankEditorReady() then return true end
  return false
end

function Redirect.UpdateToggle()
  if InCombatLockdown() then return end
  if NeedsPreload() then
    toggle:SetAttribute("type", "click")
    toggle:SetAttribute("clickbutton", rawget(_G, "GuildMicroButton"))
  else
    toggle:SetAttribute("type", nil)
  end
end

toggle:SetScript("PostClick", function(self, _, down)
  if (down and true or false) ~= KeyDownMode() then return end -- registered for both; act once
  if self:GetAttribute("type") == "click" then
    -- Blizzard's window just opened through the micro button: close it, show Guildy
    C_Timer.After(0, function()
      local frame = rawget(_G, "CommunitiesFrame")
      if frame and frame:IsShown() then
        local hide = rawget(_G, "HideUIPanel")
        if hide then pcall(hide, frame) else frame:Hide() end
      end
      ns.UI.Show()
      Redirect.UpdateToggle()
    end)
    return
  end
  ns.UI.Toggle()
end)

function Redirect.Apply()
  if InCombatLockdown() then
    pending = true
    return
  end
  pending = false
  ClearOverrideBindings(owner)
  local getKeys = rawget(_G, "GetBindingKey")
  if getKeys then
    for _, key in ipairs({ getKeys("TOGGLEGUILDTAB") }) do
      SetOverrideBindingClick(owner, false, key, "GuildyToggleButton", "LeftButton")
    end
  end
  Redirect.UpdateToggle()
end

-- PLAYER_REGEN_ENABLED: bindings changed during combat
function Redirect.AfterCombat()
  if pending then Redirect.Apply() else Redirect.UpdateToggle() end
end
