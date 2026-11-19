local _, ns = ...
local L = ns.L

-- Health numbers and friendly names.
--
-- Number format: the game writes health with its own abbreviation. After each game update of the text
-- the number is written again in the chosen format (short with N decimals, full, or the game's own).
-- Health may be secret: the game's abbreviation functions accept secret numbers, nothing is compared here.
--
-- Numbers: the game's health text option is one switch for every nameplate. Per plate, the number and
-- the percent are hidden by alpha (the game keeps managing the text as usual): on allies (unless turned
-- on), and on enemies by state: normally / on mouseover / as the target, each with its own choice.
-- Hidden texts are also shrunk to (almost) no width, so in styles with the name inside the bar they
-- don't take room.
--
-- Names: the game pins the name between two points (bar edge to bar edge, or to the level frame), so a
-- long name is cut with "...". The name is re-pinned by one point at the same place (same side, or the
-- same centre for centred names), so it is written in full. The game's own points are kept and put
-- back when the frame goes to another unit; after every game re-layout (UpdateAnchors) they are read again.
local M = ns.RegisterModule("HealthText", {})

local hidden = setmetatable({}, { __mode = "k" }) -- game unit frame -> true while all its numbers are hidden
local savedWordWrap = setmetatable({}, { __mode = "k" }) -- font string we hid -> its word wrap before
local textAlpha = setmetatable({}, { __mode = "k" }) -- shown font string -> opacity we gave it (nil = the game's)

local function HideText(text)
	if savedWordWrap[text] ~= nil then
		return -- already hidden; the game never touches alpha or width
	end
	savedWordWrap[text] = text:CanWordWrap() and true or false
	textAlpha[text] = nil
	text:SetAlpha(0)
	text:SetWordWrap(false)
	text:SetWidth(1)
end

-- alpha: the opacity chosen on the appearance page (1 = the game's)
local function RestoreText(text, alpha)
	if savedWordWrap[text] ~= nil then
		text:SetWidth(0) -- 0 = size to the text again (the game never sets a width on these)
		text:SetWordWrap(savedWordWrap[text])
		savedWordWrap[text] = nil
		text:SetAlpha(alpha)
		textAlpha[text] = alpha ~= 1 and alpha or nil
	elseif (textAlpha[text] or 1) ~= alpha then
		text:SetAlpha(alpha)
		textAlpha[text] = alpha ~= 1 and alpha or nil
	end
end

local function SetTextShown(text, shown, alpha)
	if text then
		if shown then
			RestoreText(text, alpha)
		else
			HideText(text)
		end
	end
end

-- mode: "none" | "value" | "percent" | "both"; look: appearance element ("enemyHealth" / "friendHealth"),
-- false gives the game's size and opacity back
local function ShowNumbers(unitFrame, mode, look)
	local healthBar = unitFrame.HealthBarsContainer and unitFrame.HealthBarsContainer.healthBar
	if not healthBar then
		return
	end
	local alpha = look and ns.LookAlpha(look) or 1
	local scale = look and ns.LookScale(look) or 1
	for _, text in ipairs({ healthBar.RightText, healthBar.LeftText, healthBar.TextString or healthBar.Text }) do
		ns.ApplyTextScale(text, scale)
	end
	local showValue = mode == "value" or mode == "both"
	local showPercent = mode == "percent" or mode == "both"
	-- the game's text bar: with both on, RightText = number and LeftText = percent;
	-- with only one on, TextString holds it
	local single
	if healthBar.showNumeric and not healthBar.showPercentage then
		single = showValue
	elseif healthBar.showPercentage and not healthBar.showNumeric then
		single = showPercent
	else
		single = showValue or showPercent
	end
	SetTextShown(healthBar.RightText, showValue, alpha)
	SetTextShown(healthBar.LeftText, showPercent, alpha)
	SetTextShown(healthBar.TextString or healthBar.Text, single, alpha)
	hidden[unitFrame] = (not showValue and not showPercent) or nil
end

-- the numbers hang on one text pinned to the bar's right edge (the percent); the others follow it
local function PlaceNumbers(unitFrame, look)
	local healthBar = unitFrame.HealthBarsContainer and unitFrame.HealthBarsContainer.healthBar
	if healthBar and look then
		ns.PlaceRegion(healthBar.LeftText, ns.LookOffset(look))
	end
end

------------------------------------------------------------------------
-- full names
------------------------------------------------------------------------

local nameState = setmetatable({}, { __mode = "k" }) -- unit frame -> { points = game's points, want = bool, ours = bool }

-- vertical part of a left-side point: BOTTOMLEFT -> BOTTOM etc.
local VERTICAL = { BOTTOMLEFT = "BOTTOM", LEFT = "CENTER", TOPLEFT = "TOP" }

local function CapturePoints(name)
	local ok, count = pcall(name.GetNumPoints, name)
	if not ok or type(count) ~= "number" or ns.IsSecret(count) or count == 0 then
		return nil
	end
	local points = {}
	for i = 1, count do
		local okPoint, point, relativeTo, relativePoint, x, y = pcall(name.GetPoint, name, i)
		if not okPoint or type(point) ~= "string" or ns.IsSecret(x) or ns.IsSecret(y) then
			return nil
		end
		points[i] = { point, relativeTo, relativePoint or point, x or 0, y or 0 }
	end
	return points
end

local function FindPoint(points, side)
	for _, p in ipairs(points) do
		if p[1]:find(side) then
			return p
		end
	end
end

local function IsHealthText(unitFrame, region)
	local healthBar = unitFrame.HealthBarsContainer.healthBar
	return healthBar ~= nil and (rawequal(region, healthBar.Text) or rawequal(region, healthBar.LeftText) or rawequal(region, healthBar.RightText))
end

-- where the game's right edge of the name was, as an offset from the right edge of the health bar container
local function RightOffset(unitFrame, p)
	local container = unitFrame.HealthBarsContainer
	if rawequal(p[2], container) and p[3]:find("RIGHT") then
		return p[4]
	end
	local level = unitFrame.PlayerLevelDiffFrame
	if level and rawequal(p[2], level) and p[3]:find("RIGHT") then
		-- the level frame sits right of the bar; the game reserves its width plus the gap the same way
		local _, _, _, levelX = level:GetPoint()
		local width = level:GetWidth()
		if ns.IsSecret(levelX) or ns.IsSecret(width) then
			return nil
		end
		return (width or 0) + math.abs(levelX or 0) + p[4]
	end
	if IsHealthText(unitFrame, p[2]) and hidden[unitFrame] then
		return -4 -- hidden numbers are collapsed at the bar's right edge
	end
	return nil
end

local function PutBackGamePoints(unitFrame, state)
	local name = unitFrame.name
	name:ClearAllPoints()
	for _, p in ipairs(state.points) do
		name:SetPoint(p[1], p[2], p[3], p[4], p[5])
	end
	if state.justify then
		name:SetJustifyH(state.justify)
		state.justify = nil
	end
	state.ours = false
end

-- one point that keeps the name where the game put it but lets it grow; nil = keep the game's points
local function SinglePoint(unitFrame, points)
	local container = unitFrame.HealthBarsContainer
	local left, right = FindPoint(points, "LEFT"), FindPoint(points, "RIGHT")
	-- one point (or a layout we don't know): the name is already free
	if not left or not right or not rawequal(left[2], container) then
		return nil
	end
	-- never let the name run over numbers that are shown
	if IsHealthText(unitFrame, right[2]) and not hidden[unitFrame] then
		return nil
	end

	local justify = unitFrame.name:GetJustifyH()
	if justify == "LEFT" then
		return left[1], left[3], left[4], left[5]
	end
	local rightOffset = RightOffset(unitFrame, right)
	local vertical, relativeVertical = VERTICAL[left[1]], VERTICAL[left[3]]
	if not rightOffset or not vertical or not relativeVertical then
		return nil
	end
	if justify == "RIGHT" then
		return vertical == "CENTER" and "RIGHT" or vertical .. "RIGHT",
			relativeVertical == "CENTER" and "RIGHT" or relativeVertical .. "RIGHT",
			rightOffset, left[5]
	end
	-- centred between the game's two edges
	return vertical, relativeVertical, (left[4] + rightOffset) / 2, left[5]
end

local function ApplyName(unitFrame)
	local state = nameState[unitFrame]
	if not state or not state.points then
		return
	end
	local dx, dy = state.dx or 0, state.dy or 0
	local point, relativePoint, x, y, justify
	local width = 0 -- 0: the name takes the width of its text
	local name = unitFrame.name
	local where = state.where
	if unitFrame.showOnlyName then
		where = "game" -- a plate without a bar: the name has nowhere else to go
	end
	if state.center then
		-- an ally's pet shown as a name: centred over its (hidden) bar like the game's name-only plates,
		-- whatever side the game's layout puts the name on
		point, relativePoint, x, y, justify = "BOTTOM", "TOP", 0, 2, "CENTER"
	elseif where == "above" then
		point, relativePoint, x, y, justify = "BOTTOM", "TOP", 0, 2, "CENTER"
	elseif where == "inside" then
		point, relativePoint, x, y, justify = "LEFT", "LEFT", 4, 0, "LEFT"
		if not hidden[unitFrame] then
			-- numbers on the right of the bar: leave them room, the name is cut there
			local ok, barWidth = pcall(unitFrame.HealthBarsContainer.GetWidth, unitFrame.HealthBarsContainer)
			if ok and type(barWidth) == "number" and not ns.IsSecret(barWidth) and barWidth > 0 then
				width = math.max(20, math.floor(barWidth * 0.6))
			end
		end
	elseif state.want then
		point, relativePoint, x, y = SinglePoint(unitFrame, state.points)
	end
	if justify then
		if not state.justify then
			state.justify = name:GetJustifyH()
		end
		name:SetJustifyH(justify)
	elseif state.justify then
		name:SetJustifyH(state.justify)
		state.justify = nil
	end
	if point then
		name:ClearAllPoints()
		name:SetPoint(point, unitFrame.HealthBarsContainer, relativePoint, x + dx, y + dy)
		name:SetWidth(width)
		state.ours = true
	elseif dx ~= 0 or dy ~= 0 then
		-- the game's own points, moved (the name may still be cut where the game cuts it)
		name:ClearAllPoints()
		for _, p in ipairs(state.points) do
			name:SetPoint(p[1], p[2], p[3], p[4] + dx, p[5] + dy)
		end
		state.ours = true
	elseif state.ours then
		PutBackGamePoints(unitFrame, state)
	end
end

-- the game just laid the plate out again: its points replace ours
local function OnGameLayout(unitFrame)
	local state = nameState[unitFrame]
	if not state then
		return
	end
	state.ours = false
	state.justify = nil -- the game has just set its own
	state.points = CapturePoints(unitFrame.name)
	ApplyName(unitFrame)
end

-- want: write the name in full; dx, dy: move it from the game's place; center: centre it over the bar;
-- where: "game" | "above" (over the bar) | "inside" (in the bar, from the left)
local function SetNameLayout(unitFrame, want, dx, dy, center, where)
	if not unitFrame.name or not unitFrame.HealthBarsContainer then
		return
	end
	dx, dy = dx or 0, dy or 0
	where = (where == "above" or where == "inside") and where or "game"
	local state = nameState[unitFrame]
	if not state then
		if not want and not center and dx == 0 and dy == 0 and where == "game" then
			return
		end
		state = {}
		nameState[unitFrame] = state
	end
	if not state.ours then
		state.points = CapturePoints(unitFrame.name)
	end
	state.want = want
	state.where = where
	state.center = center and true or false
	state.dx, state.dy = dx, dy
	ApplyName(unitFrame)
end

------------------------------------------------------------------------
-- health number format
------------------------------------------------------------------------

local hookedBars = setmetatable({}, { __mode = "k" })
local shortOptions -- cached abbreviation options for the current decimals

-- decimals: nil = the nameplate setting
local function BuildShortOptions(decimals)
	decimals = math.floor((tonumber(decimals or ns.Get("health.decimals")) or 1) + 0.5)
	decimals = math.max(0, math.min(2, decimals))
	local fraction = 10 ^ decimals
	-- largest first; significand x fraction = the named order (thousands, millions, ...)
	local data = {}
	for _, step in ipairs({ { 1e9, L.ABBR_BILLION }, { 1e6, L.ABBR_MILLION }, { 1e3, L.ABBR_THOUSAND } }) do
		table.insert(data, {
			breakpoint = step[1],
			abbreviation = step[2],
			significandDivisor = step[1] / fraction,
			fractionDivisor = fraction,
			abbreviationIsGlobal = false,
		})
	end
	if CreateAbbreviateConfig then
		local ok, config = pcall(CreateAbbreviateConfig, data)
		if ok and config then
			return { config = config }
		end
	end
	return { breakpointData = data }
end

-- a number for display in a style: "short" (12.3k, decimals 0..2), "full" (12 345), "game" (the game's
-- own shortening). The value may be secret: it only goes through the game's formatters.
local shortByDecimals = {}
function ns.FormatNumber(value, style, decimals)
	if style == "full" then
		return BreakUpLargeNumbers(value)
	elseif style == "short" then
		decimals = math.max(0, math.min(2, math.floor((tonumber(decimals) or 1) + 0.5)))
		shortByDecimals[decimals] = shortByDecimals[decimals] or BuildShortOptions(decimals)
		return AbbreviateNumbers(value, shortByDecimals[decimals])
	end
	return AbbreviateLargeNumbers(value)
end

local function FormatHealth(value)
	local format = ns.Get("health.format")
	if format == "full" then
		return BreakUpLargeNumbers(value)
	elseif format == "short" then
		shortOptions = shortOptions or BuildShortOptions()
		return AbbreviateNumbers(value, shortOptions)
	end
	return AbbreviateLargeNumbers(value) -- what the game itself uses on nameplates
end

-- write the number into the font string the game used for it (only if the game shows it)
local function RenderHealth(healthBar, value, evenForGameFormat)
	-- value may be secret: never compared, only handed to the game's formatters
	if ns.Get("health.format") == "game" and not evenForGameFormat then
		return
	end
	local target
	if healthBar.showNumeric and healthBar.showPercentage then
		target = healthBar.RightText -- both: number here, percent next to it
	elseif healthBar.showNumeric then
		target = healthBar.TextString
	end
	if target and target:IsShown() then
		local ok, text = pcall(FormatHealth, value)
		if ok then
			target:SetText(text)
		end
	end
end

local barOwner = setmetatable({}, { __mode = "k" }) -- health bar -> its unit frame
local modeByFrame = setmetatable({}, { __mode = "k" }) -- unit frame -> numbers mode in effect
local lookByFrame = setmetatable({}, { __mode = "k" }) -- unit frame -> appearance element of its numbers

local function OnGameHealthText(healthBar, _, value)
	RenderHealth(healthBar, value)
	-- the game may have switched which text it uses (option changed): keep the plate's choice
	local unitFrame = barOwner[healthBar]
	local mode = unitFrame and modeByFrame[unitFrame]
	if mode then
		ShowNumbers(unitFrame, mode, lookByFrame[unitFrame])
	end
end

local function HookHealthBar(unitFrame)
	local healthBar = unitFrame.HealthBarsContainer and unitFrame.HealthBarsContainer.healthBar
	if healthBar and not hookedBars[healthBar] and type(healthBar.UpdateTextStringWithValues) == "function" then
		hookedBars[healthBar] = true
		barOwner[healthBar] = unitFrame
		hooksecurefunc(healthBar, "UpdateTextStringWithValues", OnGameHealthText)
	end
	return healthBar
end

------------------------------------------------------------------------

local frameUnit = setmetatable({}, { __mode = "k" }) -- unit frame -> its unit token
local dimmed = setmetatable({}, { __mode = "k" }) -- unit frame -> name opacity while we make it transparent

------------------------------------------------------------------------
-- allies' pets: name only
------------------------------------------------------------------------

-- The game's "name only" option covers ally players, not their pets. For pets the same look is made
-- here: the plate's other parts are made invisible (the game never sets their alpha) and the name is
-- coloured by the owner's class (or white). Not in dungeons and raids, where the game doesn't let
-- addons touch ally plates.
local PET_HIDDEN_PARTS = { "HealthBarsContainer", "CastBarsContainer", "AurasFrame", "PlayerLevelDiffFrame", "ClassificationFrame" }
local petMode = setmetatable({}, { __mode = "k" }) -- unit frame -> { color = { r, g, b }, owner = name|nil } while shown as a name only
local WHITE = { 1, 1, 1 }

-- the pet's tooltip lines after its name ("Pet of X", level...); secret lines are skipped
local function TooltipLines(unit)
	local lines = {}
	if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then
		return lines
	end
	local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
	if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then
		return lines
	end
	for i = 2, #data.lines do
		local line = data.lines[i]
		local text = type(line) == "table" and line.leftText
		if not ns.IsSecret(text) and type(text) ~= "string" and type(line) == "table" and type(line.args) == "table" then
			-- older tooltip data: the text sits in the line's args
			for _, arg in ipairs(line.args) do
				if type(arg) == "table" and arg.field == "leftText" then
					text = arg.stringVal
				end
			end
		end
		if not ns.IsSecret(text) and type(text) == "string" and text ~= "" then
			table.insert(lines, text)
		end
	end
	return lines
end

-- Forever players can have a surname: UnitName gives it as a second value, shown after a separator
local function SurnameSeparator()
	local consts = Constants and Constants.CharacterNameSeparatorConsts
	return consts and consts.CHARACTERNAME_SURNAME_SEPARATOR or " "
end

-- players the owner can be: you, your group, allies and enemy players whose plates are shown
local function OwnerCandidates()
	local candidates = {}
	local function Add(unit)
		if not UnitExists(unit) then
			return
		end
		local name, surname = UnitName(unit)
		local _, class = UnitClass(unit)
		if type(name) == "string" and not ns.IsSecret(name) and not ns.IsSecret(class) and class then
			local full = name
			if type(surname) == "string" and not ns.IsSecret(surname) and surname ~= "" then
				full = name .. SurnameSeparator() .. surname
			end
			table.insert(candidates, { name = name, full = full, class = class })
		end
	end
	Add("player")
	for i = 1, 4 do
		Add("party" .. i)
	end
	if IsInRaid and IsInRaid() then
		for i = 1, 40 do
			Add("raid" .. i)
		end
	end
	for unit in pairs(ns.activePlates) do
		if ns.SafeBool(UnitIsPlayer(unit)) then
			Add(unit)
		end
	end
	return candidates
end

-- a name without its last letter: Russian tooltips decline names ("Питомец Артроза" for Артроз)
local function Stem(name)
	local letters = select(2, name:gsub("[^\128-\191]", ""))
	if letters < 4 then
		return nil
	end
	return name:match("^(.*)[%z\1-\127\194-\244][\128-\191]*$")
end

-- the pet's owner (class, full name with the surname), found by the owner's name in the pet's tooltip
local function PetOwner(unit)
	local lines = TooltipLines(unit)
	if #lines == 0 then
		return nil
	end
	local candidates = OwnerCandidates()
	for _, text in ipairs(lines) do
		for _, candidate in ipairs(candidates) do
			if text:find(candidate.name, 1, true) then
				return candidate.class, candidate.full
			end
		end
	end
	for _, text in ipairs(lines) do
		for _, candidate in ipairs(candidates) do
			local stem = Stem(candidate.name)
			if stem and text:find(stem, 1, true) then
				return candidate.class, candidate.full
			end
		end
	end
end

-- for /fpl debug
function ns.DebugPet(unit, unitFrame)
	if not unit then
		return "pet=?"
	end
	local info = petMode[unitFrame]
	local lines = TooltipLines(unit)
	return ("pet=%s owner=%s tooltip=%d [%s]"):format(info == nil and "no" or (info.color == WHITE and "white" or "coloured"),
		tostring((PetOwner(unit))), #lines, lines[1] or "")
end

local function ClassColor(class)
	local color = class and ((C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class))
		or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
	if color and color.r then
		return { color.r, color.g, color.b }
	end
end

-- { color = { r, g, b }, owner = name|nil } for a pet shown as a name only
local function PetInfo(unit)
	local class, owner = PetOwner(unit)
	local mode, rgbElement = ns.PetColorMode()
	local color
	if mode == "custom" then
		color = { ns.LookRGB(rgbElement) }
	elseif mode == "class" then
		color = ClassColor(class) or WHITE
	else
		color = WHITE
	end
	return { color = color, owner = owner }
end

local function IsAllyPet(unit)
	return ns.SafeBool(UnitIsOtherPlayersPet and UnitIsOtherPlayersPet(unit)) == true
		or ns.SafeBool(UnitIsUnit(unit, "pet")) == true
		or ns.SafeBool(UnitIsMinion and UnitIsMinion(unit)) == true
end
ns.IsAllyPet = IsAllyPet

-- info: { color, owner } for the name, or nil to show the plate normally again (the colour is set with the name's)
local function SetPetNameOnly(unitFrame, info)
	if info then
		for _, key in ipairs(PET_HIDDEN_PARTS) do
			local part = unitFrame[key]
			if type(part) == "table" and part.SetAlpha then
				part:SetAlpha(0)
			end
		end
		petMode[unitFrame] = info
	elseif petMode[unitFrame] then
		for _, key in ipairs(PET_HIDDEN_PARTS) do
			local part = unitFrame[key]
			if type(part) == "table" and part.SetAlpha then
				part:SetAlpha(1)
			end
		end
		petMode[unitFrame] = nil
	end
end

------------------------------------------------------------------------
-- name colour
------------------------------------------------------------------------

-- The game colours a name on each of its name updates; a colour chosen here is put back on top right
-- after. The game's own colour is remembered (never compared: it may be secret) to give it back.
local nameColor = setmetatable({}, { __mode = "k" }) -- unit frame -> { r, g, b } kept on its name
local gameNameColor = setmetatable({}, { __mode = "k" }) -- unit frame -> the game's last { r, g, b }

local function RememberGameColor(unitFrame)
	local name = unitFrame.name
	if name and name.GetVertexColor then
		local ok, r, g, b = pcall(name.GetVertexColor, name)
		if ok and r ~= nil then
			gameNameColor[unitFrame] = { r, g, b }
		end
	end
end

-- color: { r, g, b }, or nil for the game's colour
local function SetNameColor(unitFrame, color)
	local name = unitFrame.name
	if not name then
		return
	end
	if color then
		if not nameColor[unitFrame] then
			RememberGameColor(unitFrame)
		end
		nameColor[unitFrame] = color
		name:SetVertexColor(color[1], color[2], color[3])
	elseif nameColor[unitFrame] then
		nameColor[unitFrame] = nil
		local game = gameNameColor[unitFrame]
		if game then
			name:SetVertexColor(game[1], game[2], game[3])
		end
	end
end

if type(CompactUnitFrame_UpdateName) == "function" then
	hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
		local color = nameColor[frame]
		if color and frame.name then
			RememberGameColor(frame)
			frame.name:SetVertexColor(color[1], color[2], color[3])
		end
	end)
end

-- the colour a name should have, nil = the game's. Ally "class" is the game's own option (NativeOptions),
-- so it works in dungeons too; enemy "class" colours players only.
local function NameColor(unit, element, pet)
	if pet then
		return pet.color
	end
	local mode = ns.LookColorMode(element)
	if mode == "white" then
		return WHITE
	elseif mode == "custom" then
		return { ns.LookRGB(element) }
	elseif mode == "class" and element == "enemyName" then
		if ns.SafeBool(UnitIsPlayer(unit)) then
			local _, class = UnitClass(unit)
			if class and not ns.IsSecret(class) then
				return ClassColor(class)
			end
		elseif ns.SafeBool(UnitIsOtherPlayersPet and UnitIsOtherPlayersPet(unit)) == true then
			-- an enemy player's pet: the owner's class colour, once the owner's plate is around
			return ClassColor((PetOwner(unit)))
		end
	end
	return nil
end

-- alpha: 0..1, or nil for the game's own (the game never changes the name's alpha itself)
local function SetNameAlpha(unitFrame, alpha)
	local name = unitFrame.name
	if not name then
		return
	end
	if alpha then
		name:SetAlpha(alpha)
		dimmed[unitFrame] = alpha
	elseif dimmed[unitFrame] then
		name:SetAlpha(1)
		dimmed[unitFrame] = nil
	end
end

-- name size: the game sets the font height itself (and never the text scale), so a scale on top stays
local scaled = setmetatable({}, { __mode = "k" }) -- unit frame -> scale we set
local function SetNameScale(unitFrame, scale)
	local name = unitFrame.name
	if not name or not name.SetTextScale then
		return
	end
	if scale then
		if scaled[unitFrame] ~= scale then
			name:SetTextScale(scale)
			scaled[unitFrame] = scale
		end
	elseif scaled[unitFrame] then
		name:SetTextScale(1)
		scaled[unitFrame] = nil
	end
end

-- the name size on a plate (1 = the game's), for rows drawn above the name
function ns.GetNameScale(unitFrame)
	return unitFrame and scaled[unitFrame] or 1
end

-- where the addon put the name: "above" / "inside" the bar, nil = the game's place
function ns.GetNamePlace(unitFrame)
	local state = unitFrame and nameState[unitFrame]
	if not state or state.center or unitFrame.showOnlyName then
		return nil
	end
	return (state.where == "above" or state.where == "inside") and state.where or nil
end

-- how far the name was moved up (negative: down)
function ns.GetNameOffsetY(unitFrame)
	local state = unitFrame and nameState[unitFrame]
	return state and state.dy or 0
end

------------------------------------------------------------------------
-- subtitle: a small second line with the pet's owner or the player's guild
------------------------------------------------------------------------

-- Under the name when the plate shows only the name; above it when there is a health bar under the
-- name (the extra aura row then moves up, see Auras).
local SUBTITLE_SIZE = 0.85 -- of the name's font size
local SUBTITLE_GAP = 1
local subtitles = setmetatable({}, { __mode = "k" }) -- unit frame -> our font string
local subtitleAbove = setmetatable({}, { __mode = "k" }) -- unit frame -> height of a subtitle shown above the name

local function ShowsOnlyName(unitFrame)
	return unitFrame.showOnlyName == true or petMode[unitFrame] ~= nil
end

-- element: "enemyGuild", "friendGuild" or "petOwner" (size, opacity and place relative to the name)
local function SetSubtitle(unitFrame, text, color, element)
	local line = subtitles[unitFrame]
	local name = unitFrame.name
	if not text or not name then
		if line then
			line:Hide()
		end
		if subtitleAbove[unitFrame] then
			subtitleAbove[unitFrame] = nil
			if ns.ReanchorAuras then
				ns.ReanchorAuras(unitFrame)
			end
		end
		return
	end
	if not line then
		line = unitFrame:CreateFontString(nil, "OVERLAY")
		subtitles[unitFrame] = line
	end
	local font, size, flags = name:GetFont()
	size = (tonumber(size) or 12) * SUBTITLE_SIZE
	if font then
		line:SetFont(font, size, flags)
	else
		line:SetFontObject("SystemFont_NamePlate_Outlined")
	end
	local scale = (scaled[unitFrame] or 1) * ns.LookScale(element)
	if line.SetTextScale then
		line:SetTextScale(scale)
	end
	line:SetText(text)
	line:SetTextColor(color[1], color[2], color[3])
	line:SetAlpha((dimmed[unitFrame] or 1) * ns.LookAlpha(element))
	line:ClearAllPoints()
	local place = ns.LookPlace(element)
	local above
	if place == "auto" then
		above = not ShowsOnlyName(unitFrame)
	else
		above = place == "above"
	end
	local dx, dy = ns.LookOffset(element)
	-- lined up with the name's text: a name written from the left edge gets its line from the left edge too
	local justify = name:GetJustifyH()
	local side = (justify == "LEFT" or justify == "RIGHT") and justify or ""
	line:SetJustifyH(side == "" and "CENTER" or side)
	if above then
		line:SetPoint("BOTTOM" .. side, name, "TOP" .. side, dx, SUBTITLE_GAP + dy)
	else
		line:SetPoint("TOP" .. side, name, "BOTTOM" .. side, dx, -SUBTITLE_GAP + dy)
	end
	line:Show()
	local height = above and math.max(0, size * scale + SUBTITLE_GAP + dy) or nil
	if subtitleAbove[unitFrame] ~= height then
		subtitleAbove[unitFrame] = height
		if ns.ReanchorAuras then
			ns.ReanchorAuras(unitFrame)
		end
	end
end

-- the subtitle font string of a plate (for /fpl debug and tests)
function ns.GetSubtitleLine(unitFrame)
	return subtitles[unitFrame]
end

-- extra room the aura row has to leave above the name
function ns.GetSubtitleHeight(unitFrame)
	return subtitleAbove[unitFrame] or 0
end

-- "<Guild>" of a player, or nil
local function GuildTag(unit, kind)
	local wanted = (kind == "friendlyPlayer" and ns.Get("plates.guildFriends"))
		or (kind == "enemyPlayer" and ns.Get("plates.guildEnemies"))
	if not wanted then
		return nil
	end
	if not GetGuildInfo then
		return nil
	end
	local ok, guild = pcall(GetGuildInfo, unit)
	if not ok or ns.IsSecret(guild) or type(guild) ~= "string" or guild == "" then
		return nil
	end
	return "<" .. guild .. ">"
end

local function PlateFrame(token)
	local plate = C_NamePlate.GetNamePlateForUnit(token)
	return plate and plate.UnitFrame
end

local function NumbersMode(unit, unitFrame)
	local kind = ns.GetUnitKind(unit)
	if kind == "friendlyPlayer" or kind == "friendlyNpc" then
		return ns.Get("plates.friendHealth") or "none", true
	end
	if rawequal(unitFrame, PlateFrame("target")) then
		return ns.Get("enemyText.target"), false
	end
	if rawequal(unitFrame, PlateFrame("mouseover")) then
		return ns.Get("enemyText.mouseover"), false
	end
	return ns.Get("enemyText.idle"), false
end

local leftToGame = setmetatable({}, { __mode = "k" }) -- unit frame -> true while the plate is the game's own

-- give the plate back to the game: name, numbers and the second line as the game draws them
local function Release(unitFrame)
	modeByFrame[unitFrame] = nil
	SetNameLayout(unitFrame, false, 0, 0, false)
	SetNameAlpha(unitFrame, nil)
	SetNameScale(unitFrame, nil)
	SetPetNameOnly(unitFrame, nil)
	SetNameColor(unitFrame, nil)
	lookByFrame[unitFrame] = nil
	SetSubtitle(unitFrame, nil)
	ShowNumbers(unitFrame, "both", false)
	hidden[unitFrame] = nil
end

local function Update(unit, unitFrame)
	if ns.LeftToGame(unit) then
		if not leftToGame[unitFrame] then
			leftToGame[unitFrame] = true
			Release(unitFrame)
		end
		return
	end
	leftToGame[unitFrame] = nil
	local mode, isFriendly = NumbersMode(unit, unitFrame)
	local numbersLook = isFriendly and "friendHealth" or "enemyHealth"
	modeByFrame[unitFrame] = mode
	lookByFrame[unitFrame] = numbersLook
	ShowNumbers(unitFrame, mode, numbersLook)
	PlaceNumbers(unitFrame, numbersLook)

	local isPet = isFriendly and ns.Get("plates.petNamesOnly") and IsAllyPet(unit)
	local nameElement = (isPet and "petName") or (isFriendly and "friendName") or "enemyName"
	local wantFull
	if isFriendly then
		wantFull = ns.Get("plates.friendFullNames")
	else
		wantFull = ns.Get("plates.enemyFullNames")
	end
	local nameDx, nameDy = ns.LookOffset(nameElement)
	SetNameLayout(unitFrame, wantFull and true or false, nameDx, nameDy, isPet, not isPet and ns.Get("look." .. nameElement .. ".where"))

	local pet = isPet and PetInfo(unit) or nil
	SetPetNameOnly(unitFrame, pet)
	SetNameColor(unitFrame, NameColor(unit, nameElement, pet))

	local alpha = ns.LookAlpha(nameElement)
	SetNameAlpha(unitFrame, alpha ~= 1 and alpha or nil)

	local scale = ns.LookScale(nameElement)
	SetNameScale(unitFrame, scale ~= 1 and scale or nil)

	if pet and pet.owner and ns.Get("plates.petOwner") then
		SetSubtitle(unitFrame, pet.owner, pet.color, "petOwner")
	else
		local kind = ns.GetUnitKind(unit)
		local guildLook = kind == "enemyPlayer" and "enemyGuild" or "friendGuild"
		SetSubtitle(unitFrame, GuildTag(unit, kind), { ns.LookRGB(guildLook) }, guildLook)
	end
	-- the aura row above the name follows the name's size and place
	if ns.ReanchorAuras then
		ns.ReanchorAuras(unitFrame)
	end
end

local function Refresh(unitFrame)
	local unit = unitFrame and frameUnit[unitFrame]
	if unit and rawequal(ns.activePlates[unit], unitFrame) then
		Update(unit, unitFrame)
	end
end

-- the game laid the plate out again: name, numbers and the second line back where we want them
function M:OnPlateLayout(_, unitFrame)
	OnGameLayout(unitFrame)
	PlaceNumbers(unitFrame, lookByFrame[unitFrame])
	if subtitles[unitFrame] and subtitles[unitFrame]:IsShown() then
		Refresh(unitFrame) -- name only <-> with a bar: the line may change sides
	end
end

-- /fpl debug: what the addon sees on the plate under the cursor / of the target
function ns.DebugNames()
	local count = 0
	for _ in pairs(ns.activePlates) do
		count = count + 1
	end
	ns.Print(("debug: plates managed %d"):format(count))
	for _, token in ipairs({ "mouseover", "target" }) do
		if UnitExists(token) then
			local plate = C_NamePlate.GetNamePlateForUnit(token)
			if not plate then
				ns.Print(token .. ": plate closed to addons by the game (or no plate)")
			else
				local unitFrame = plate.UnitFrame
				local state = nameState[unitFrame]
				local parts = {
					token,
					"unit=" .. tostring(frameUnit[unitFrame]),
					"kind=" .. tostring(frameUnit[unitFrame] and ns.GetUnitKind(frameUnit[unitFrame])),
					"onlyName=" .. tostring(unitFrame.showOnlyName),
					"offset=" .. tostring(state and state.dx) .. "," .. tostring(state and state.dy),
					"want=" .. tostring(state and state.want),
					"ours=" .. tostring(state and state.ours),
					"captured=" .. tostring(state and state.points and #state.points),
					"justify=" .. tostring(unitFrame.name:GetJustifyH()),
				}
				local okCount, n = pcall(unitFrame.name.GetNumPoints, unitFrame.name)
				table.insert(parts, "points=" .. tostring(okCount and n))
				if okCount and type(n) == "number" then
					for i = 1, n do
						local ok, point, relativeTo, relativePoint, x, y = pcall(unitFrame.name.GetPoint, unitFrame.name, i)
						if ok then
							local relName = relativeTo and (rawequal(relativeTo, unitFrame.HealthBarsContainer) and "bars"
								or rawequal(relativeTo, unitFrame.PlayerLevelDiffFrame) and "level" or "other") or "nil"
							table.insert(parts, ("[%s %s %s %s %s]"):format(tostring(point), relName, tostring(relativePoint),
								ns.IsSecret(x) and "secret" or tostring(x), ns.IsSecret(y) and "secret" or tostring(y)))
						else
							table.insert(parts, "[error]")
						end
					end
				end
				if ns.DebugPet then
					table.insert(parts, ns.DebugPet(frameUnit[unitFrame], unitFrame))
				end
				ns.Print(table.concat(parts, " "))
			end
		end
	end
end

------------------------------------------------------------------------
-- target and mouseover
------------------------------------------------------------------------

local events = CreateFrame("Frame")
local lastTarget, lastMouseover
local sinceCheck = 0

local function OnTargetChanged()
	local new = PlateFrame("target")
	if not rawequal(new, lastTarget) then
		local old = lastTarget
		lastTarget = new
		Refresh(old)
		Refresh(new)
	end
end

local CheckMouseover

local function WatchMouseover(_, elapsed)
	sinceCheck = sinceCheck + (elapsed or 0)
	if sinceCheck >= 0.1 then
		sinceCheck = 0
		CheckMouseover()
	end
end

function CheckMouseover()
	local new = PlateFrame("mouseover")
	if not rawequal(new, lastMouseover) then
		local old = lastMouseover
		lastMouseover = new
		Refresh(old)
		Refresh(new)
	end
	-- no event fires when the cursor leaves a unit: watch while it is on one
	events:SetScript("OnUpdate", lastMouseover and WatchMouseover or nil)
end

-- pets whose owner wasn't known yet (white): look again when the group changes or a player plate appears
local petRefreshQueued = false
local function QueuePetRefresh()
	if petRefreshQueued then
		return
	end
	petRefreshQueued = true
	C_Timer.After(0.2, function()
		petRefreshQueued = false
		for unitFrame, info in pairs(petMode) do
			if not info.owner then
				Refresh(unitFrame)
			end
		end
	end)
end

events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_TARGET_CHANGED" then
		OnTargetChanged()
	elseif event == "GROUP_ROSTER_UPDATE" then
		QueuePetRefresh()
	else
		CheckMouseover()
	end
end)

------------------------------------------------------------------------

function M:OnInit()
	ns.RegisterUnitEvent("UNIT_FACTION")
	ns.RegisterUnitEvent("UNIT_NAME_UPDATE")
	events:RegisterEvent("PLAYER_TARGET_CHANGED")
	events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
	pcall(events.RegisterEvent, events, "GROUP_ROSTER_UPDATE")
end

function M:OnPlateAdded(unit, unitFrame)
	frameUnit[unitFrame] = unit
	HookHealthBar(unitFrame)
	Update(unit, unitFrame)
	if ns.GetUnitKind(unit) == "friendlyPlayer" then
		QueuePetRefresh() -- maybe the owner of a pet shown without one so far
	end
end

function M:OnPlateRemoved(_, unitFrame)
	-- unit frames are reused: give everything back before another unit takes this frame
	frameUnit[unitFrame] = nil
	leftToGame[unitFrame] = nil
	Release(unitFrame)
end

function M:OnUnitEvent(event, unit, unitFrame)
	if event == "UNIT_FACTION" or event == "UNIT_NAME_UPDATE" then
		Update(unit, unitFrame)
	end
end

function M:Apply(key)
	if key == nil or key:find("^health%.") then
		shortOptions = nil
		ns.ForEachPlate(function(_, unitFrame)
			local healthBar = HookHealthBar(unitFrame)
			if healthBar then
				RenderHealth(healthBar, healthBar:GetValue(), true)
			end
		end)
	end
	if key == nil or key:find("^plates%.") or key:find("^enemyText%.") or key:find("^look%.") then
		ns.ForEachPlate(Update)
	end
end
