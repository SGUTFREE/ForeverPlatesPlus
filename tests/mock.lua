-- Minimal WoW API mock for exercising ForeverPlates outside the game.
-- Only what the addon touches; every frame method not listed is a recorded no-op.

LOG = {}
local function log(...) table.insert(LOG, table.concat({ ... }, " ")) end

ERRORS = {}
function geterrorhandler() return function(msg) table.insert(ERRORS, tostring(msg)) end end
PRINTS = {}
print = function(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
	table.insert(PRINTS, table.concat(parts, " "))
end

LOCALE = LOCALE or "ruRU"
function GetLocale() return LOCALE end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function strsplit(sep, s, n)
	local out, start = {}, 1
	while true do
		if n and #out == n - 1 then out[#out + 1] = s:sub(start); break end
		local i = s:find(sep, start, true)
		if not i then out[#out + 1] = s:sub(start); break end
		out[#out + 1] = s:sub(start, i - 1)
		start = i + #sep
	end
	return unpack(out)
end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
SlashCmdList = {}

-- secrets ---------------------------------------------------------------
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end,
	__lt = function() error("attempt to compare a secret value") end,
	__le = function() error("attempt to compare a secret value") end,
	__eq = function() error("attempt to compare a secret value") end })
SECRET_VALUE = SECRET
function issecretvalue(v) return v == nil and false or rawequal(v, SECRET) end

-- combat / timers -------------------------------------------------------
IN_COMBAT = false
IN_INSTANCE = false
function IsInInstance() return IN_INSTANCE, IN_INSTANCE and "party" or "none" end
function InCombatLockdown() return IN_COMBAT end
C_Timer = { queue = {} }
function C_Timer.After(_, fn) table.insert(C_Timer.queue, fn) end
function RunTimers()
	local q = C_Timer.queue
	C_Timer.queue = {}
	for _, fn in ipairs(q) do fn() end
end

-- enums -----------------------------------------------------------------
Enum = {
	NamePlateInfoDisplay = { None = 0, CurrentHealthPercent = 1, CurrentHealthValue = 2, RarityIcon = 3 },
	NamePlateCastBarDisplay = { None = 0, SpellName = 1, SpellIcon = 2, SpellTarget = 3, HighlightImportantCasts = 4, HighlightWhenCastTarget = 5 },
	NamePlateEnemyNpcAuraDisplay = { None = 0, Buffs = 1, Debuffs = 2, CrowdControl = 3 },
	NamePlateEnemyPlayerAuraDisplay = { None = 0, Buffs = 1, Debuffs = 2, LossOfControl = 3 },
	NamePlateFriendlyPlayerAuraDisplay = { None = 0, Buffs = 1, Debuffs = 2, LossOfControl = 3 },
	NamePlateThreatDisplay = { None = 0, Progressive = 1, Flash = 2, HealthBarColor = 3 },
	NamePlateStackType = { None = 0, Enemy = 1, Friendly = 2 },
	NamePlateStyle = { Modern = 0, Thin = 1, Block = 2, HealthFocus = 3, CastFocus = 4, Legacy = 5, Classic = 6 },
}
AnchorUtil = { FlowDirection = { Left = 1, Right = 2, Up = 3, Down = 4 } }

-- CVars -----------------------------------------------------------------
CVARS = CVARS or {
	nameplateInfoDisplay = "0", nameplateCastBarDisplay = "0", nameplateThreatDisplay = "0",
	nameplateEnemyNpcAuraDisplay = "0", nameplateEnemyPlayerAuraDisplay = "0", nameplateFriendlyPlayerAuraDisplay = "0",
	nameplateStackingTypes = "0", nameplateShowAll = "0", nameplateShowOffscreen = "1", nameplateShowFriendlyNpcs = "1",
	nameplateOccludedAlphaMult = "0.6", nameplateStyle = "1", nameplateDebuffPadding = "2",
	nameplateShowOnlyNameForFriendlyPlayerUnits = "0", nameplateUseClassColorForFriendlyPlayerUnitNames = "0",
	nameplateShowFriendlyPlayerMinions = "0", UnitNameFriendlyMinionName = "1",
	nameplateShowEnemyMinions = "1", nameplateShowEnemyMinus = "0", nameplateSimplifiedTypes = "3",
	nameplateMaxDistance = "41",
}
local DEFAULTS = {}
for k, v in pairs(CVARS) do DEFAULTS[k] = v end
CVAR_SETS = 0
local function bits(name) return tonumber(CVARS[name]) or 0 end
C_CVar = {}
function C_CVar.GetCVar(name) return CVARS[name] end
function C_CVar.GetCVarDefault(name) return DEFAULTS[name] end
function C_CVar.SetCVar(name, value)
	assert(not IN_COMBAT, "SetCVar in combat: " .. name)
	assert(CVARS[name] ~= nil, "unknown cvar " .. name)
	CVARS[name] = tostring(value); CVAR_SETS = CVAR_SETS + 1
	return true
end
function C_CVar.GetCVarBitfield(name, index)
	assert(index >= 1, "luaIndex must be >= 1")
	return math.floor(bits(name) / 2 ^ (index - 1)) % 2 == 1
end
function C_CVar.SetCVarBitfield(name, index, value)
	assert(not IN_COMBAT, "SetCVarBitfield in combat: " .. name)
	assert(CVARS[name] ~= nil, "unknown cvar " .. name)
	assert(type(value) == "boolean", "bitfield value must be boolean")
	local cur = C_CVar.GetCVarBitfield(name, index)
	local b = bits(name)
	if value and not cur then b = b + 2 ^ (index - 1) elseif (not value) and cur then b = b - 2 ^ (index - 1) end
	CVARS[name] = tostring(math.floor(b)); CVAR_SETS = CVAR_SETS + 1
	return true
end

-- frames ----------------------------------------------------------------
local VALID_FILTERS = { HELPFUL = 1, HARMFUL = 1, PLAYER = 1, RAID = 1, CANCELABLE = 1, INCLUDE_NAME_PLATE_ONLY = 1, MAW = 1,
	EXTERNAL_DEFENSIVE = 1, CROWD_CONTROL = 1, RAID_IN_COMBAT = 1, RAID_PLAYER_DISPELLABLE = 1, BIG_DEFENSIVE = 1, IMPORTANT = 1, DISPELLABLE = 1 }

local FrameMethods = {}
FrameMethods.__index = function(self, key)
	local m = FrameMethods[key]
	if m then return m end
	if type(key) == "string" and key:match("^%u") then
		return function() return nil end -- any other widget method: no-op
	end
	return nil
end

local function NewObject(kind, parent)
	local o = setmetatable({ kind = kind, parent = parent, shown = true, scripts = {}, points = {}, events = {} }, FrameMethods)
	return o
end

function FrameMethods:RegisterEvent(e) assert(KNOWN_EVENTS[e] ~= false, "unknown event " .. e); self.events[e] = true end
function FrameMethods:RegisterUnitEvent(e, ...) self.events[e] = true; self.unitEventUnits = { ... } end
function FrameMethods:UnregisterEvent(e) self.events[e] = nil end
function FrameMethods:SetScript(name, fn) self.scripts[name] = fn end
function FrameMethods:Show() self.shown = true end
function FrameMethods:Hide() self.shown = false end
function FrameMethods:IsShown() return self.shown end
function FrameMethods:SetShown(v) self.shown = v and true or false end
function FrameMethods:GetFrameLevel() return self.level or 1 end
function FrameMethods:SetFrameLevel(l) self.level = l end
function FrameMethods:ClearAllPoints() self.points = {} end
-- like the game: setting a point that is already set replaces it
function FrameMethods:SetPoint(point, ...)
	for i, p in ipairs(self.points) do
		if p[1] == point then self.points[i] = { point, ... }; return end
	end
	table.insert(self.points, { point, ... })
end
function FrameMethods:SetScale(v) self.scale = v end
function FrameMethods:GetScale() return self.scale or 1 end
function FrameMethods:IsVisible() return self.shown end
function FrameMethods:SetAllPoints(rel) self.points = { { "ALL", rel } } end
function FrameMethods:SetSize(w, h) self.width, self.height = w, h end
function FrameMethods:SetWidth(w) self.width = w end
function FrameMethods:SetColorTexture(r, g, b, a) self.color = { r, g, b, a == nil and 1 or a } end
function FrameMethods:SetWordWrap(v) self.wordWrap = v end
function FrameMethods:CanWordWrap() if self.wordWrap == nil then return true end return self.wordWrap end
function FrameMethods:GetWidth() return self.width or 140 end
function FrameMethods:SetAlpha(a) self.alpha = a end
function FrameMethods:GetCenter() return 100, 100 end
function FrameMethods:GetEffectiveScale() return 1 end
function FrameMethods:CreateTexture() return NewObject("Texture", self) end
function FrameMethods:CreateFontString(_, _, template) local fs = NewObject("FontString", self); fs.template = template; return fs end
function FrameMethods:SetTextHeight(h) assert(type(h) == "number", "SetTextHeight needs a number"); self.textHeight = h end
function FrameMethods:SetStatusBarTexture(t) self.barTexture = NewObject("Texture", self) end
function FrameMethods:GetStatusBarTexture() return self.barTexture end
function FrameMethods:SetMinMaxValues(a, b) self.min, self.max = a, b end
function FrameMethods:GetValue() return self.value end
function FrameMethods:SetText(t) self.text = t end
-- like the game: secret arguments are allowed and make the text secret
function FrameMethods:SetFormattedText(fmt, ...)
	for i = 1, select("#", ...) do
		if issecretvalue((select(i, ...))) then self.text = SECRET; return end
	end
	self.text = fmt:format(...)
end
function FrameMethods:GetNumPoints() return #self.points end
function FrameMethods:GetPoint(i) local p = self.points[i or 1]; if p then return unpack(p, 1, 5) end end
function FrameMethods:SetJustifyH(j) self.justify = j end
function FrameMethods:GetJustifyH() return self.justify or "LEFT" end
function hooksecurefunc(t, key, fn)
	if type(t) == "string" then t, key, fn = _G, t, key end
	local orig = t[key]
	assert(type(orig) == "function", "hooksecurefunc: no function " .. tostring(key))
	rawset(t, key, function(...) local r = { orig(...) }; fn(...); return unpack(r) end)
end
function FrameMethods:SetValue(v) self.value = v end

-- aura container
local function ValidateFilter(filter)
	for token in filter:gmatch("[^|]+") do
		local bare = token:gsub("^!", "")
		assert(VALID_FILTERS[bare], "invalid aura filter component: " .. token)
	end
end
function FrameMethods:AddAuraGroup(key, filter, options)
	assert(self.kind == "AuraContainer")
	assert(type(key) == "string" and key ~= "")
	assert(not self.groups[key], "group exists")
	ValidateFilter(filter)
	assert(options.maxFrameCount == nil or (type(options.maxFrameCount) == "number" and options.maxFrameCount >= 0 and options.maxFrameCount == math.floor(options.maxFrameCount)), "maxFrameCount must be a non-negative integer")
	if options.layout then
		for _, f in ipairs({ "elementSpacing", "lineSpacing", "groupSpacing", "groupLineSpacing", "elementWidth", "elementHeight", "layoutIndex" }) do
			local v = options.layout[f]
			assert(v == nil or type(v) == "number", f .. " must be a number")
		end
	end
	self.groups[key] = { filter = filter, enabled = true, options = options, buttons = {} }
	-- the game creates a batch of frames up front
	for _ = 1, 3 do
		local b = NewObject("AuraButton", self)
		table.insert(self.groups[key].buttons, b)
		if options.initializeFrame then options.initializeFrame(b) end
	end
end
function FrameMethods:SetAuraGroupEnabled(key, v) assert(self.groups[key], "no group " .. key); assert(type(v) == "boolean", "enabled must be boolean"); self.groups[key].enabled = v end
function FrameMethods:SetAuraGroupMaxFrameCount(key, n) assert(self.groups[key]); assert(type(n) == "number" and n == math.floor(n) and n >= 0, "bad max"); self.groups[key].max = n end
function FrameMethods:SetAuraGroupLayout(key, layout) assert(self.groups[key]); self.groups[key].layout = layout end
function FrameMethods:SetFlowLayoutAnchorPoint(p) assert(type(p) == "string") end
function FrameMethods:SetFlowLayoutGrowthDirection(h, v) assert(h and v, "directions") end
function FrameMethods:SetFlowLayoutMaximumLineSize(n) assert(n == nil or type(n) == "number") end
function FrameMethods:SetEnabled(v) self.enabled = v end
function FrameMethods:SetUnit(u) assert(type(u) == "string", "SetUnit needs a string"); self.unit = u end
function FrameMethods:UpdateAllAuras() self.updates = (self.updates or 0) + 1 end
-- aura button
function FrameMethods:SetIcon(t) assert(t and t.kind == "Texture"); self.icon = t end
function FrameMethods:SetDurationCooldown(c) assert(c and c.kind == "Cooldown"); self.cooldown = c end
function FrameMethods:SetApplicationCount(fs) assert(fs and fs.kind == "FontString"); self.count = fs end
function FrameMethods:SetDurationText(fs, opts) assert(fs and fs.kind == "FontString"); self.durationText = fs; self.durationOpts = opts end
function FrameMethods:ClearDurationText() self.durationText = nil end

ALL_FRAMES = {}
function CreateFrame(kind, name, parent, template)
	if kind == "AuraContainer" then
		assert(template == "CustomAuraContainerTemplate", "aura containers need the template")
	end
	local f = NewObject(kind, parent)
	f.template = template
	f.name = name
	if kind == "AuraContainer" then f.groups = {} end
	table.insert(ALL_FRAMES, f)
	return f
end
C_XMLUtil = { GetTemplateInfo = function(name) return name == "CustomAuraContainerTemplate" and {} or nil end }
C_StringUtil = { CreateNumericRuleFormatter = function()
	return { bps = {}, AddBreakpoint = function(self, bp) assert(bp.threshold and bp.format); table.insert(self.bps, bp) end }
end }

KNOWN_EVENTS = KNOWN_EVENTS or {}

-- number formatting (secret in -> secret out)
function AbbreviateLargeNumbers(v) if issecretvalue(v) then return SECRET end; return ("%.2fK"):format(v / 1000) end
function BreakUpLargeNumbers(v) if issecretvalue(v) then return SECRET end; local s = tostring(math.floor(v)); return (s:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "")) end
ABBREV_CONFIGS = 0
function CreateAbbreviateConfig(data)
	for _, bp in ipairs(data) do
		assert(type(bp.breakpoint) == "number" and type(bp.abbreviation) == "string" and type(bp.significandDivisor) == "number" and type(bp.fractionDivisor) == "number", "bad breakpoint")
		assert(math.abs(bp.significandDivisor * bp.fractionDivisor - bp.breakpoint) < 1e-6, "significand x fraction must equal the breakpoint order")
	end
	for i = 2, #data do assert(data[i - 1].breakpoint > data[i].breakpoint, "breakpoints must go from largest to smallest") end
	ABBREV_CONFIGS = ABBREV_CONFIGS + 1
	return { data = data }
