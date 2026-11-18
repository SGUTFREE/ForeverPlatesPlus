local _, ns = ...

--[[
	Settings are flat "section.name" keys. The value in effect is resolved as:
	    your change (overrides)  ->  class preset  ->  BASE
	A class preset lists only the keys it changes. To add a class later, add a table to
	ns.ClassPresets with the class file name (WARRIOR, MAGE, ...) and an entry in ns.PresetOrder.
]]

ns.BASE = {
	-- game (CVar) nameplate options, applied only while native.manage is on
	["native.manage"]         = true,
	["native.healthPercent"]  = true,   -- nameplateInfoDisplay: CurrentHealthPercent
	["native.healthValue"]    = true,   -- nameplateInfoDisplay: CurrentHealthValue
	["native.alwaysShow"]     = true,   -- nameplateShowAll
	["native.stackEnemies"]   = true,   -- nameplateStackingTypes: Enemy (common practice)
	["native.stackFriends"]   = false,  -- nameplateStackingTypes: Friendly (so allies don't push enemies)
	["native.offscreen"]      = false,  -- nameplateShowOffscreen: only the target stays clamped
	["native.friendlyNpcs"]   = false,  -- nameplateShowFriendlyNpcs
	["native.losFade"]        = 0.4,    -- nameplateOccludedAlphaMult, if the client has it
	["health.format"]         = "short", -- short (12.3K) | full (12 345) | game
	["health.decimals"]       = 1,       -- decimals in the short format
	["native.friendNamesOnly"] = "always", -- never | instance | always: ally players show only the name (no bar, no numbers)
	["native.friendClassColor"] = false,   -- ally player names in class colour (off: white)
	["plates.friendNameAlpha"]  = 55,      -- ally name opacity, % (100 = as the game draws it)
	["plates.petNamesOnly"]     = true,    -- allies' pets and minions: only the name, like ally players
	["plates.petClassColor"]    = true,    -- pet names in the owner's class colour (white if the owner isn't found)
	["plates.friendHealthText"] = false, -- health numbers on friendly plates (the game option is shared by all plates)
	["plates.friendFullNames"]  = true,  -- friendly names written in full instead of cut with "..."
	["plates.enemyFullNames"]   = true,  -- the same for enemies
	-- health numbers on enemies by state: none | value | percent | both
	["enemyText.idle"]        = "none",  -- not targeted, not under the cursor
	["enemyText.mouseover"]   = "value",
	["enemyText.target"]      = "both",
	["ui.minimap"]            = true,   -- minimap button
	["info.quest"]            = true,   -- quest marker on mobs and NPCs of your active quests

	-- fading enemy plates
	["fade.range"]            = true,   -- out of range of your class spell
	["fade.rangeAlpha"]       = 50,     -- %
	["fade.rangeSpell"]       = 0,      -- 0 = pick by class
	["fade.nonTarget"]        = false,  -- not your target, while you have one
	["fade.nonTargetAlpha"]   = 60,     -- %

	-- native.enemyMinions, native.enemyMinus, native.smallMinions, native.smallMinus, native.maxDistance have no default
	-- on purpose: the game's own setting stays until you change it

	["native.castName"]       = true,   -- nameplateCastBarDisplay bits
	["native.castIcon"]       = true,
	["native.castTarget"]     = true,
	["native.castImportant"]  = true,
	["native.castOnMe"]       = true,
	["cast.timer"]            = true,   -- time left next to enemy cast bars
	["cast.interruptReady"]   = true,   -- grey enemy cast bar while your interrupt is on cooldown
	["native.threat"]         = "progressive", -- none | progressive | flash | bar
	["threat.warn"]           = true,   -- early aggro warning (glow grows before you pull)
	["threat.warnFrom"]       = 70,     -- start at this % of the threat that pulls the mob

	-- game aura rows; game debuffs are replaced by our "My debuffs" row
	["native.npcBuffs"]       = true,
	["native.npcDebuffs"]     = false,
	["native.npcCC"]          = true,
	["native.pvpBuffs"]       = true,
	["native.pvpDebuffs"]     = false,
	["native.pvpLoC"]         = true,
	["native.friendBuffs"]    = false,  -- no buff icons (Fortitude etc.) on allies
	["native.friendDebuffs"]  = false,
	["native.friendLoC"]      = true,

	-- our extra aura rows, drawn in the slot of the game's debuff row (above the name)
	["auras.purge"]           = true,   -- HELPFUL|RAID_PLAYER_DISPELLABLE on enemies (buffs you can remove)
	["auras.purgeSize"]       = 20,
	["auras.purgeMax"]        = 3,
	["auras.mine"]            = true,   -- HARMFUL|PLAYER on enemies
	["auras.minePlayers"]     = true,
	["auras.mineSize"]        = 22,
	["auras.mineMax"]         = 6,
	["auras.dispel"]          = true,   -- HARMFUL|RAID_PLAYER_DISPELLABLE on allies
	["auras.dispelSize"]      = 16,
	["auras.dispelMax"]       = 3,
	["auras.timer"]           = true,

	-- execute zone on enemy health bars
	["killzone.enabled"]      = false,
	["killzone.combatOnly"]   = true,    -- only while you are in combat
	["killzone.targetOnly"]   = true,    -- only on your target
	["killzone.style"]        = "line",  -- line (just the mark) | zone (tinted part of the bar)
	["killzone.mode"]         = "value", -- spell (damage from the spell description) | value | percent
	["killzone.spell"]        = 0,       -- spell ID or name for "spell" mode
	["killzone.spellBonus"]   = 0,       -- % correction to the description damage
	["killzone.value"]        = 350,     -- manual threshold, also the fallback when the description can't be read
	["killzone.percent"]      = 20,
	["killzone.crit"]         = false,   -- faint continuation: kills only on a crit
	["killzone.critMult"]     = 150,     -- crit damage, % of normal
}

ns.ClassPresets = {
	-- Shadow Word: Death: the zone ends at its minimum damage from the description (grows with spell power).
	PRIEST = {
		["killzone.enabled"] = true,
		["killzone.mode"]    = "spell",
		["killzone.spell"]   = 32379, -- Shadow Word: Death; by name the game picks the player's own rank
		["killzone.value"]   = 350,
		["killzone.crit"]    = true,
	},
}

-- order and labels for the preset dropdown
ns.PresetOrder = { "auto", "BASE", "PRIEST" }
ns.PresetLabelKey = { auto = "PRESET_AUTO", BASE = "PRESET_BASE", PRIEST = "PRESET_PRIEST" }
