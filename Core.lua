local ADDON_NAME, ns = ...
local L = ns.L

local frame = CreateFrame("Frame")
ns.frame = frame
ns.modules = {}
ns.activePlates = {}   -- [unitToken] = unitFrame of the game's nameplate

local function Print(...)
	print("|cff8fb8ffForever Plates|r:", ...)
end
ns.Print = Print

-- secret values (Midnight/Forever addon rules): never compare or test them
local issecretvalue = issecretvalue
function ns.IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value) or false
end

-- returns a boolean we are allowed to test, or nil if the game hides it
function ns.SafeBool(value)
	if value == nil or ns.IsSecret(value) then
		return nil
	end
	return value and true or false
end

function ns.RegisterModule(name, module)
	module.name = name
	table.insert(ns.modules, module)
	return module
end

local function CallModules(method, ...)
	for _, module in ipairs(ns.modules) do
		local fn = module[method]
		if fn then
			local ok, err = pcall(fn, module, ...)
			if not ok then
				geterrorhandler()(("ForeverPlates %s.%s: %s"):format(module.name, method, tostring(err)))
			end
		end
	end
end
ns.CallModules = CallModules

------------------------------------------------------------------------
-- settings: overrides -> class preset -> BASE
------------------------------------------------------------------------

-- settings renamed in 0.10 (the appearance page): keep what the player had chosen
local function Migrate(overrides)
	local function Move(old, new, convert)
		local value = overrides[old]
		if value ~= nil then
			if overrides[new] == nil then
				overrides[new] = convert and convert(value) or value
			end
			overrides[old] = nil
		end
	end
	local nameScale = overrides["plates.nameScale"]
	if nameScale ~= nil then
		Move("plates.nameScale", "look.enemyName.scale")
		overrides["look.friendName.scale"] = overrides["look.friendName.scale"] or nameScale
	end
	Move("plates.friendNameAlpha", "look.friendName.alpha")
	local guild = overrides["plates.guild"]
	if guild ~= nil then
		if guild == "allies" or guild == "all" then
			overrides["plates.guildFriends"] = true
		end
		if guild == "all" then
			overrides["plates.guildEnemies"] = true
		end
		overrides["plates.guild"] = nil
	end
	for group, pixels in pairs({ purge = 20, mine = 22, dispel = 16 }) do
		Move("auras." .. group .. "Size", "look." .. group .. ".scale", function(size)
			return math.floor((tonumber(size) or pixels) / pixels * 20 + 0.5) * 5 -- percent, in steps of 5
		end)
	end
end

-- 0.11: the settings are split by frame (enemy / ally / pet); a few switches became choices
local function MigrateSides(overrides)
	local function Copy(old, news)
		local value = overrides[old]
		if value == nil then
			return
		end
		for _, new in ipairs(news) do
			if overrides[new] == nil then
				overrides[new] = value
			end
		end
		overrides[old] = nil
	end
	for _, prop in ipairs({ "scale", "alpha", "x", "y", "place" }) do
		Copy("look.guild." .. prop, { "look.enemyGuild." .. prop, "look.friendGuild." .. prop })
		Copy("look.health." .. prop, { "look.enemyHealth." .. prop, "look.friendHealth." .. prop })
	end
	-- pets had the ally name's look
	for _, prop in ipairs({ "scale", "alpha" }) do
		local value = overrides["look.friendName." .. prop]
		if value ~= nil and overrides["look.petName." .. prop] == nil then
			overrides["look.petName." .. prop] = value
		end
	end
	-- the ally row of icons got its own offset
	for _, axis in ipairs({ "x", "y" }) do
		local value = overrides["look.addonAuras." .. axis]
		if value ~= nil and overrides["look.dispel." .. axis] == nil then
			overrides["look.dispel." .. axis] = value
		end
	end
	if overrides["native.friendClassColor"] ~= nil then
		if overrides["native.friendClassColor"] == true and overrides["look.friendName.color"] == nil then
			overrides["look.friendName.color"] = "class"
		end
		overrides["native.friendClassColor"] = nil
	end
	if overrides["plates.petClassColor"] ~= nil then
		if overrides["plates.petClassColor"] == false and overrides["look.petName.color"] == nil then
			overrides["look.petName.color"] = "white"
		end
		overrides["plates.petClassColor"] = nil
	end
	if overrides["plates.friendHealthText"] ~= nil then
		if overrides["plates.friendHealthText"] == true and overrides["plates.friendHealth"] == nil then
			overrides["plates.friendHealth"] = "both"
		end
		overrides["plates.friendHealthText"] = nil
	end
	if overrides["auras.timer"] ~= nil then
		for _, group in ipairs({ "mine", "purge", "dispel" }) do
			if overrides["auras." .. group .. "Timer"] == nil then
				overrides["auras." .. group .. "Timer"] = overrides["auras.timer"]
			end
		end
		overrides["auras.timer"] = nil
	end
	-- the game's health number switches are always on now: what to show is chosen per plate
	overrides["native.healthValue"] = nil
	overrides["native.healthPercent"] = nil