end
function AbbreviateNumbers(v, options)
	if issecretvalue(v) then return SECRET end
	local data = options and (options.config and options.config.data or options.breakpointData) or {}
	for _, bp in ipairs(data) do
		if v >= bp.breakpoint then
			local significand = math.floor(v / bp.significandDivisor)
			local decimals = math.floor(math.log10(bp.fractionDivisor) + 0.5)
			return ("%." .. decimals .. "f"):format(significand / bp.fractionDivisor) .. bp.abbreviation
		end
	end
	return tostring(v)
end

-- spells ------------------------------------------------------------------
SPELLS = {
	[32379] = { name = "Слово Тьмы: Смерть", desc = "Слово, исполненное темной силы, наносит цели |cffffffff412|r ед. урона от темной магии. Если цель не погибает, вы получаете урон." },
}
SPELL_BY_NAME = {} -- name -> spellID the player knows (rank / override)
C_Spell = {}
function C_Spell.GetSpellName(id) local s = SPELLS[id]; return s and s.name end
function C_Spell.GetSpellInfo(idOrName)
	if type(idOrName) == "string" then
		local id = SPELL_BY_NAME[idOrName]
		if not id then for k, v in pairs(SPELLS) do if v.name == idOrName then id = k end end end
		return id and { spellID = id, name = idOrName } or nil
	end
	local s = SPELLS[idOrName]; return s and { spellID = idOrName, name = s.name } or nil
