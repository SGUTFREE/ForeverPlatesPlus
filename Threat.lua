local _, ns = ...

-- Early aggro warning: the game lights an enemy plate only once your threat is above the tank's.
-- This lights it earlier: a glow in the game's own aggro style above the enemy bar that grows from
-- left to right as your threat goes from the chosen threshold to the point where the mob turns on you.
-- Threat may be secret in instances, so nothing is compared here: the value goes to a status bar whose
-- range starts at the threshold (below it the bar is simply empty) and the game draws the result.
local M = ns.RegisterModule("Threat", {})

local ATLAS = "UI-HUD-Nameplates-Aggro-Flare" -- the texture of the game's own aggro glow
local COLOR = { 1, 0.82, 0.25 }
local TEXTURE = "Interface\\Buttons\\WHITE8X8"

local bars = setmetatable({}, { __mode = "k" }) -- game unit frame -> our status bar

local function CreateBar(unitFrame)
	local container = unitFrame.HealthBarsContainer
	if not container then
		return nil
	end
	local bar = CreateFrame("StatusBar", nil, unitFrame)
	bar.fpRole = "threat"
	bar:SetPoint("BOTTOMLEFT", container, "TOPLEFT", 0, 0)
	bar:SetPoint("BOTTOMRIGHT", container, "TOPRIGHT", 0, 0)
	bar:SetStatusBarTexture(TEXTURE)
	if bar.EnableMouse then
		bar:EnableMouse(false)
	end

	local fill = bar:GetStatusBarTexture()
	local atlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(ATLAS)
	if atlas and fill.SetAtlas then
		fill:SetAtlas(ATLAS)
		bar:SetHeight(math.min(atlas.height or 10, 12))
		fill:SetBlendMode("ADD")
		bar:SetStatusBarColor(COLOR[1], COLOR[2], COLOR[3], 0.9)
	else
		-- no glow texture on this client: a thin line on top of the bar instead
		bar:SetHeight(2)
		bar:SetStatusBarColor(COLOR[1], COLOR[2], COLOR[3], 0.9)
	end
	bar:Hide()
	return bar
end

local function IsTank()
	if UnitGroupRolesAssigned and UnitGroupRolesAssigned("player") == "TANK" then
		return true
	end
	return false
end

local function ShouldWarn(unit)
	if not ns.Get("threat.warn") then
		return false
	end
	-- like the game: threat is only shown in a group, and a tank doesn't need this
	if not (IsInGroup and IsInGroup()) or IsTank() then
		return false
	end
	return ns.GetUnitKind(unit) == "enemyNpc" and not ns.LeftToGame(unit)
end

-- how many values came back (none = we're not on the mob's threat list) and the scaled percentage
local function ReadThreat(...)
	return select("#", ...), select(3, ...)
end

local function Update(unit, unitFrame)
	local bar = bars[unitFrame]
	if not ShouldWarn(unit) then
		if bar then
			bar:Hide()
		end
		return
	end
	local count, scaled = ReadThreat(UnitDetailedThreatSituation("player", unit))
	if count < 3 then
		if bar then
			bar:Hide()
		end
		return
	end
	if not bar then
		bar = CreateBar(unitFrame)
		if not bar then
			return
		end
		bars[unitFrame] = bar
	end
	-- 100 = the mob turns on you; below the threshold the bar stays empty
	bar:SetMinMaxValues(ns.Get("threat.warnFrom") or 70, 100)
	bar:SetValue(scaled)
	bar:Show()
end

local function UpdateAll()
	ns.ForEachPlate(Update)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", UpdateAll)

function M:OnInit()
	ns.RegisterUnitEvent("UNIT_THREAT_LIST_UPDATE")
	ns.RegisterUnitEvent("UNIT_THREAT_SITUATION_UPDATE")
	ns.RegisterUnitEvent("UNIT_FACTION")
	for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_REGEN_ENABLED" }) do
		pcall(events.RegisterEvent, events, event)
	end
end

function M:OnPlateAdded(unit, unitFrame)
	Update(unit, unitFrame)
end

function M:OnPlateRemoved(_, unitFrame)
	local bar = bars[unitFrame]
	if bar then
		bar:Hide()
	end
end

function M:OnUnitEvent(event, unit, unitFrame)
	if event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE" or event == "UNIT_FACTION" then
		Update(unit, unitFrame)
	end
end

function M:Apply(key)
	if key and not key:find("^threat%.") and key ~= "plates.enemies" then
		return
	end
	UpdateAll()
end
