local _, ns = ...
local L = ns.L

-- Drives the game's own nameplate options (the same ones as in Options > Nameplates).
-- Nothing is drawn here: the plates keep the Forever look, only their behaviour changes.
local M = ns.RegisterModule("NativeOptions", {})

local function EnumValue(enumName, field, fallback)
	local group = Enum and Enum[enumName]
	return (group and group[field]) or fallback
end

local function CVarExists(name)
	return C_CVar.GetCVar(name) ~= nil
end

local managedCVars = {} -- every CVar this module may touch, for "gamedefaults"

local function SetBool(name, value)
	managedCVars[name] = true
	if not CVarExists(name) then
		return
	end
	local wanted = value and "1" or "0"
	if C_CVar.GetCVar(name) ~= wanted then
		C_CVar.SetCVar(name, wanted)
	end
end

-- back to the game's default value (for options the addon stops managing)
local function SetToDefault(name)
	managedCVars[name] = true
	if not CVarExists(name) then
		return
	end
	local default = C_CVar.GetCVarDefault(name)
	if default ~= nil and C_CVar.GetCVar(name) ~= default then
		C_CVar.SetCVar(name, default)
	end
end

-- the big floating "Name <Pet of X>" labels the game draws over allies' pets
local WORLD_PET_NAME_CVARS = { "UnitNameFriendlyMinionName", "UnitNameFriendlyPetName", "UnitNameFriendlyGuardianName", "UnitNameFriendlyTotemName" }

local function SetNumber(name, value)
	managedCVars[name] = true
	if not CVarExists(name) or type(value) ~= "number" then
		return
	end
	local current = tonumber(C_CVar.GetCVar(name))
	if not current or math.abs(current - value) > 0.001 then
		C_CVar.SetCVar(name, tostring(value))
	end
end

local function SetBit(name, index, value)
	managedCVars[name] = true
	if not CVarExists(name) or not index then
		return
	end
	if (C_CVar.GetCVarBitfield(name, index) and true or false) ~= (value and true or false) then
		C_CVar.SetCVarBitfield(name, index, value and true or false)
	end
end

-- bitfield options: setting key -> CVar + enum field
local BITS = {
	{ key = "native.healthPercent", cvar = "nameplateInfoDisplay", enum = "NamePlateInfoDisplay", field = "CurrentHealthPercent", fallback = 1 },
	{ key = "native.healthValue", cvar = "nameplateInfoDisplay", enum = "NamePlateInfoDisplay", field = "CurrentHealthValue", fallback = 2 },

	{ key = "native.castName", cvar = "nameplateCastBarDisplay", enum = "NamePlateCastBarDisplay", field = "SpellName", fallback = 1 },
	{ key = "native.castIcon", cvar = "nameplateCastBarDisplay", enum = "NamePlateCastBarDisplay", field = "SpellIcon", fallback = 2 },
	{ key = "native.castTarget", cvar = "nameplateCastBarDisplay", enum = "NamePlateCastBarDisplay", field = "SpellTarget", fallback = 3 },
	{ key = "native.castImportant", cvar = "nameplateCastBarDisplay", enum = "NamePlateCastBarDisplay", field = "HighlightImportantCasts", fallback = 4 },
	{ key = "native.castOnMe", cvar = "nameplateCastBarDisplay", enum = "NamePlateCastBarDisplay", field = "HighlightWhenCastTarget", fallback = 5 },

	{ key = "native.npcBuffs", cvar = "nameplateEnemyNpcAuraDisplay", enum = "NamePlateEnemyNpcAuraDisplay", field = "Buffs", fallback = 1 },
	{ key = "native.npcDebuffs", cvar = "nameplateEnemyNpcAuraDisplay", enum = "NamePlateEnemyNpcAuraDisplay", field = "Debuffs", fallback = 2 },
	{ key = "native.npcCC", cvar = "nameplateEnemyNpcAuraDisplay", enum = "NamePlateEnemyNpcAuraDisplay", field = "CrowdControl", fallback = 3 },

	{ key = "native.pvpBuffs", cvar = "nameplateEnemyPlayerAuraDisplay", enum = "NamePlateEnemyPlayerAuraDisplay", field = "Buffs", fallback = 1 },
	{ key = "native.pvpDebuffs", cvar = "nameplateEnemyPlayerAuraDisplay", enum = "NamePlateEnemyPlayerAuraDisplay", field = "Debuffs", fallback = 2 },
	{ key = "native.pvpLoC", cvar = "nameplateEnemyPlayerAuraDisplay", enum = "NamePlateEnemyPlayerAuraDisplay", field = "LossOfControl", fallback = 3 },

	{ key = "native.friendBuffs", cvar = "nameplateFriendlyPlayerAuraDisplay", enum = "NamePlateFriendlyPlayerAuraDisplay", field = "Buffs", fallback = 1 },
	{ key = "native.friendDebuffs", cvar = "nameplateFriendlyPlayerAuraDisplay", enum = "NamePlateFriendlyPlayerAuraDisplay", field = "Debuffs", fallback = 2 },
	{ key = "native.friendLoC", cvar = "nameplateFriendlyPlayerAuraDisplay", enum = "NamePlateFriendlyPlayerAuraDisplay", field = "LossOfControl", fallback = 3 },

	-- no preset default: left as the game has them until you change them
	{ key = "native.smallMinions", cvar = "nameplateSimplifiedTypes", enum = "NamePlateSimplifiedType", field = "Minion", fallback = 1 },
	{ key = "native.smallMinus", cvar = "nameplateSimplifiedTypes", enum = "NamePlateSimplifiedType", field = "MinusMob", fallback = 2 },
}