end
function C_Spell.GetSpellDescription(id) local s = SPELLS[id]; return s and s.desc end
SPELL_LOAD_REQUESTS = 0
KNOWN_SPELLS = { [585] = true } -- Smite
function C_Spell.IsSpellInRange(spell, unit) local u = UNITS[unit]; if not u then return nil end; return u.inRange end
COOLDOWNS = {} -- spellID -> active (true/false/SECRET)
function C_Spell.GetSpellCooldownDuration(spell, ignoreGCD)
	assert(ignoreGCD == true, "interrupt check must ignore the GCD")
	if COOLDOWNS[spell] == nil then return nil end
	local active = COOLDOWNS[spell]
	return { IsActive = function() return active end }
end
C_SpellBook = { IsSpellKnown = function(id, bank) if bank then return false end; return KNOWN_SPELLS[id] == true end }
Enum = Enum or {}
Enum.SpellBookSpellBank = { Player = 0, Pet = 1 }
CASTS = {} -- unit -> { notInterruptible = bool, channel = bool }
function UnitCastingInfo(u)
	local c = CASTS[u]; if not c or c.channel then return end
	return "Spell", "", 1, 1000, 2000, false, 7, c.notInterruptible, 123
end
function UnitChannelInfo(u)
	local c = CASTS[u]; if not c or not c.channel then return end
	return "Channel", "", 1, 1000, 2000, false, c.notInterruptible, 123
