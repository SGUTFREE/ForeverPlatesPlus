local _, ns = ...

-- Text on the health and mana bars of your own unit frame, your target's and your target's target.
-- Every bar is the game's ("as in the game") until a format is chosen for it; then the game's own texts
-- on that bar are made invisible and ours are drawn on top, in the same font and place.
-- Health and power may be secret values in Forever: here they are never compared or calculated with,
-- only handed to the game's number formatters and to SetFormattedText, which accept them.
local M = ns.RegisterModule("UnitFrames", {})

ns.UNIT_FRAMES = { "player", "target", "tot" }

local THROTTLE = 0.1 -- seconds between refreshes (target of target sends no events of its own)

local function Path(root, ...)
	local node = root
	for i = 1, select("#", ...) do
		if type(node) ~= "table" then
			return nil
		end
		node = node[(select(i, ...))]
	end
	return type(node) == "table" and node or nil
end

local DEFS = {
	player = {
		unit = function()
			return (PlayerFrame and type(PlayerFrame.unit) == "string" and PlayerFrame.unit) or "player"
		end,
		health = function()
			return Path(PlayerFrame, "PlayerFrameContent", "PlayerFrameContentMain", "HealthBarsContainer", "HealthBar")
		end,
		mana = function()
			return Path(PlayerFrame, "PlayerFrameContent", "PlayerFrameContentMain", "ManaBarArea", "ManaBar")
		end,
	},
	target = {
		unit = function()
			return "target"
		end,
		health = function()
			return Path(TargetFrame, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer", "HealthBar")
		end,
		mana = function()
			return Path(TargetFrame, "TargetFrameContent", "TargetFrameContentMain", "ManaBar")
		end,
	},
	tot = {
		unit = function()
			return "targettarget"
		end,
		health = function()
			return Path(TargetFrame, "totFrame", "HealthBar") or Path(_G.TargetFrameToT, "HealthBar")
		end,
		mana = function()
			return Path(TargetFrame, "totFrame", "ManaBar") or Path(_G.TargetFrameToT, "ManaBar")
		end,
	},
}

------------------------------------------------------------------------
-- values (possibly secret)
------------------------------------------------------------------------

local percentCurve -- 0..1 -> 0..100, for the game's percent functions
local function PercentCurve()
	if percentCurve == nil then
		percentCurve = false
		if C_CurveUtil and C_CurveUtil.CreateCurve then
			local ok, curve = pcall(C_CurveUtil.CreateCurve)
			if ok and curve and pcall(curve.AddPoint, curve, 0, 0) and pcall(curve.AddPoint, curve, 1, 100) then
				percentCurve = curve
			end
		end
	end
	return percentCurve or nil
end

local function Call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, value = pcall(fn, ...)
	if ok then
		return value
	end
	return nil
end

-- current, max, missing, percent (0..100) of health or power; any of them may be nil or secret
local function Values(unit, kind)
	local cur, max, missing, pct
	if kind == "health" then
		cur, max = Call(UnitHealth, unit), Call(UnitHealthMax, unit)
		missing = Call(UnitHealthMissing, unit)
		local curve = PercentCurve()
		if curve then
			pct = Call(UnitHealthPercent, unit, true, curve)
		end
	else
		cur, max = Call(UnitPower, unit), Call(UnitPowerMax, unit)
		missing = Call(UnitPowerMissing, unit)
		local curve = PercentCurve()
		if curve then
			pct = Call(UnitPowerPercent, unit, nil, false, curve)
		end
	end
	-- without the game's helpers (or on values that aren't secret) work them out here
	local plain = cur ~= nil and max ~= nil and not ns.IsSecret(cur) and not ns.IsSecret(max)
	if plain and missing == nil then
		missing = max - cur
	end
	if plain and pct == nil and max > 0 then
		pct = cur / max * 100
	end
	return cur, max, missing, pct
end

------------------------------------------------------------------------
-- formats
------------------------------------------------------------------------

