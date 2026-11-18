local _, ns = ...

-- Fading enemy plates:
--  * out of range: enemies you can't reach with your class's main ranged (or melee) spell get faded;
--  * not your target: while you have a target, the other enemies get faded.
-- Range answers are plain true/false (or nil when the game can't tell: then nothing is faded).
local M = ns.RegisterModule("Fade", {})

local INTERVAL = 0.2

-- range reference spells per class, the first one the player knows is used
local RANGE_SPELLS = {
	PRIEST = { 585, 589, 8092 },           -- Smite, Shadow Word: Pain, Mind Blast
	MAGE = { 133, 116, 2136 },             -- Fireball, Frostbolt, Fire Blast
	WARLOCK = { 686, 172 },                -- Shadow Bolt, Corruption
	SHAMAN = { 403, 8042 },                -- Lightning Bolt, Earth Shock
	DRUID = { 5176, 8921 },                -- Wrath, Moonfire
	HUNTER = { 75, 1130, 3044 },           -- Auto Shot, Hunter's Mark, Arcane Shot
	PALADIN = { 62124, 20271, 35395 },     -- Hand of Reckoning, Judgement, Crusader Strike
	WARRIOR = { 355, 1715, 78 },           -- Taunt, Hamstring, Heroic Strike
	ROGUE = { 1752, 2098, 1766 },          -- Sinister Strike, Eviscerate, Kick
	DEATHKNIGHT = { 49576, 45477 },        -- Death Grip, Icy Touch
	MONK = { 115546, 100780 },             -- Provoke, Tiger Palm
	DEMONHUNTER = { 185123, 162794 },      -- Throw Glaive, Chaos Strike
	EVOKER = { 361469, 362969 },           -- Living Flame, Azure Strike
}

local rangeSpell
local faded = setmetatable({}, { __mode = "k" }) -- game unit frame -> alpha we set
local sinceCheck = 0

local function IsKnown(spellID)
	if not (C_SpellBook and C_SpellBook.IsSpellKnown) then
		return false
	end
	local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID)
	return ok and known == true
end

local function ResolveRangeSpell()
	rangeSpell = nil
	local custom = ns.Get("fade.rangeSpell")
	if custom and custom ~= 0 and custom ~= "" then
		rangeSpell = custom
		return
	end
	local _, class = UnitClass("player")
	for _, spellID in ipairs(RANGE_SPELLS[class] or {}) do
		if IsKnown(spellID) then
			rangeSpell = spellID
			return
		end
	end
end

function ns.GetRangeSpell()
	return rangeSpell
end

local function TargetFrame()
	local plate = C_NamePlate.GetNamePlateForUnit("target")
	return plate and plate.UnitFrame
end

local function DesiredAlpha(unit, unitFrame, targetFrame)
	local kind = ns.GetUnitKind(unit)
	if kind ~= "enemyNpc" and kind ~= "enemyPlayer" then
		return nil
	end
	local alpha = 1
	if ns.Get("fade.nonTarget") and targetFrame and not rawequal(unitFrame, targetFrame) then
		alpha = math.min(alpha, (tonumber(ns.Get("fade.nonTargetAlpha")) or 60) / 100)
	end
	if ns.Get("fade.range") and rangeSpell and C_Spell and C_Spell.IsSpellInRange then
		local ok, inRange = pcall(C_Spell.IsSpellInRange, rangeSpell, unit)
		if ok and ns.SafeBool(inRange) == false then
			alpha = math.min(alpha, (tonumber(ns.Get("fade.rangeAlpha")) or 50) / 100)
		end
	end
	return alpha < 1 and alpha or nil
end

local function Update(unit, unitFrame, targetFrame)
	local alpha = DesiredAlpha(unit, unitFrame, targetFrame)
	if alpha then
		if faded[unitFrame] ~= alpha then
			unitFrame:SetAlpha(alpha)
			faded[unitFrame] = alpha
		end
	elseif faded[unitFrame] then
		unitFrame:SetAlpha(1)
		faded[unitFrame] = nil
	end
end

local function UpdateAll()
	local targetFrame = TargetFrame()
	ns.ForEachPlate(function(unit, unitFrame)
		Update(unit, unitFrame, targetFrame)
	end)
end

local watcher = CreateFrame("Frame")

local function Watch(_, elapsed)
	sinceCheck = sinceCheck + elapsed
	if sinceCheck >= INTERVAL then
		sinceCheck = 0
		UpdateAll()
	end
end

-- range changes as you move and has no event: check a few times a second, only while it's needed
local function UpdateWatching()
	local needed = ns.Get("fade.range") and rangeSpell ~= nil
	watcher:SetScript("OnUpdate", needed and Watch or nil)
end

watcher:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_TARGET_CHANGED" then
		UpdateAll()
	else
		ResolveRangeSpell()
		UpdateWatching()
		UpdateAll()
	end
end)

function M:OnInit()
	watcher:RegisterEvent("PLAYER_TARGET_CHANGED")
	for _, event in ipairs({ "PLAYER_LOGIN", "SPELLS_CHANGED" }) do
		pcall(watcher.RegisterEvent, watcher, event)
	end
end

function M:OnPlateAdded(unit, unitFrame)
	Update(unit, unitFrame, TargetFrame())
end

function M:OnPlateRemoved(_, unitFrame)
	if faded[unitFrame] then
		unitFrame:SetAlpha(1) -- unit frames are reused
		faded[unitFrame] = nil
	end
end

function M:Apply(key)
	if key and not key:find("^fade%.") then
		return
	end
	if key == nil or key == "fade.rangeSpell" then
		ResolveRangeSpell()
	end
	UpdateWatching()
	UpdateAll()
end
