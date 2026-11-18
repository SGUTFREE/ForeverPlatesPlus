local _, ns = ...
local L = ns.L

-- Execute zone: a tinted part of the enemy health bar from 0 up to the execute threshold.
-- Health values may be secret in Forever, so nothing is compared here: the threshold is handed to
-- a status bar whose range is the unit's max health, and the game draws the result.
-- The threshold can follow the spell's own description, so it grows with spell power.
local M = ns.RegisterModule("KillZone", {})

local COLOR = { 0.58, 0.25, 1.0 } -- shadow purple
local TEXTURE = "Interface\\Buttons\\WHITE8X8"
-- kill zone: solid; crit zone (kills only on a crit): faint continuation behind it
local STYLE = {
	kill = { fill = 0.32, edge = 0.95, edgeWidth = 2, level = 2 },
	crit = { fill = 0.13, edge = 0.5, edgeWidth = 1, level = 1 },
}

local zones = setmetatable({}, { __mode = "k" }) -- game unit frame -> { kill = status bar, crit = status bar }
local inCombat = false
local spellCache -- { damage = number|nil, name = string|nil }; nil = read again on next use
local refreshQueued = false

------------------------------------------------------------------------
-- spell damage from the description
------------------------------------------------------------------------

local SEPARATORS = { [" "] = true, [","] = true, ["."] = true, ["\194\160"] = true } -- thousands: "1 234", "1,234", "1.234"

-- first number in a spell description; for "450 to 522" / "от 450 до 522" that is the minimum
local function ParseFirstNumber(text)
	if type(text) ~= "string" or ns.IsSecret(text) or text == "" then
		return nil
	end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]*:", ""):gsub("|r", ""):gsub("%$[%w_]+", "")
	local start = text:find("%d")
	if not start then
		return nil
	end
	local digits = text:match("^%d+", start)
	local pos = start + #digits
	while true do
		local sepLen = text:sub(pos, pos) == "\194" and 2 or 1
		if not SEPARATORS[text:sub(pos, pos + sepLen - 1)] then
			break
		end
		local group = text:match("^%d%d%d", pos + sepLen)
		if not group or text:find("^%d", pos + sepLen + 3) then
			break
		end
		digits = digits .. group
		pos = pos + sepLen + 3
	end
	return tonumber(digits)
end
ns.ParseSpellNumber = ParseFirstNumber

-- killzone.spell: a spell ID or a spell name
local function ReadSpellDamage()
	local spell = ns.Get("killzone.spell")
	if not C_Spell or spell == nil or spell == 0 or spell == "" then
		return nil
	end
	local name = type(spell) == "number" and C_Spell.GetSpellName and C_Spell.GetSpellName(spell) or spell
	if type(name) ~= "string" or ns.IsSecret(name) then
		return nil
	end
	-- by name the game gives the player's own version of the spell (rank, talent override)
	local info = C_Spell.GetSpellInfo(name)
	local spellID = info and not ns.IsSecret(info.spellID) and info.spellID or (type(spell) == "number" and spell)
	if not spellID then
		return nil, name
	end
	local damage = ParseFirstNumber(C_Spell.GetSpellDescription(spellID))
	if not damage and C_Spell.RequestLoadSpellData then
		C_Spell.RequestLoadSpellData(spellID) -- text not loaded yet: SPELL_TEXT_UPDATE follows
	end
	if not damage or damage <= 0 then
		return nil, name
	end
	return damage, name
end

local function GetSpellCache()
	if spellCache == nil then
		local ok, damage, name = pcall(ReadSpellDamage)
		spellCache = ok and { damage = damage, name = name } or {}
	end
	return spellCache
end

-- threshold in health points, its source ("spell" | "fallback" | "value" | "percent") and the spell name
function ns.GetKillZoneThreshold()
	local mode = ns.Get("killzone.mode")
	if mode == "percent" then
		return nil, "percent"
	end
	if mode == "spell" then
		local cache = GetSpellCache()
		if cache.damage then
			local bonus = tonumber(ns.Get("killzone.spellBonus")) or 0
			return math.floor(cache.damage * (1 + bonus / 100) + 0.5), "spell", cache.name
		end
		return ns.Get("killzone.value") or 0, "fallback", cache.name
	end
	return ns.Get("killzone.value") or 0, "value"
end

-- one line for /fpl status and the minimap tooltip
function ns.KillZoneSummary()
	if not ns.Get("killzone.enabled") then
		return L.KZ_OFF
	end
	local value, source, spellName = ns.GetKillZoneThreshold()
	local text
	if source == "percent" then
		text = ("%d%%"):format(ns.Get("killzone.percent") or 0)
	elseif source == "spell" then
		text = L.KZ_FROM_SPELL:format(value, spellName or "?")
	elseif source == "fallback" then
		text = L.KZ_FALLBACK:format(value)
	else
		text = L.KZ_MANUAL:format(value)
	end
	if ns.Get("killzone.crit") then
		local critMult = (tonumber(ns.Get("killzone.critMult")) or 150) / 100
		if source == "percent" then
			text = text .. L.KZ_CRIT_SUFFIX:format(("%d%%"):format(math.floor((ns.Get("killzone.percent") or 0) * critMult + 0.5)))
		else
			text = text .. L.KZ_CRIT_SUFFIX:format(tostring(math.floor(value * critMult + 0.5)))
		end
	end
	if ns.Get("killzone.combatOnly") then
		text = text .. L.KZ_COMBAT_SUFFIX
	end
	return text
