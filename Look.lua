local _, ns = ...

-- Appearance ("Внешний вид"): size, opacity, offset (and for the small second line, its place) of every
-- part of a nameplate the addon can tune. Each part is an element; its settings are flat keys
-- "look.<element>.<scale|alpha|x|y|place>". Sizes and opacity are percents, offsets are pixels.
-- The modules draw the parts; this file only knows the elements and how to read their settings.

-- every element; the settings pages (Враг / Союзник / Питомец) pick theirs
ns.LOOK_ELEMENTS = {
	-- enemies
	"enemyName", "enemyGuild", "enemyHealth", "castText", "castTimer", "mine", "purge",
	"gameBuffs", "gameDebuffs", "gameCC", "quest",
	-- allies
	"friendName", "friendGuild", "friendHealth", "dispel", "friendGame",
	-- allies' pets
	"petName", "petOwner",
}

local HAS_PLACE = { enemyGuild = true, friendGuild = true, petOwner = true } -- the small line under / above the name
-- the enemy's two aura rows of the addon are one row on the plate: one shared offset
local OFFSET_ELEMENT = { mine = "addonAuras", purge = "addonAuras" }

-- offsets start at 0 (the game's place); written here instead of one line per element in Presets.lua
for _, element in ipairs(ns.LOOK_ELEMENTS) do
	for _, axis in ipairs({ "x", "y" }) do
		local key = "look." .. (OFFSET_ELEMENT[element] or element) .. "." .. axis
		if ns.BASE[key] == nil then
			ns.BASE[key] = 0
		end
	end
end

ns.LOOK_LIMITS = {
	scale = { 50, 200, 5 },
	alpha = { 0, 100, 5 },
	x = { -40, 40, 1 },
	y = { -40, 40, 1 },
}

function ns.LookHas(element, prop)
	if prop == "place" then
		return HAS_PLACE[element] == true
	end
	return ns.LOOK_LIMITS[prop] ~= nil
end

function ns.LookKey(element, prop)
	if (prop == "x" or prop == "y") and OFFSET_ELEMENT[element] then
		element = OFFSET_ELEMENT[element]
	end
	return "look." .. element .. "." .. prop
end

local function Clamp(value, prop)
	local limits = ns.LOOK_LIMITS[prop]
	value = tonumber(value) or 0
	return math.max(limits[1], math.min(limits[2], value))
end

-- size as a factor (1 = the game's own size)
function ns.LookScale(element)
	return Clamp(ns.Get(ns.LookKey(element, "scale")) or 100, "scale") / 100
end

-- opacity 0..1
function ns.LookAlpha(element)
	return Clamp(ns.Get(ns.LookKey(element, "alpha")) or 100, "alpha") / 100
end

-- offset in pixels: right, up
function ns.LookOffset(element)
	return Clamp(ns.Get(ns.LookKey(element, "x")) or 0, "x"), Clamp(ns.Get(ns.LookKey(element, "y")) or 0, "y")
end

-- "auto" | "above" | "below"
function ns.LookPlace(element)
	local place = ns.Get(ns.LookKey(element, "place"))
	if place == "above" or place == "below" then
		return place
	end
	return "auto"
end

-- name colour: "game" (as the game colours it) | "class" | "white" | "custom"
function ns.LookColorMode(element)
	return ns.Get("look." .. element .. ".color") or "game"
end

-- a colour stored as "AARRGGBB" (the settings colour swatch writes that) -> r, g, b
function ns.HexToRGB(hex)
	if type(hex) ~= "string" or not hex:match("^%x%x%x%x%x%x%x%x$") then
		return 1, 1, 1
	end
	return tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255
end

-- the element's own colour (custom name colour, guild colour)
function ns.LookRGB(element)
	return ns.HexToRGB(ns.Get("look." .. element .. ".rgb"))
end

-- every key of an element (its shared offset included)
function ns.LookKeys(element)
	local keys = {}
	for _, prop in ipairs({ "scale", "alpha", "x", "y", "place" }) do
		if ns.LookHas(element, prop) then
			table.insert(keys, ns.LookKey(element, prop))
		end
	end
	for _, prop in ipairs({ "color", "rgb" }) do
		local key = "look." .. element .. "." .. prop
		if ns.BASE[key] ~= nil then
			table.insert(keys, key)
		end
	end
	return keys
end

-- back to the preset's look (nil = every element)
function ns.ResetLook(element)
	local elements = element and { element } or ns.LOOK_ELEMENTS
	for _, el in ipairs(elements) do
		for _, key in ipairs(ns.LookKeys(el)) do
			ns.db.overrides[key] = nil
		end
	end
	ns.Refresh("look." .. (element or "all"))
end

------------------------------------------------------------------------
-- touching the game's regions only when a setting differs from the game
------------------------------------------------------------------------

local touchedScale = setmetatable({}, { __mode = "k" })
local touchedAlpha = setmetatable({}, { __mode = "k" })
local touchedTextScale = setmetatable({}, { __mode = "k" })

-- frame scale; 1 on a frame we never scaled leaves it alone
function ns.ApplyScale(region, scale)
	if not region or not region.SetScale then
		return
	end
	if scale == 1 and not touchedScale[region] then
		return
	end
	region:SetScale(scale)
	touchedScale[region] = scale ~= 1 or nil
end

function ns.ApplyAlpha(region, alpha)
	if not region or not region.SetAlpha then
		return
	end
	if alpha == 1 and not touchedAlpha[region] then
		return
	end
	region:SetAlpha(alpha)
	touchedAlpha[region] = alpha ~= 1 or nil
end

-- font size on top of the game's (the game sets text heights, never the text scale)
function ns.ApplyTextScale(text, scale)
	if not text or not text.SetTextScale then
		return
	end
	if scale == 1 and not touchedTextScale[text] then
		return
	end
	if touchedTextScale[text] ~= scale then
		text:SetTextScale(scale)
	end
	touchedTextScale[text] = scale ~= 1 and scale or nil
end

------------------------------------------------------------------------
-- offsets on the game's regions
------------------------------------------------------------------------

-- The game anchors its regions itself and may anchor them again at any time (a new layout, a style
-- change). The points the region has now are compared with the ones set here last: a point still as
-- we left it stands for its original; any other point is the game's new one. So offsets never pile up,
-- whatever the game re-anchors and whenever.
local placed = setmetatable({}, { __mode = "k" }) -- region -> { base = points, set = points }

local function ReadPoints(region)
	local ok, count = pcall(region.GetNumPoints, region)
	if not ok or type(count) ~= "number" or ns.IsSecret(count) then
		return nil
	end
	local points = {}
	for i = 1, count do
		local okPoint, point, relativeTo, relativePoint, x, y = pcall(region.GetPoint, region, i)
		if not okPoint or type(point) ~= "string" or ns.IsSecret(x) or ns.IsSecret(y) then
			return nil
		end
		points[i] = { point, relativeTo, relativePoint or point, tonumber(x) or 0, tonumber(y) or 0 }
	end
	return points
end

local function SamePoint(a, b)
	return a[1] == b[1] and rawequal(a[2], b[2]) and a[3] == b[3]
		and math.abs(a[4] - b[4]) < 0.01 and math.abs(a[5] - b[5]) < 0.01
end

local function SetPoints(region, points, dx, dy)
	local set = {}
	region:ClearAllPoints()
	for i, p in ipairs(points) do
		local q = { p[1], p[2], p[3], p[4] + dx, p[5] + dy }
		region:SetPoint(q[1], q[2], q[3], q[4], q[5])
		set[i] = q
	end
	return set
end

-- move a region of the game by dx, dy from where the game put it (0, 0 = the game's place)
function ns.PlaceRegion(region, dx, dy)
	if not region or not region.GetNumPoints then
		return
	end
	dx, dy = dx or 0, dy or 0
	local state = placed[region]
	if not state and dx == 0 and dy == 0 then
		return
	end
	local current = ReadPoints(region)
	if not current or #current == 0 then
		return
	end
	if state and state.dx == dx and state.dy == dy and #current == #state.set then
		local untouched = true
		for i, p in ipairs(current) do
			if not SamePoint(p, state.set[i]) then
				untouched = false
			end
		end
		if untouched then
			return -- already where it should be
		end
	end
	if state then
		local base = {}
		for i, p in ipairs(current) do
			local original
			for j, ours in ipairs(state.set) do
				if SamePoint(p, ours) then
					original = state.base[j]
				end
			end
			base[i] = original or p
		end
		state.base = base
	else
		state = { base = current }
		placed[region] = state
	end
	if dx == 0 and dy == 0 then
		SetPoints(region, state.base, 0, 0)
		placed[region] = nil
		return
	end
	state.set = SetPoints(region, state.base, dx, dy)
	state.dx, state.dy = dx, dy
end
