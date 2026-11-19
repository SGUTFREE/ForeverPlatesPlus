local _, ns = ...

-- Extras on the game's enemy cast bars:
--  * time left, next to the bar;
--  * "interrupt not ready": the bar is greyed out while your interrupt is on cooldown
--    (only on casts that can be interrupted).
-- Cast data and cooldowns may be secret in Forever. The timer only reads the game's own numbers and
-- hides itself when they are secret; the grey layer is driven by the game from booleans
-- (SetAlphaFromBoolean), nothing secret is compared here.
local M = ns.RegisterModule("CastBar", {})

local THROTTLE = 0.05
local GREY_ALPHA = 0.55

-- class interrupts, the first one the player knows is used
local INTERRUPTS = {
	WARRIOR = { 6552, 72, 1671, 1672, 29704 },             -- Pummel, Shield Bash
	ROGUE = { 1766, 1767, 1768, 1769, 38768 },             -- Kick
	MAGE = { 2139 },                                       -- Counterspell
	SHAMAN = { 57994, 8042, 8044, 8045, 8046, 10412, 10413, 10414 }, -- Wind Shear, Earth Shock
	PRIEST = { 15487 },                                    -- Silence
	HUNTER = { 147362, 187707, 34490 },                    -- Counter Shot, Muzzle, Silencing Shot
	PALADIN = { 96231 },                                   -- Rebuke
	DRUID = { 106839, 16979 },                             -- Skull Bash, Feral Charge
	WARLOCK = { 19647, 19244, 119910 },                    -- Spell Lock (Felhunter)
	DEATHKNIGHT = { 47528 },                               -- Mind Freeze
	MONK = { 116705 },                                     -- Spear Hand Strike
	DEMONHUNTER = { 183752 },                              -- Disrupt
	EVOKER = { 351338 },                                   -- Quell
}

local interruptSpell -- spell ID of the player's interrupt, nil if none
local extras = setmetatable({}, { __mode = "k" }) -- game unit frame -> our extras on its cast bar

local function IsKnown(spellID)
	if not (C_SpellBook and C_SpellBook.IsSpellKnown) then
		return false
	end
	local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID)
	if ok and known == true then
		return true
	end
	-- pet abilities (Spell Lock)
	local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
	if bank then
		ok, known = pcall(C_SpellBook.IsSpellKnown, spellID, bank)
		return ok and known == true
	end
	return false
end

local function ResolveInterrupt()
	interruptSpell = nil
	local _, class = UnitClass("player")
	for _, spellID in ipairs(INTERRUPTS[class] or {}) do
		if IsKnown(spellID) then
			interruptSpell = spellID
			return
		end
	end
end

function ns.GetInterruptSpell()
	return interruptSpell
end

------------------------------------------------------------------------

local function GetCastBar(unitFrame)
	local container = unitFrame.CastBarsContainer
	return container and container.castBar
end

local function UpdateTimer(extra)
	local castBar, text = extra.castBar, extra.timer
	if not extra.enabled or not ns.Get("cast.timer") then
		text:Hide()
		return
	end
	local value, maxValue = castBar.value, castBar.maxValue
	if ns.IsSecret(value) or ns.IsSecret(maxValue) or type(value) ~= "number" or type(maxValue) ~= "number" then
		text:Hide() -- the game keeps this cast's timing secret here
		return
	end
	local remaining
	if castBar.channeling then
		remaining = value -- channels count down
	elseif castBar.casting or castBar.reverseChanneling then
		remaining = maxValue - value
	end
	if not remaining then
		text:Hide()
		return
	end
	text:SetText(("%.1f"):format(math.max(0, remaining)))
	text:Show()
end

-- how many values came back (0 = not casting) and the n-th one, without testing it (it may be secret)
local function Pick(n, ...)
	return select("#", ...), (select(n, ...))
end

local function UpdateInterrupt(extra)
	local layer = extra.interruptLayer
	if not extra.enabled or not ns.Get("cast.interruptReady") or not interruptSpell or not extra.unit then
		layer:Hide()
		return
	end
	-- only interruptible casts: the frame is see-through when the cast can't be interrupted
	local position = extra.castBar.channeling and 7 or 8 -- notInterruptible in UnitChannelInfo / UnitCastingInfo
	local count, notInterruptible
	if extra.castBar.channeling then
		count, notInterruptible = Pick(position, UnitChannelInfo(extra.unit))
	else
		count, notInterruptible = Pick(position, UnitCastingInfo(extra.unit))
	end
	local cooldown = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(interruptSpell, true)
	if count < position or not cooldown then
		layer:Hide()
		return
	end
	layer:SetAlphaFromBoolean(notInterruptible, 0, 1)
	extra.grey:SetAlphaFromBoolean(cooldown:IsActive(), GREY_ALPHA, 0)
	layer:Show()
end