end
C_QuestLog = { UnitIsRelatedToActiveQuest = function(u) return (UNITS[u] or {}).quest == true end }
function C_Spell.RequestLoadSpellData() SPELL_LOAD_REQUESTS = SPELL_LOAD_REQUESTS + 1 end

-- units & nameplates ------------------------------------------------------
UNITS = {}
function UnitClass(u) local x = UNITS[u] or {}; return x.className, x.class end
function UnitCanAttack(_, u) return (UNITS[u] or {}).canAttack end
function UnitIsPlayer(u) return (UNITS[u] or {}).isPlayer end
function UnitIsFriend(_, u) return (UNITS[u] or {}).isFriend end
function UnitHealthMax(u) return (UNITS[u] or {}).maxHealth end
function UnitHealth(u) return (UNITS[u] or {}).health end
function UnitPower(u) return (UNITS[u] or {}).power end
function UnitPowerMax(u) return (UNITS[u] or {}).maxPower end
function UnitIsDeadOrGhost(u) return (UNITS[u] or {}).dead == true end
function UnitAffectingCombat(u) return (UNITS[u] or {}).inCombat end
function UnitExists(u) return UNITS[u] ~= nil end
function UnitIsMinion(u) return (UNITS[u] or {}).isMinion or false end
function UnitIsOtherPlayersPet(u) return (UNITS[u] or {}).isPet or false end
function FrameMethods:SetVertexColor(r, g, b) self.vertex = { r, g, b } end
function FrameMethods:SetAlphaFromBoolean(b, yes, no)
	if issecretvalue(b) then self.alpha = SECRET; self.alphaFromSecret = true; return end
	assert(type(b) == "boolean", "SetAlphaFromBoolean needs a boolean")
	self.alpha = b and yes or no