end

local function InitDB()
	ForeverPlatesCharDB = ForeverPlatesCharDB or {}
	local db = ForeverPlatesCharDB
	if type(db.preset) ~= "string" then
		db.preset = "auto"
	end
	if type(db.overrides) ~= "table" then
		db.overrides = {}
	end
	local version = tonumber(db.version) or 1
	if version < 2 then
		Migrate(db.overrides)
	end
	if version < 3 then
		MigrateSides(db.overrides)
	end
	db.version = 3
	ns.db = db
end

function ns.GetPlayerClass()
	local _, classFile = UnitClass("player")
	return classFile
end

-- the preset actually used ("BASE" or a class key)
function ns.GetActivePreset()
	local preset = ns.db and ns.db.preset or "auto"
	if preset == "auto" then
		local classFile = ns.GetPlayerClass()
		if classFile and ns.ClassPresets[classFile] then
			return classFile
		end
		return "BASE"
	end
	if preset ~= "BASE" and not ns.ClassPresets[preset] then
		return "BASE"
	end
	return preset
end

function ns.GetPresetDefault(key)
	local active = ns.GetActivePreset()
	local classPreset = ns.ClassPresets[active]
	if classPreset and classPreset[key] ~= nil then
		return classPreset[key]
	end
	return ns.BASE[key]
end

function ns.Get(key)
	local overrides = ns.db and ns.db.overrides
	if overrides and overrides[key] ~= nil then
		return overrides[key]
	end
	return ns.GetPresetDefault(key)
end

function ns.Set(key, value)
	if ns.GetPresetDefault(key) == value then
		ns.db.overrides[key] = nil -- same as the preset: keep the preset in charge
	else
		ns.db.overrides[key] = value
	end
	ns.Refresh(key)
end

function ns.CountOverrides()
	local count = 0
	for _ in pairs(ns.db.overrides) do
		count = count + 1
	end
	return count
end

function ns.ResetOverrides()
	wipe(ns.db.overrides)
	ns.Refresh()
end

function ns.SetPreset(preset)
	if preset ~= "auto" and preset ~= "BASE" and not ns.ClassPresets[preset] then
		return false
	end
	ns.db.preset = preset
	ns.Refresh()
	return true
end

-- key == nil means "everything changed"
function ns.Refresh(key)
	CallModules("Apply", key)
	if ns.OnSettingsRefreshed then
		ns.OnSettingsRefreshed(key)
	end
end

------------------------------------------------------------------------
-- work that must wait until combat ends (protected game settings)
------------------------------------------------------------------------

local pendingAfterCombat = {}
local announcedDeferral = false

function ns.RunOutOfCombat(id, fn)
	if InCombatLockdown() then
		pendingAfterCombat[id] = fn
		if not announcedDeferral then
			announcedDeferral = true
			Print(L.COMBAT_DEFERRED)
		end
		return false
	end
	fn()
	return true
end

------------------------------------------------------------------------
-- nameplates
------------------------------------------------------------------------

-- enemyPlayer | enemyNpc | friendlyPlayer | friendlyNpc
function ns.GetUnitKind(unit)
	local canAttack = ns.SafeBool(UnitCanAttack("player", unit))
	local isPlayer = ns.SafeBool(UnitIsPlayer(unit))
	if canAttack == nil then
		local isFriend = ns.SafeBool(UnitIsFriend("player", unit))
		canAttack = isFriend == false
	end
	if canAttack then
		return isPlayer and "enemyPlayer" or "enemyNpc"
	end
	return isPlayer and "friendlyPlayer" or "friendlyNpc"
end

-- the game's unit frame on a nameplate we are allowed to touch (forbidden plates return nil)
local function GetPlateUnitFrame(unit)
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	return plate and plate.UnitFrame
end
ns.GetPlateUnitFrame = GetPlateUnitFrame

-- The game lays a plate out again (UpdateAnchors) when its style, size or name-only state changes,
-- putting its parts back in their places: modules get OnPlateLayout to apply their changes again.
local layoutHooked = setmetatable({}, { __mode = "k" })
local plateUnit = setmetatable({}, { __mode = "k" }) -- unit frame -> unit token while active

local function OnGameLayout(unitFrame)
	local unit = plateUnit[unitFrame]
	if unit and rawequal(ns.activePlates[unit], unitFrame) then
		CallModules("OnPlateLayout", unit, unitFrame)
	end
end

local function HookLayout(unitFrame)
	if not layoutHooked[unitFrame] and type(unitFrame.UpdateAnchors) == "function" then
		layoutHooked[unitFrame] = true
		hooksecurefunc(unitFrame, "UpdateAnchors", OnGameLayout)
	end
