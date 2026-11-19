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
	-- nameplateInfoDisplay: kept on, the addon shows or hides the numbers per plate (enemyText.*, plates.friendHealth)
	["native.healthPercent"]  = true,
	["native.healthValue"]    = true,
	["native.alwaysShow"]     = true,   -- nameplateShowAll
	["native.stackEnemies"]   = true,   -- nameplateStackingTypes: Enemy (common practice)
	["native.stackFriends"]   = false,  -- nameplateStackingTypes: Friendly (so allies don't push enemies)
	["native.offscreen"]      = false,  -- nameplateShowOffscreen: only the target stays clamped
	["native.friendlyNpcs"]   = false,  -- nameplateShowFriendlyNpcs
	["native.losFade"]        = 0.4,    -- nameplateOccludedAlphaMult, if the client has it
	["health.format"]         = "short", -- short (12.3K) | full (12 345) | game
	["health.decimals"]       = 1,       -- decimals in the short format
	["native.friendNamesOnly"] = "always", -- never | instance | always: ally players show only the name (no bar, no numbers)
	["plates.petNamesOnly"]     = true,    -- allies' pets and minions: only the name, like ally players
	["plates.petOwner"]         = true,    -- small line under a pet's name with its owner
	["plates.guildFriends"]     = false,   -- guild of allied players (small line under / above the name)
	["plates.guildEnemies"]     = false,   -- guild of enemy players
	["plates.friendHealth"]     = "none",  -- numbers on allies with a health bar: none | value | percent | both
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
	["auras.purgeMax"]        = 3,
	["auras.mine"]            = true,   -- HARMFUL|PLAYER on enemies
	["auras.minePlayers"]     = true,
	["auras.mineMax"]         = 6,
	["auras.dispel"]          = true,   -- HARMFUL|RAID_PLAYER_DISPELLABLE on allies
	["auras.dispelMax"]       = 3,
	["auras.mineTimer"]       = true,   -- time left on the icons of each row
	["auras.purgeTimer"]      = true,
	["auras.dispelTimer"]     = true,

	-- appearance of each part (Look.lua): size and opacity in %, offsets in pixels (right, up);
	-- "place" of the small second line: auto (under a name-only plate, above a plate with a bar) | above | below
	["look.enemyName.scale"]   = 115,
	["look.enemyName.alpha"]   = 100,
	["look.enemyName.color"]   = "game",  -- game | class (players) | white | custom
	["look.enemyName.rgb"]     = "ffffffff",
	["look.enemyName.where"]   = "game",  -- game (as the nameplate style draws it) | above | inside the bar
	["look.enemyGuild.scale"]  = 100,     -- of the name's size
	["look.enemyGuild.alpha"]  = 85,      -- of the name's opacity
	["look.enemyGuild.place"]  = "auto",
	["look.enemyGuild.rgb"]    = "ffd9d9d9",
	["look.enemyHealth.scale"] = 100,
	["look.enemyHealth.alpha"] = 100,
	["look.castText.scale"]    = 115,     -- spell name a bit bigger than the game's
	["look.castText.alpha"]    = 100,
	["look.castTimer.scale"]   = 115,
	["look.castTimer.alpha"]   = 100,
	["look.mine.scale"]        = 100,     -- 100% = 22 px
	["look.mine.alpha"]        = 100,
	["look.purge.scale"]       = 100,     -- 100% = 20 px
	["look.purge.alpha"]       = 100,
	["look.gameBuffs.scale"]   = 100,
	["look.gameBuffs.alpha"]   = 100,
	["look.gameDebuffs.scale"] = 100,
	["look.gameDebuffs.alpha"] = 100,
	["look.gameCC.scale"]      = 100,
	["look.gameCC.alpha"]      = 100,
	["look.quest.scale"]       = 100,     -- 100% = 14 px
	["look.quest.alpha"]       = 100,
	["look.friendName.scale"]  = 115,
	["look.friendName.alpha"]  = 55,      -- ally names see-through, so allies don't distract
	["look.friendName.color"]  = "white", -- class | white | custom
	["look.friendName.rgb"]    = "ffffffff",
	["look.friendName.where"]  = "game",  -- only for allies shown with a bar
	["look.friendGuild.scale"] = 100,
	["look.friendGuild.alpha"] = 85,
	["look.friendGuild.place"] = "auto",
	["look.friendGuild.rgb"]   = "ffd9d9d9",
	["look.friendHealth.scale"] = 100,
	["look.friendHealth.alpha"] = 100,
	["look.dispel.scale"]      = 100,     -- 100% = 16 px
	["look.dispel.alpha"]      = 100,
	["look.friendGame.scale"]  = 100,     -- the game's own icons on allies
	["look.friendGame.alpha"]  = 100,
	["look.petName.scale"]     = 115,
	["look.petName.alpha"]     = 55,
	["look.petName.color"]     = "class", -- class (the owner's) | white | custom
	["look.petName.rgb"]       = "ffffffff",
	["look.petOwner.scale"]    = 100,
	["look.petOwner.alpha"]    = 85,
	["look.petOwner.place"]    = "auto",
	-- every offset ("look.<element>.x" / ".y", "look.addonAuras.x" / ".y" for the enemy's two aura rows) is 0 by default

	-- text on the health and mana bars of your unit frame, your target's and your target's target
	-- (UnitFrames.lua). Off until turned on; then these formats apply, "game" leaves a bar to the game.
	-- formats: game | none | current | percent | currentPercent | currentMax | currentMaxPercent |
	--          missing | missingPercent | split (percent left, current right)
	-- when: always | combat | noCombat
	["frames.enabled"]        = false,
	["frames.number"]         = "short", -- short (12.3k) | full (12 345) | game
	["frames.decimals"]       = 1,
	["frames.player.health"]  = "currentPercent",
	["frames.player.mana"]    = "current",
	["frames.player.when"]    = "always",
	["frames.player.scale"]   = 100,
	["frames.target.health"]  = "currentPercent",
	["frames.target.mana"]    = "current",
	["frames.target.when"]    = "always",
	["frames.target.scale"]   = 100,
	["frames.tot.health"]     = "percent",
	["frames.tot.mana"]       = "none",
	["frames.tot.when"]       = "always",
	["frames.tot.scale"]      = 80,      -- its bars are small

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
	["killzone.rgb"]          = "ff141414", -- colour of the mark: a thin dark line, not a bright stripe
	["killzone.alpha"]        = 85,      -- its opacity, %
	["killzone.width"]        = 1,       -- line width, px
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