end
function FrameMethods:GetFont() return self.font or "Fonts\\FRIZQT__.TTF", self.fontSize or 10, "OUTLINE" end
function FrameMethods:SetFont(f, size, flags) self.font, self.fontSize = f, size end
function FrameMethods:GetScript(name) return self.scripts[name] end
-- the game's name update: colours a friendly NPC name green
function CompactUnitFrame_UpdateName(frame) frame.name:SetVertexColor(0, 1, 0) end
function UnitIsUnit(a, b) return a == b end
function FrameMethods:SetStatusBarColor(r, g, b, a) self.barColor = { r, g, b, a } end
function FrameMethods:SetTextScale(v) self.textScale = v end
function FrameMethods:SetTextColor(r, g, b) self.textColor = { r, g, b } end
function GetGuildInfo(u) local d = UNITS[u]; if d then return d.guild end end
function UnitName(u) local d = UNITS[u]; return d and d.name end
function IsInRaid() return false end
UNITNAME_TITLE_PET = "Питомец %s"
UNITNAME_TITLE_MINION = "Прислужник %s"
RAID_CLASS_COLORS = { HUNTER = { r = 0.67, g = 0.83, b = 0.45 }, WARLOCK = { r = 0.53, g = 0.53, b = 0.93 } }
C_TooltipInfo = { GetUnit = function(u)
	local d = UNITS[u]; if not d then return nil end
	local lines = { { leftText = d.name or "?" } }
	if d.ownerLine then table.insert(lines, { leftText = d.ownerLine }) end
	return { lines = lines }
end }
IN_GROUP, PLAYER_ROLE = false, "NONE"
function IsInGroup() return IN_GROUP end
function UnitGroupRolesAssigned() return PLAYER_ROLE end
THREAT = {} -- unit -> scaled percentage (nil = not on its threat list)
function UnitDetailedThreatSituation(_, u)
	local t = THREAT[u]
	if t == nil then return end
	return false, 0, t, t, 1000