end

local function OnPlateAdded(unit, attempt)
	local unitFrame = GetPlateUnitFrame(unit)
	if not unitFrame then
		-- the game may attach its unit frame a moment later
		if (attempt or 0) < 2 and C_NamePlate.GetNamePlateForUnit(unit) then
			C_Timer.After(0, function()
				OnPlateAdded(unit, (attempt or 0) + 1)
			end)
		end
		return
	end
	ns.activePlates[unit] = unitFrame
	plateUnit[unitFrame] = unit
	HookLayout(unitFrame)
	CallModules("OnPlateAdded", unit, unitFrame)
end

local function OnPlateRemoved(unit)
	local unitFrame = ns.activePlates[unit]
	ns.activePlates[unit] = nil
	if unitFrame then
		plateUnit[unitFrame] = nil
		CallModules("OnPlateRemoved", unit, unitFrame)
	end
end

function ns.ForEachPlate(callback)
	for unit, unitFrame in pairs(ns.activePlates) do
		callback(unit, unitFrame)
	end
end

------------------------------------------------------------------------
-- events
------------------------------------------------------------------------

local unitEvents = {} -- event -> true, forwarded to modules as OnUnitEvent

function ns.RegisterUnitEvent(event)
	if not unitEvents[event] then
		unitEvents[event] = true
		frame:RegisterEvent(event)
	end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")

frame:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == ADDON_NAME then
			InitDB()
			CallModules("OnInit")
			frame:UnregisterEvent("ADDON_LOADED")
		end

	elseif event == "PLAYER_LOGIN" then
		CallModules("OnLogin")
		Print(L.LOADED)

	elseif event == "PLAYER_ENTERING_WORLD" then
		-- the game restores its own nameplate settings while loading; apply ours right after
		C_Timer.After(1, function()
			CallModules("Apply", nil)
		end)

	elseif event == "PLAYER_REGEN_ENABLED" then
		announcedDeferral = false
		local jobs = pendingAfterCombat
		pendingAfterCombat = {}
		for _, fn in pairs(jobs) do
			fn()
		end

	elseif event == "NAME_PLATE_UNIT_ADDED" then
		OnPlateAdded(...)

	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		OnPlateRemoved(...)

	elseif unitEvents[event] then
		local unit = ...
		local unitFrame = unit and ns.activePlates[unit]
		if unitFrame then
			CallModules("OnUnitEvent", event, unit, unitFrame)
		end
	end
end)

------------------------------------------------------------------------
-- slash commands
------------------------------------------------------------------------

SLASH_FOREVERPLATES1 = "/fpl"
SLASH_FOREVERPLATES2 = "/foreverplates"
SlashCmdList.FOREVERPLATES = function(msg)
	local cmd, arg = strsplit(" ", strtrim(msg or ""), 2)
	cmd = (cmd or ""):lower()

	if cmd == "" then
		if ns.OpenOptions then
			ns.OpenOptions()
		end
		Print(L.HELP)

	elseif cmd == "preset" then
		local wanted = (arg or ""):lower()
		local preset = (wanted == "auto" and "auto") or (wanted == "base" and "BASE") or wanted:upper()
		if ns.SetPreset(preset) then
			Print(L.PRESET .. ":", ns.GetActivePreset())
		else
			Print(L.UNKNOWN_PRESET, tostring(arg))
		end

	elseif cmd == "reset" then
		ns.ResetOverrides()
		Print(L.RESET_DONE, ns.GetActivePreset())

	elseif cmd == "kz" then
		local value = tonumber(arg)
		if value and value > 0 then
			ns.Set("killzone.mode", "value")
			ns.Set("killzone.value", math.floor(value))
			ns.Set("killzone.enabled", true)
			Print(L.KZ_SET, math.floor(value))
		else
			Print(L.KZ_SET, tostring(ns.Get("killzone.value")))
		end

	elseif cmd == "kzspell" then
		local spell = strtrim(arg or "")
		if spell ~= "" then
			ns.Set("killzone.spell", tonumber(spell) or spell)
			ns.Set("killzone.mode", "spell")
			ns.Set("killzone.enabled", true)
		end
		Print(L.KZ_SPELL_SET, ns.KillZoneSummary and ns.KillZoneSummary() or "")

	elseif cmd == "debug" then
		if ns.DebugNames then
			ns.DebugNames()
		end

	elseif cmd == "status" then
		Print(L.STATUS:format(ns.GetActivePreset(), ns.CountOverrides()))
		if ns.KillZoneSummary then
			Print(L.SECTION_KILLZONE .. ": " .. ns.KillZoneSummary())
		end

	elseif cmd == "gamedefaults" then
		if ns.ResetGameNameplateSettings then
			ns.ResetGameNameplateSettings()
		end

	else
		Print(L.HELP)
	end
end