end

------------------------------------------------------------------------
-- the zone on the health bar
------------------------------------------------------------------------

local function GetHealthBar(unitFrame)
	local container = unitFrame.HealthBarsContainer
	return container and container.healthBar
end

local function CreateBar(healthBar, role)
	local style = STYLE[role]
	local bar = CreateFrame("StatusBar", nil, healthBar)
	bar.fpRole = role
	bar:SetAllPoints(healthBar)
	bar:SetFrameLevel(healthBar:GetFrameLevel() + style.level)
	bar:SetStatusBarTexture(TEXTURE)
	bar:SetStatusBarColor(COLOR[1], COLOR[2], COLOR[3], style.fill)
	if bar.EnableMouse then
		bar:EnableMouse(false)
	end

	-- line where the zone ends
	local fill = bar:GetStatusBarTexture()
	local edge = bar:CreateTexture(nil, "OVERLAY")
	edge:SetColorTexture(COLOR[1], COLOR[2], COLOR[3], style.edge)
	edge:SetWidth(style.edgeWidth)
	edge:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
	edge:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)

	bar:Hide()
	return bar
end

local function CreateZone(unitFrame)
	local healthBar = GetHealthBar(unitFrame)
	if not healthBar then
		return nil
	end
	return { kill = CreateBar(healthBar, "kill"), crit = CreateBar(healthBar, "crit") }
end

local function HideZone(zone)
	if zone then
		zone.kill:Hide()
		zone.crit:Hide()
	end
end

local function ShouldShow(unit)
	if not ns.Get("killzone.enabled") then
		return false
	end
	if ns.Get("killzone.combatOnly") and not inCombat then
		return false
	end
	-- enemies only; if the game hides the answer, keep showing the zone
	return ns.SafeBool(UnitCanAttack("player", unit)) ~= false
end

local function Update(unit, unitFrame)
	local zone = zones[unitFrame]
	if not ShouldShow(unit) then
		HideZone(zone)
		return
	end

	if not zone then
		zone = CreateZone(unitFrame)
		if not zone then
			return
		end
		zones[unitFrame] = zone
	end

	local minValue, maxValue, threshold
	local kill = ns.GetKillZoneThreshold()
	if not kill then -- percent mode
		maxValue, threshold = 100, ns.Get("killzone.percent") or 20
	else
		maxValue, threshold = UnitHealthMax(unit), kill
		if not ns.IsSecret(maxValue) then
			if not maxValue or maxValue <= 0 then
				HideZone(zone)
				return
			end
			-- if the client only reports enemy players as 0..100, a health value can't be placed on the bar
			if maxValue <= 100 and ns.SafeBool(UnitIsPlayer(unit)) then
				HideZone(zone)
				return
			end
		end
	end
	minValue = 0

	zone.kill:SetMinMaxValues(minValue, maxValue)
	zone.kill:SetValue(threshold)
	zone.kill:Show()

	if ns.Get("killzone.crit") then
		local critMult = (tonumber(ns.Get("killzone.critMult")) or 150) / 100
		zone.crit:SetMinMaxValues(minValue, maxValue)
		zone.crit:SetValue(threshold * critMult)
		zone.crit:Show()
	else
		zone.crit:Hide()
	end
end

local function UpdateAll()
	ns.ForEachPlate(Update)
end

------------------------------------------------------------------------
-- events
------------------------------------------------------------------------

-- spell power changes with gear, buffs and talents: read the description again (at most every 0.3 s)
local function QueueSpellRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true
	C_Timer.After(0.3, function()
		refreshQueued = false
		local old = spellCache and spellCache.damage
		spellCache = nil
		if ns.Get("killzone.enabled") and ns.Get("killzone.mode") == "spell" and GetSpellCache().damage ~= old then
			UpdateAll()
		end
	end)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		inCombat = true
		spellCache = nil -- fresh numbers for the fight
		UpdateAll()
	elseif event == "PLAYER_REGEN_ENABLED" then
		inCombat = false
		UpdateAll()
	else
		QueueSpellRefresh()
	end
end)

function M:OnInit()
	ns.RegisterUnitEvent("UNIT_MAXHEALTH")
	ns.RegisterUnitEvent("UNIT_FACTION")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	-- events a client might not have are skipped
	for _, event in ipairs({ "SPELLS_CHANGED", "SPELL_TEXT_UPDATE", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP" }) do
		pcall(events.RegisterEvent, events, event)
	end
	pcall(events.RegisterUnitEvent, events, "UNIT_AURA", "player")
	inCombat = (ns.SafeBool(UnitAffectingCombat("player")) or InCombatLockdown()) and true or false
end

function M:OnPlateAdded(unit, unitFrame)
	Update(unit, unitFrame)
end

function M:OnPlateRemoved(_, unitFrame)
	HideZone(zones[unitFrame])
end

function M:OnUnitEvent(event, unit, unitFrame)
	if event == "UNIT_MAXHEALTH" or event == "UNIT_FACTION" then
		Update(unit, unitFrame)
	end
end

function M:Apply(key)
	if key and not key:find("^killzone%.") then
		return
	end
	if key == nil or key == "killzone.spell" then
		spellCache = nil
	end
	UpdateAll()
end