end
C_Texture = { GetAtlasInfo = function(name) if name == "UI-HUD-Nameplates-Aggro-Flare" then return { width = 64, height = 10 } end end }

PLATES = {}
function MakePlate(unit)
	local plate = NewObject("NamePlate")
	local uf = NewObject("UnitFrame", plate)
	uf.HealthBarsContainer = NewObject("Frame", uf)
	uf.HealthBarsContainer.healthBar = NewObject("StatusBar", uf.HealthBarsContainer)
	uf.name = NewObject("FontString", uf)
	local hb = uf.HealthBarsContainer.healthBar
	hb.Text = NewObject("FontString", hb); hb.LeftText = NewObject("FontString", hb); hb.RightText = NewObject("FontString", hb)
	-- the game's text status bar (TextStatusBar.lua): fields swapped like NamePlateHealthBarMixin:OnLoad
	hb.TextString = hb.Text
	hb.LeftText, hb.RightText = hb.RightText, hb.LeftText
	hb.showNumeric, hb.showPercentage = true, true
	rawset(hb, "UpdateTextStringWithValues", function(self, textString, value)
		if self.showPercentage then
			self.LeftText:SetText("100%"); self.RightText:SetText(AbbreviateLargeNumbers(value))
			self.LeftText:Show(); self.RightText:Show(); textString:Hide()
		else
			self.LeftText:Hide(); self.RightText:Hide()
			textString:SetText(AbbreviateLargeNumbers(value)); textString:Show()
		end
	end)
	uf.CastBarsContainer = NewObject("Frame", uf)
	uf.CastBarsContainer.castBar = NewObject("StatusBar", uf.CastBarsContainer)
	uf.CastBarsContainer.castBar.Text = NewObject("FontString", uf.CastBarsContainer.castBar)
	uf.CastBarsContainer.castBar.Icon = NewObject("Texture", uf.CastBarsContainer.castBar)
	uf.CastBarsContainer.castBar.CastTargetNameText = NewObject("FontString", uf.CastBarsContainer.castBar)
	-- the game's aura lists (Blizzard_NamePlates.xml): buffs left of the bar, debuffs above the name, CC right
	uf.AurasFrame = NewObject("Frame", uf)
	-- left of the bar: raid mark, elite dragon (hidden ones take no room), then the game's buffs
	uf.ClassificationFrame = NewObject("Frame", uf)
	uf.ClassificationFrame:SetPoint("RIGHT", uf.HealthBarsContainer, "LEFT", 0, 0)
	uf.AurasFrame.BuffListFrame = NewObject("Frame", uf.AurasFrame)
	uf.AurasFrame.BuffListFrame:SetPoint("RIGHT", uf.ClassificationFrame, "LEFT", -5, 0)
	uf.AurasFrame.DebuffListFrame = NewObject("Frame", uf.AurasFrame)
	uf.AurasFrame.DebuffListFrame:SetPoint("LEFT", uf.HealthBarsContainer, "LEFT", 0, 0)
	uf.AurasFrame.CrowdControlListFrame = NewObject("Frame", uf.AurasFrame)
	uf.AurasFrame.LossOfControlFrame = NewObject("Frame", uf.AurasFrame)
	uf.PlayerLevelDiffFrame = NewObject("Frame", uf)
	uf.PlayerLevelDiffFrame.width = 26
	uf.PlayerLevelDiffFrame:SetPoint("LEFT", uf.HealthBarsContainer, "RIGHT", 2, 0)
	-- the game's name layout (Blizzard_NamePlateUnitFrame UpdateAnchors): Thin = name centred above the bar,
	-- spanning bar + level frame; Modern = name inside the bar, ending where the health numbers start
	rawset(uf, "UpdateAnchors", function(self)
		self.layoutRuns = (self.layoutRuns or 0) + 1
		-- cast bar text (ApplyStyleAndAnchoring), health numbers, the game's debuff row and CC (UpdateControlAnchors)
		local cb = self.CastBarsContainer.castBar
		cb.Text:ClearAllPoints(); cb.Text:SetPoint("LEFT", cb.Icon, "RIGHT", 2, 0)
		local bar = self.HealthBarsContainer.healthBar
		bar.LeftText:ClearAllPoints(); bar.RightText:ClearAllPoints(); bar.Text:ClearAllPoints()
		if not self.showOnlyName then
			bar.LeftText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
			bar.RightText:SetPoint("RIGHT", bar.LeftText, "LEFT", -2, 0)
			bar.Text:SetPoint("RIGHT", bar.RightText, "LEFT", 2, 0)
		end
		if self.AurasFrame and self.AurasFrame.DebuffListFrame then
			self.AurasFrame.DebuffListFrame:SetPoint("BOTTOM", self.name, "TOP", 0, 2)
			self.AurasFrame.CrowdControlListFrame:ClearAllPoints()
			self.AurasFrame.CrowdControlListFrame:SetPoint("LEFT", self.HealthBarsContainer, "RIGHT", 5, 0)
			self.AurasFrame.LossOfControlFrame:SetPoint("LEFT", self.HealthBarsContainer, "RIGHT", 5, 0)
		end
		self.name:ClearAllPoints()
		if self.showOnlyName then
			-- name-only (friendly players with the game option on)
			self.name:SetJustifyH("CENTER")
			self.name:SetPoint("BOTTOMLEFT", self.HealthBarsContainer, "TOPLEFT", 4, 2)
			self.name:SetPoint("BOTTOMRIGHT", self.HealthBarsContainer, "TOPRIGHT", -4, 2)
		elseif CVARS.nameplateStyle == "0" then
			self.name:SetJustifyH("LEFT")
			self.name:SetPoint("LEFT", self.HealthBarsContainer, "LEFT", 4, 0)
			self.name:SetPoint("RIGHT", self.HealthBarsContainer.healthBar.Text, "LEFT", -2, 0)
		else
			self.name:SetJustifyH("CENTER")
			self.name:SetPoint("BOTTOMLEFT", self.HealthBarsContainer, "TOPLEFT", 0, 2)
			self.name:SetPoint("RIGHT", self.PlayerLevelDiffFrame, "RIGHT", 0, 0)
		end
	end)
	uf:UpdateAnchors()
	plate.UnitFrame = uf
	PLATES[unit] = plate
	return plate