-- plain on/off options with no preset default (left as the game has them until you change them)
local OPTIONAL_BOOLS = {
	{ key = "native.enemyMinions", cvar = "nameplateShowEnemyMinions" },
	{ key = "native.enemyMinus", cvar = "nameplateShowEnemyMinus" },
}

-- numbers with no preset default (left as the game has them until you change them)
local OPTIONAL_NUMBERS = {
	{ key = "native.maxDistance", cvar = "nameplateMaxDistance" }, -- how far away plates appear, yards
}

-- what the game currently has for an option (for the settings panel when the addon doesn't set it)
function ns.GetGameOption(key)
	for _, info in ipairs(OPTIONAL_NUMBERS) do
		if info.key == key and CVarExists(info.cvar) then
			return tonumber(C_CVar.GetCVar(info.cvar))
		end
	end
	for _, info in ipairs(OPTIONAL_BOOLS) do
		if info.key == key and CVarExists(info.cvar) then
			return C_CVar.GetCVar(info.cvar) == "1"
		end
	end
	for _, info in ipairs(BITS) do
		if info.key == key and CVarExists(info.cvar) then
			return C_CVar.GetCVarBitfield(info.cvar, EnumValue(info.enum, info.field, info.fallback)) and true or false
		end
	end
	return nil
end

local THREAT_FIELDS = {
	progressive = "Progressive",
	flash = "Flash",
	bar = "HealthBarColor",
}

local function ApplyThreat()
	local mode = ns.Get("native.threat")
	if mode == nil then
		return
	end
	local fallbacks = { Progressive = 1, Flash = 2, HealthBarColor = 3 }
	for _, field in pairs(THREAT_FIELDS) do
		local index = EnumValue("NamePlateThreatDisplay", field, fallbacks[field])
		SetBit("nameplateThreatDisplay", index, THREAT_FIELDS[mode] == field)
	end
end

local function ApplyStacking()
	local enemies = ns.Get("native.stackEnemies")
	local friends = ns.Get("native.stackFriends")
	if CVarExists("nameplateStackingTypes") then
		SetBit("nameplateStackingTypes", EnumValue("NamePlateStackType", "Enemy", 1), enemies)
		SetBit("nameplateStackingTypes", EnumValue("NamePlateStackType", "Friendly", 2), friends)
	else
		-- older nameplate system: one switch for everything
		SetBool("nameplateMotion", enemies)
	end
end

local function ApplyAll()
	for _, info in ipairs(BITS) do
		local value = ns.Get(info.key)
		if value ~= nil then
			SetBit(info.cvar, EnumValue(info.enum, info.field, info.fallback), value)
		end
	end
	for _, info in ipairs(OPTIONAL_BOOLS) do
		local value = ns.Get(info.key)
		if value ~= nil then
			SetBool(info.cvar, value)
		end
	end
	for _, info in ipairs(OPTIONAL_NUMBERS) do
		local value = tonumber(ns.Get(info.key))
		if value then
			SetNumber(info.cvar, value)
		end
	end
	ApplyThreat()
	ApplyStacking()
	SetBool("nameplateShowAll", ns.Get("native.alwaysShow"))
	SetBool("nameplateShowOffscreen", ns.Get("native.offscreen"))
	SetBool("nameplateShowFriendlyNpcs", ns.Get("native.friendlyNpcs"))
	SetNumber("nameplateOccludedAlphaMult", ns.Get("native.losFade"))

	-- In dungeons and raids the game doesn't let addons touch ally nameplates, so numbers there can only
	-- go away with the game's own "name only" option. Re-applied on every loading screen.
	local namesOnly = ns.Get("native.friendNamesOnly")
	local inInstance = IsInInstance and IsInInstance() and true or false
	SetBool("nameplateShowOnlyNameForFriendlyPlayerUnits", namesOnly == "always" or (namesOnly == "instance" and inInstance))
	SetBool("nameplateUseClassColorForFriendlyPlayerUnitNames", ns.Get("native.friendClassColor"))

	-- Allies' pets: instead of the game's big floating labels, nameplates that the addon turns into a
	-- white name (see HealthText). In dungeons and raids the addon can't touch ally plates, so pets get
	-- neither plates nor labels there.
	if ns.Get("plates.petNamesOnly") then
		SetBool("nameplateShowFriendlyPlayerMinions", not inInstance)
		for _, name in ipairs(WORLD_PET_NAME_CVARS) do
			SetBool(name, false)
		end
	else
		SetToDefault("nameplateShowFriendlyPlayerMinions")
		for _, name in ipairs(WORLD_PET_NAME_CVARS) do
			SetToDefault(name)
		end
	end
end

function M:Apply(key)
	if key and not key:find("^native%.") and key ~= "plates.petNamesOnly" then
		return
	end
	if not ns.Get("native.manage") then
		return
	end
	ns.RunOutOfCombat("native", ApplyAll)
end

-- every CVar this module can touch, known up front
for _, info in ipairs(BITS) do
	managedCVars[info.cvar] = true
end
for _, info in ipairs(OPTIONAL_BOOLS) do
	managedCVars[info.cvar] = true
end
for _, info in ipairs(OPTIONAL_NUMBERS) do
	managedCVars[info.cvar] = true
end
managedCVars.nameplateShowFriendlyPlayerMinions = true
for _, name in ipairs(WORLD_PET_NAME_CVARS) do
	managedCVars[name] = true
end
for _, name in ipairs({ "nameplateThreatDisplay", "nameplateStackingTypes", "nameplateMotion", "nameplateShowAll",
		"nameplateShowOffscreen", "nameplateShowFriendlyNpcs", "nameplateOccludedAlphaMult",
		"nameplateShowOnlyNameForFriendlyPlayerUnits", "nameplateUseClassColorForFriendlyPlayerUnitNames" }) do
	managedCVars[name] = true
end

-- /fpl gamedefaults: stop managing the game options and put them back to the game defaults
function ns.ResetGameNameplateSettings()
	ns.RunOutOfCombat("native-defaults", function()
		ns.Set("native.manage", false)
		for name in pairs(managedCVars) do
			if CVarExists(name) then
				local default = C_CVar.GetCVarDefault(name)
				if default then
					C_CVar.SetCVar(name, default)
				end
			end
		end
		ns.Print(L.GAMEDEFAULTS_DONE)
	end)
end

-- which optional options the client supports (used to hide unsupported sliders)
function ns.ClientHasCVar(name)
	return CVarExists(name)
end