local function OnUpdate(holder, elapsed)
	holder.sinceUpdate = (holder.sinceUpdate or 0) + elapsed
	if holder.sinceUpdate < THROTTLE then
		return
	end
	holder.sinceUpdate = 0
	local extra = holder.extra
	local ok, err = pcall(UpdateTimer, extra)
	if ok then
		ok, err = pcall(UpdateInterrupt, extra)
	end
	if not ok then
		holder:SetScript("OnUpdate", nil) -- don't repeat an error every frame
		geterrorhandler()("ForeverPlatesPlus CastBar: " .. tostring(err))
	end
end

local function CreateExtras(unitFrame)
	local castBar = GetCastBar(unitFrame)
	if not castBar then
		return nil
	end
	-- child of the cast bar: shown and hidden together with it
	local holder = CreateFrame("Frame", nil, castBar)
	holder:SetAllPoints(castBar)
	holder:SetFrameLevel(castBar:GetFrameLevel() + 2)

	local timer = holder:CreateFontString(nil, "OVERLAY")
	local font, size, flags
	if castBar.Text and castBar.Text.GetFont then
		font, size, flags = castBar.Text:GetFont()
	end
	if font then
		timer:SetFont(font, size or 10, flags)
	else
		timer:SetFontObject("SystemFont_NamePlate_Outlined")
	end
	timer:SetJustifyH("LEFT")
	timer:Hide()

	local interruptLayer = CreateFrame("Frame", nil, holder)
	interruptLayer:SetAllPoints(castBar)
	local grey = interruptLayer:CreateTexture(nil, "OVERLAY")
	grey:SetAllPoints(castBar)
	grey:SetColorTexture(0.12, 0.12, 0.12, 1)
	grey:SetAlpha(0)
	interruptLayer:Hide()

	local extra = { castBar = castBar, holder = holder, timer = timer, interruptLayer = interruptLayer, grey = grey }
	holder.extra = extra
	holder:SetScript("OnUpdate", OnUpdate)
	return extra
end

-- size, opacity and place of the spell name and the timer (appearance page); every plate, the game's
-- cast bar text is re-anchored by the game on each layout, so this runs again after it
local function ApplyLook(unitFrame)
	local castBar = GetCastBar(unitFrame)
	if not castBar then
		return
	end
	local scale, alpha = ns.LookScale("castText"), ns.LookAlpha("castText")
	for _, text in ipairs({ castBar.Text, castBar.CastTargetNameText }) do
		if type(text) == "table" then
			ns.ApplyTextScale(text, scale)
			ns.ApplyAlpha(text, alpha)
		end
	end
	if type(castBar.Text) == "table" then
		ns.PlaceRegion(castBar.Text, ns.LookOffset("castText"))
	end
	local extra = extras[unitFrame]
	if extra then
		local timer = extra.timer
		local dx, dy = ns.LookOffset("castTimer")
		timer:ClearAllPoints()
		timer:SetPoint("LEFT", castBar, "RIGHT", 3 + dx, dy)
		if timer.SetTextScale then
			timer:SetTextScale(ns.LookScale("castTimer"))
		end
		timer:SetAlpha(ns.LookAlpha("castTimer"))
	end
end

local function IsEnemy(unit)
	local kind = ns.GetUnitKind(unit)
	return kind == "enemyNpc" or kind == "enemyPlayer"
end

function M:OnInit()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_LOGIN", "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE", "UNIT_PET" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", ResolveInterrupt)
end

local function SetUpExtras(unit, unitFrame)
	local wanted = IsEnemy(unit) and (ns.Get("cast.timer") or ns.Get("cast.interruptReady"))
	local extra = extras[unitFrame]
	if not wanted then
		if extra then
			extra.enabled = false
			extra.unit = nil
			extra.timer:Hide()
			extra.interruptLayer:Hide()
		end
		return
	end
	if not extra then
		extra = CreateExtras(unitFrame)
		if not extra then
			return
		end
		extras[unitFrame] = extra
	end
	extra.enabled = true
	extra.unit = unit
	if not extra.holder:GetScript("OnUpdate") then
		extra.holder:SetScript("OnUpdate", OnUpdate) -- re-arm after an earlier error
	end
end

function M:OnPlateAdded(unit, unitFrame)
	SetUpExtras(unit, unitFrame)
	ApplyLook(unitFrame)
end

function M:OnPlateLayout(_, unitFrame)
	ApplyLook(unitFrame)
end

function M:OnPlateRemoved(_, unitFrame)
	local extra = extras[unitFrame]
	if extra then
		extra.enabled = false
		extra.unit = nil
		extra.timer:Hide()
		extra.interruptLayer:Hide()
	end
end

function M:Apply(key)
	if key and not key:find("^cast%.") and not key:find("^look%.") then
		return
	end
	ns.ForEachPlate(function(unit, unitFrame)
		M:OnPlateAdded(unit, unitFrame)
	end)
end