end
C_NamePlate = { GetNamePlateForUnit = function(unit, includeForbidden)
	local p = PLATES[unit]
	if p and rawget(p, "forbidden") and not includeForbidden then return nil end
	return p
end }

Minimap = NewObject("Frame"); Minimap.width = 140
GameTooltip = NewObject("GameTooltip")
CURSOR_X, CURSOR_Y = 100, 200
function GetCursorPosition() return CURSOR_X, CURSOR_Y end

-- settings ----------------------------------------------------------------
SETTINGS = {}
Settings = { VarType = { Boolean = "boolean", String = "string", Number = "number" } }
function Settings.RegisterVerticalLayoutCategory(name)
	local cat = { name = name, GetID = function() return 42 end }
	local lay = { inits = {}, AddInitializer = function(self, i) table.insert(self.inits, i) end }
	SETTINGS.category, SETTINGS.layout = cat, lay
	return cat, lay
end
SETTINGS.pages = {}
function Settings.RegisterVerticalLayoutSubcategory(parent, name)
	assert(parent and parent.GetID, "subcategory needs the main category")
	local cat = { name = name, parent = parent, GetID = function() return 100 + #SETTINGS.pages end }
	local lay = { inits = {}, AddInitializer = function(self, i) table.insert(self.inits, i) end }
	table.insert(SETTINGS.pages, name)
	SETTINGS.layouts = SETTINGS.layouts or {}
	SETTINGS.layouts[name] = lay
	return cat, lay
end
function Settings.RegisterProxySetting(cat, variable, varType, name, default, get, set)
	assert(type(variable) == "string")
	assert(type(default) == varType, ("default for %s is %s, expected %s"):format(variable, type(default), varType))
	assert(not SETTINGS[variable], "duplicate setting " .. variable)
	local s = { variable = variable, varType = varType, default = default, get = get, set = set, notified = 0, page = cat.name }
	function s:NotifyUpdate() self.notified = self.notified + 1; self.get() end
	function s:GetValue() return self.get() end
	-- like the game's Setting:SetValue: the setter only runs when the value changes
	function s:SetValue(v) if self.get() ~= v then self.set(v) end end
	SETTINGS[variable] = s
	return s
end
-- the shown predicates the game's settings list checks (ShouldShow)
local function AddShown(init)
	init.shown = {}
	function init:AddShownPredicate(fn) table.insert(self.shown, fn) end
	function init:ShouldShow() for _, fn in ipairs(self.shown) do if not fn() then return false end end; return true end
end
local function NewInitializer(s)
	local init = { setting = s }
	AddShown(init)
	function init:SetParentInitializer(parent, predicate) self.parent = parent; self.predicate = predicate end
	s.init = init
	return init
end
function Settings.CreateCheckbox(cat, s) s.control = "checkbox"; return NewInitializer(s) end
function Settings.CreateSlider(cat, s, options) s.control = "slider"; s.options = options; return NewInitializer(s) end
function Settings.CreateDropdown(cat, s, getOptions) s.control = "dropdown"; s.getOptions = getOptions; return NewInitializer(s) end
function Settings.CreateColorSwatch(cat, s) s.control = "color"; return NewInitializer(s) end
function Settings.CreateSliderOptions(min, max, step)
	return { min = min, max = max, step = step, SetLabelFormatter = function(self, t, f) self.formatter = f end }
end
function Settings.CreateControlTextContainer()
	local c = { data = {} }
	function c:Add(v, l) table.insert(self.data, { value = v, label = l }) end
	function c:GetData() return self.data end
	return c
end
function Settings.RegisterAddOnCategory(cat) SETTINGS.registered = cat end
function Settings.OpenToCategory(id) SETTINGS.opened = id end
MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }
function CreateSettingsListSectionHeaderInitializer(t, tooltip)
	local init = { header = t, tooltip = tooltip }
	AddShown(init)
	return init