-- known zero (only when the value isn't secret)
local function IsZero(value)
	return value ~= nil and not ns.IsSecret(value) and value <= 0
end

-- write a bar's text into the three strings: center, left, right
function ns.RenderBarText(strings, format, cur, max, missing, pct, style, decimals)
	local center, left, right = strings.center, strings.left, strings.right
	center:SetText("")
	left:SetText("")
	right:SetText("")
	if format == "none" or cur == nil then
		return
	end
	local function N(value)
		local ok, text = pcall(ns.FormatNumber, value, style, decimals)
		return ok and text or ""
	end
	if format == "current" then
		center:SetFormattedText("%s", N(cur))
	elseif format == "percent" then
		if pct ~= nil then
			center:SetFormattedText("%.0f%%", pct)
		end
	elseif format == "currentPercent" then
		if pct ~= nil then
			center:SetFormattedText("%s (%.0f%%)", N(cur), pct)
		else
			center:SetFormattedText("%s", N(cur))
		end
	elseif format == "currentMax" then
		center:SetFormattedText("%s / %s", N(cur), N(max))
	elseif format == "currentMaxPercent" then
		if pct ~= nil then
			center:SetFormattedText("%s / %s (%.0f%%)", N(cur), N(max), pct)
		else
			center:SetFormattedText("%s / %s", N(cur), N(max))
		end
	elseif format == "missing" then
		if missing ~= nil and not IsZero(missing) then
			center:SetFormattedText("-%s", N(missing))
		end
	elseif format == "missingPercent" then
		if missing == nil or IsZero(missing) then
			if pct ~= nil then
				center:SetFormattedText("%.0f%%", pct)
			end
		elseif pct ~= nil then
			center:SetFormattedText("-%s (%.0f%%)", N(missing), pct)
		else
			center:SetFormattedText("-%s", N(missing))
		end
	elseif format == "split" then
		if pct ~= nil then
			left:SetFormattedText("%.0f%%", pct)
		end
		right:SetFormattedText("%s", N(cur))
	end
end

------------------------------------------------------------------------
-- our strings on the bars
------------------------------------------------------------------------

local overlays = setmetatable({}, { __mode = "k" }) -- status bar -> { center, left, right, game = { ... } }

local function GameTexts(bar)
	local texts = {}
	for i, key in ipairs({ "TextString", "LeftText", "RightText" }) do
		local text = bar[key]
		texts[i] = type(text) == "table" and text or false
	end
	return texts
end

local function GetOverlay(bar)
	local overlay = overlays[bar]
	if overlay then
		return overlay
	end
	local game = GameTexts(bar)
	local anchorText = game[1] or game[2] or game[3] or nil
	local parent = bar
	if anchorText and anchorText.GetParent then
		parent = anchorText:GetParent() or bar
	end
	local font = anchorText and anchorText.GetFontObject and anchorText:GetFontObject() or _G.TextStatusBarText
	overlay = { game = game }
	local places = {
		center = { "CENTER", game[1], "CENTER", 0 },
		left = { "LEFT", game[2], "LEFT", 3 },
		right = { "RIGHT", game[3], "RIGHT", -3 },
	}
	for side, place in pairs(places) do
		local text = parent:CreateFontString(nil, "OVERLAY")
		if font then
			text:SetFontObject(font)
		end
		if place[2] then -- the game's string of that side
			text:SetPoint(place[1], place[2], place[3], 0, 0)
		else
			text:SetPoint(place[1], bar, place[3], place[4], 0)
		end
		overlay[side] = text
	end
	overlays[bar] = overlay
	return overlay
end

local function SetGameTextsAlpha(overlay, alpha)
	if overlay.gameAlpha == alpha then
		return
	end
	overlay.gameAlpha = alpha
	for _, text in pairs(overlay.game) do
		if text and text.SetAlpha then
			text:SetAlpha(alpha)
		end
	end
end

local function Clear(overlay)
	overlay.center:SetText("")
	overlay.left:SetText("")
	overlay.right:SetText("")
end

-- give a bar back to the game
local function Release(bar)
	local overlay = overlays[bar]
	if overlay then
		Clear(overlay)
		SetGameTextsAlpha(overlay, 1)
	end
end

------------------------------------------------------------------------
-- refresh
------------------------------------------------------------------------

local function InCombat()
	return (InCombatLockdown and InCombatLockdown()) or ns.SafeBool(UnitAffectingCombat("player")) == true
end

local function WhenAllows(when)
	if when == "combat" then
		return InCombat()
	elseif when == "noCombat" then
		return not InCombat()
	end
	return true
end

local function UpdateBar(bar, unit, kind, format, visible, scale)
	if not bar then
		return
	end
	if format == "game" then
		Release(bar)
		return
	end
	local overlay = GetOverlay(bar)
	SetGameTextsAlpha(overlay, 0)
	for _, side in ipairs({ "center", "left", "right" }) do
		if overlay[side].SetTextScale and overlay.scale ~= scale then
			overlay[side]:SetTextScale(scale)
		end
	end
	overlay.scale = scale
	if not visible or not UnitExists(unit) or (kind == "health" and ns.SafeBool(UnitIsDeadOrGhost(unit)) == true) then
		Clear(overlay)
		return
	end
	local cur, max, missing, pct = Values(unit, kind)
	if kind == "mana" and IsZero(max) then
		Clear(overlay)
		return
	end
	ns.RenderBarText(overlay, format, cur, max, missing, pct, ns.Get("frames.number"), ns.Get("frames.decimals"))
end

local function UpdateFrame(frameKey)
	local def = DEFS[frameKey]
	local prefix = "frames." .. frameKey .. "."
	local unit = def.unit()
	local visible = WhenAllows(ns.Get(prefix .. "when"))
	local scale = math.max(0.5, math.min(2, (tonumber(ns.Get(prefix .. "scale")) or 100) / 100))
	UpdateBar(def.health(), unit, "health", ns.Get(prefix .. "health"), visible, scale)
	UpdateBar(def.mana(), unit, "mana", ns.Get(prefix .. "mana"), visible, scale)
end

-- is any bar given a format of ours
local function Active()
	for _, frameKey in ipairs(ns.UNIT_FRAMES) do
		for _, kind in ipairs({ "health", "mana" }) do
			local format = ns.Get("frames." .. frameKey .. "." .. kind)
			if format and format ~= "game" then
				return true
			end
		end
	end
	return false
end
ns.UnitFramesActive = Active

-- does a frame have a bar of ours (for the settings sketch)
function ns.UnitFrameChanged(frameKey)
	for _, kind in ipairs({ "health", "mana" }) do
		local format = ns.Get("frames." .. frameKey .. "." .. kind)
		if format and format ~= "game" then
			return true
		end
	end
	return false
end

local function UpdateAll()
	if not Active() then
		return
	end
	for _, frameKey in ipairs(ns.UNIT_FRAMES) do
		local ok, err = pcall(UpdateFrame, frameKey)
		if not ok and ns.Debug then
			ns.Debug("UnitFrames: " .. tostring(err))
		end
	end
end

local function ReleaseAll()
	for bar in pairs(overlays) do
		Release(bar)
	end
end

local driver
local elapsed = 0

local function OnUpdate(_, delta)
	elapsed = elapsed + delta
	if elapsed >= THROTTLE then
		elapsed = 0
		UpdateAll()
	end
end

local function Start()
	if not driver then
		driver = CreateFrame("Frame")
		for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_TARGET" }) do
			pcall(driver.RegisterEvent, driver, event)
		end
		driver:SetScript("OnEvent", function()
			UpdateAll()
		end)
	end
	driver:SetScript("OnUpdate", OnUpdate)
	UpdateAll()
end

local function Stop()
	if driver then
		driver:SetScript("OnUpdate", nil)
	end
	ReleaseAll()
end

-- copy one frame's text choices to the others (settings button)
function ns.CopyFrameText(fromKey)
	for _, frameKey in ipairs(ns.UNIT_FRAMES) do
		if frameKey ~= fromKey then
			for _, prop in ipairs({ "health", "mana", "when" }) do
				ns.Set("frames." .. frameKey .. "." .. prop, ns.Get("frames." .. fromKey .. "." .. prop))
			end
		end
	end
end

function M:OnLogin()
	if Active() then
		Start()
	end
end

function M:Apply(key)
	if key and not key:find("^frames%.") then
		return
	end
	if Active() then
		Start() -- bars set back to "as in the game" are given back on this first refresh
	else
		Stop()
	end
end

-- for tests
ns.UpdateUnitFrames = UpdateAll
function ns.GetFrameOverlay(bar)
	return overlays[bar]
end