end
CreateFromMixins = CreateFromMixins or function(...)
	local t = {}
	for _, m in ipairs({ ... }) do for k, v in pairs(m) do t[k] = v end end
	return t
end
-- the game's pieces for drawing page descriptions; present only when a test asks for them
if DESCRIPTIONS_AVAILABLE then
	SettingsListSectionHeaderMixin = { Init = function(self, initializer) self.headerInit = initializer end }
	function Settings.CreateElementInitializer(template, data)
		return { template = template, data = data, GetName = function(self) return self.data.name end }
	end
	local getTemplateInfo = C_XMLUtil.GetTemplateInfo
	C_XMLUtil.GetTemplateInfo = function(name)
		if name == "ForeverPlatesDescriptionTemplate" or name == "ForeverPlatesPreviewTemplate" then return {} end
		return getTemplateInfo(name)
	end
end
function CreateSettingsButtonInitializer(name, text, click, tt, tags)
	assert(tags ~= nil)
	local init = { button = name, click = click, shown = {} }
	function init:AddShownPredicate(fn) table.insert(self.shown, fn) end
	return init
end
SETTINGS.buttons = {}

-- event helper --------------------------------------------------------------
function FireEvent(event, ...)
	for _, f in ipairs(ALL_FRAMES) do
		if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
	end
end
