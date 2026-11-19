"""Load ForeverPlatesPlus into a mocked WoW API and check its behaviour.

usage: python3 -I run_tests.py <addon_dir> <harness_dir>
"""
import os
import re
import sys

from lupa import lua51

addon_dir, harness_dir = sys.argv[1], sys.argv[2]
toc = open(os.path.join(addon_dir, "ForeverPlatesPlus.toc"), encoding="utf-8").read()
files = [l.strip() for l in toc.splitlines() if l.strip().endswith(".lua")]

failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)
        print("FAIL:", msg)
    else:
        print("ok  :", msg)


def new_runtime(locale="ruRU", player_class="PRIEST", cvars_override=None):
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    L.execute(f'LOCALE = "{locale}"')
    if cvars_override is not None:
        L.execute(cvars_override)
    L.execute(open(os.path.join(harness_dir, "mock.lua"), encoding="utf-8").read())
    L.execute(f'UNITS.player = {{ class = "{player_class}", className = "x" }}')
    ns = L.table()
    for f in files:
        code = open(os.path.join(addon_dir, f), encoding="utf-8").read()
        chunk = L.execute("return function(code, name) local fn, err = loadstring(code, name); if not fn then error(err) end; return fn end")(code, f)
        chunk("ForeverPlatesPlus", ns)
    return L, ns


# ---------------------------------------------------------------- syntax
L0 = lua51.LuaRuntime()
for f in files:
    code = open(os.path.join(addon_dir, f), encoding="utf-8").read()
    ok = L0.execute("return function(c, n) local fn, err = loadstring(c, n); return fn ~= nil, err end")(code, f)
    check(ok[0], f"{f} compiles ({ok[1]})")

# globals written by the addon (should be only the saved variable, slash command and SlashCmdList entry)
for f in files:
    code = open(os.path.join(addon_dir, f), encoding="utf-8").read()
    for m in re.finditer(r"^(\w+)\s*=", code, re.M):
        name = m.group(1)
        check(name in ("ForeverPlatesPlusCharDB", "SLASH_FOREVERPLATESPLUS1", "SLASH_FOREVERPLATESPLUS2"), f"{f}: global assignment {name} is expected")

# ---------------------------------------------------------------- priest, full flow
L, ns = new_runtime()
G = L.globals()
G.FireEvent("ADDON_LOADED", "ForeverPlatesPlus")
G.FireEvent("PLAYER_LOGIN")
G.FireEvent("PLAYER_ENTERING_WORLD")
G.RunTimers()
check(len(G.ERRORS) == 0, "no errors after login: " + "; ".join(G.ERRORS[i] for i in range(1, len(G.ERRORS) + 1)))
check(ns.GetActivePreset() == "PRIEST", "auto preset resolves to PRIEST for a priest")
cv = G.CVARS
bit = lambda name, i: G.C_CVar.GetCVarBitfield(name, i)
check(bit("nameplateInfoDisplay", 1) and bit("nameplateInfoDisplay", 2), "health percent + value on")
check(all(bit("nameplateCastBarDisplay", i) for i in range(1, 6)), "all cast bar bits on")
check(bit("nameplateThreatDisplay", 1) and not bit("nameplateThreatDisplay", 2) and not bit("nameplateThreatDisplay", 3), "threat = progressive only")
check(bit("nameplateEnemyNpcAuraDisplay", 1) and not bit("nameplateEnemyNpcAuraDisplay", 2) and bit("nameplateEnemyNpcAuraDisplay", 3), "npc auras: buffs+cc, no game debuffs")
check(not bit("nameplateFriendlyPlayerAuraDisplay", 1) and not bit("nameplateFriendlyPlayerAuraDisplay", 2) and bit("nameplateFriendlyPlayerAuraDisplay", 3), "friendly auras: only loss of control")
check(bit("nameplateStackingTypes", 1) and not bit("nameplateStackingTypes", 2), "stack enemies only")
check(cv["nameplateShowAll"] == "1" and cv["nameplateShowOffscreen"] == "0" and cv["nameplateShowFriendlyNpcs"] == "0", "always show on, offscreen off, friendly npcs off")
check(abs(float(cv["nameplateOccludedAlphaMult"]) - 0.4) < 1e-6, "LOS fade 0.4")
check(cv["nameplateShowOnlyNameForFriendlyPlayerUnits"] == "1" and cv["nameplateUseClassColorForFriendlyPlayerUnitNames"] == "0", "default: allies everywhere as white names only")
ns.Set("look.friendName.color", "class")
check(cv["nameplateUseClassColorForFriendlyPlayerUnitNames"] == "1", "ally name colour 'class' = the game's own class colour (works in dungeons too)")
ns.Set("look.friendName.color", "white")
check(cv["nameplateUseClassColorForFriendlyPlayerUnitNames"] == "0" and G.SETTINGS["FOREVERPLATESPLUS_LOOK_FRIENDNAME_COLOR"].page == "Союзник", "colour choice on the Ally page")
ns.Set("native.friendNamesOnly", "never")
check(cv["nameplateShowOnlyNameForFriendlyPlayerUnits"] == "0", "'never': ally plates with health bars")
ns.Set("native.friendNamesOnly", "instance")
check(cv["nameplateShowOnlyNameForFriendlyPlayerUnits"] == "0", "'dungeons only', outside: bars")
check(cv["nameplateShowFriendlyPlayerMinions"] == "1" and cv["UnitNameFriendlyMinionName"] == "0", "ally pets: plates on (addon makes them a white name), big floating labels off")
G.IN_INSTANCE = True
G.FireEvent("PLAYER_ENTERING_WORLD"); G.RunTimers()
check(cv["nameplateShowOnlyNameForFriendlyPlayerUnits"] == "1", "in a dungeon: allies show only the name (the game forbids addons there)")
check(cv["nameplateShowFriendlyPlayerMinions"] == "0" and cv["UnitNameFriendlyMinionName"] == "0", "in a dungeon: pets get neither plates nor labels")
G.IN_INSTANCE = False
G.FireEvent("PLAYER_ENTERING_WORLD"); G.RunTimers()
check(cv["nameplateShowOnlyNameForFriendlyPlayerUnits"] == "0", "out of the dungeon: back to bars")
ns.Set("native.friendNamesOnly", "always")
check(cv["nameplateShowOnlyNameForFriendlyPlayerUnits"] == "1", "'everywhere' option")
ns.Set("plates.petNamesOnly", False)
check(cv["nameplateShowFriendlyPlayerMinions"] == "0" and cv["UnitNameFriendlyMinionName"] == "1", "pets option off: the game's own pet plates/labels back")
ns.Set("plates.petNamesOnly", True)
check(cv["nameplateShowFriendlyPlayerMinions"] == "1" and cv["UnitNameFriendlyMinionName"] == "0", "pets option on again")
ns.Set("native.friendNamesOnly", "always")
check(G.SETTINGS["FOREVERPLATESPLUS_NATIVE_FRIENDNAMESONLY"] is not None, "names-only dropdown in the panel")
sets_after_login = G.CVAR_SETS
G.FireEvent("PLAYER_ENTERING_WORLD"); G.RunTimers()
check(G.CVAR_SETS == sets_after_login, "re-applying unchanged settings writes no CVars")

# settings panel
S = G.SETTINGS
check(S.registered is not None, "settings category registered")
preset_setting = S["FOREVERPLATESPLUS_PROFILE_PRESET"]
check(preset_setting is not None and preset_setting.default == "auto", "preset dropdown default is auto")
check(S["FOREVERPLATESPLUS_NATIVE_LOSFADE"] is not None, "LOS slider shown when client has the CVar")

# nameplates
L.execute('UNITS.nameplate1 = { canAttack = true, isPlayer = false, isFriend = false, maxHealth = 1200 }')
L.execute('UNITS.nameplate2 = { canAttack = true, isPlayer = true, isFriend = false, maxHealth = 100 }')
L.execute('UNITS.nameplate3 = { canAttack = false, isPlayer = true, isFriend = true, maxHealth = 3000 }')
L.execute('UNITS.nameplate4 = { canAttack = SECRET_VALUE, isPlayer = false, isFriend = SECRET_VALUE, maxHealth = SECRET_VALUE }')
L.execute('UNITS.nameplate5 = { canAttack = true, isPlayer = false, isFriend = false, maxHealth = 900 }')
for i in range(1, 6):
    G.MakePlate(f"nameplate{i}")
L.execute("PLATES.nameplate5.forbidden = true")
for i in range(1, 6):
    G.FireEvent("NAME_PLATE_UNIT_ADDED", f"nameplate{i}")
G.RunTimers()
check(len(G.ERRORS) == 0, "no errors adding plates: " + "; ".join(G.ERRORS[i] for i in range(1, len(G.ERRORS) + 1)))

find = L.eval("""function(uf, kind)
  for _, f in ipairs(ALL_FRAMES) do
    if f.kind == kind and (f.parent == uf or (f.parent and f.parent.parent and f.parent.parent.parent == uf)) then return f end
  end
end""")
uf = lambda u: G.PLATES[u].UnitFrame

c1 = find(uf("nameplate1"), "AuraContainer")
check(c1 is not None and c1.enabled and c1.unit == "nameplate1", "enemy npc gets an aura container bound to its unit")
check(c1.groups["mine"].enabled and not c1.groups["dispel"].enabled, "enemy npc: my debuffs on, dispel off")
check(c1.groups["mine"].filter == "HARMFUL|PLAYER", "my debuffs filter")
b = c1.groups["mine"].buttons[1]
check(b.icon is not None and b.cooldown is not None and b.count is not None and b.durationText is not None, "aura button wired: icon, cooldown, count, timer")
check(b.width == 22 and b.height == 22, "my debuff icons 22px")

c3 = find(uf("nameplate3"), "AuraContainer")
check(c3 is not None and c3.groups["dispel"].enabled and not c3.groups["mine"].enabled, "friendly player: dispel row only")
check(c3.groups["dispel"].filter == "HARMFUL|RAID_PLAYER_DISPELLABLE", "dispel filter")

zones_lua = L.eval("""function(unit, role)
  local out = {}
  local hb = PLATES[unit].UnitFrame.HealthBarsContainer.healthBar
  for _, f in ipairs(ALL_FRAMES) do if f.kind == "StatusBar" and rawequal(f.parent, hb) and f.fpRole == role then table.insert(out, f) end end
  return out
end""")
zones = lambda unit, role="kill": list(zones_lua(unit, role).values())
ns.Set("killzone.targetOnly", False)  # the checks below look at several plates at once
check(len(zones("nameplate1")) == 0, "out of combat: no kill zone")
G.FireEvent("PLAYER_REGEN_DISABLED")
kz1 = zones("nameplate1")
check(len(kz1) == 1 and kz1[0].shown and kz1[0].max == 1200 and kz1[0].value == 412, "in combat: priest kill zone from SW:D description, 412 of 1200")
cz1 = zones("nameplate1", "crit")
check(len(cz1) == 1 and cz1[0].shown and cz1[0].max == 1200 and abs(cz1[0].value - 618) < 1e-6 and cz1[0].level < kz1[0].level, "crit zone behind it: 412 x 150% = 618")
kz2 = zones("nameplate2")
check(len(kz2) == 1 and not kz2[0].shown, "kill zone hidden on enemy player reported as 0..100")
kz3 = zones("nameplate3")
check(len(kz3) == 0, "no kill zone on allies")
kz4 = zones("nameplate4")
check(len(kz4) == 1 and kz4[0].shown and G.issecretvalue(kz4[0].max), "secret unit: zone still shown, secret max passed straight to the bar")
c5 = find(uf("nameplate5"), "AuraContainer")
check(c5 is None, "forbidden plate untouched")

# full names on allies (Thin layout: name centred over bar + level frame)
pts = L.eval("function(u) local out = {}; for i, p in ipairs(PLATES[u].UnitFrame.name.points) do out[i] = { p[1], p[2], p[3], p[4], p[5] } end; return out end")
points = lambda u: [list(p.values()) for p in pts(u).values()]
is_container = L.eval("function(u, rel) return rawequal(rel, PLATES[u].UnitFrame.HealthBarsContainer) end")
p3 = points("nameplate3")
check(len(p3) == 1 and p3[0][0] == "BOTTOM" and is_container("nameplate3", p3[0][1]) and p3[0][2] == "TOP" and p3[0][3] == 14 and p3[0][4] == 2, "ally name: one point, centred where the game centred it (bar + level frame), so it isn't cut")
check(len(points("nameplate1")) == 1, "enemy name freed too (full enemy names on by default)")
uf("nameplate3").UpdateAnchors(uf("nameplate3"))
p3 = points("nameplate3")
check(len(p3) == 1 and p3[0][0] == "BOTTOM", "after the game re-lays the plate out, the ally name is freed again")
ns.Set("plates.friendFullNames", False)
p3 = points("nameplate3")
check(len(p3) == 2 and p3[0][0] == "BOTTOMLEFT" and p3[1][0] == "RIGHT", "full names off: the game's points are back")
ns.Set("plates.friendFullNames", True)
check(len(points("nameplate3")) == 1, "full names on again")
check(G.SETTINGS["FOREVERPLATESPLUS_PLATES_FRIENDFULLNAMES"] is not None, "full names checkbox in the panel")
# guild names (off by default)
L.execute('UNITS.nameplate3.guild = "Орда навсегда"; UNITS.nameplate2.guild = "Альянс"')
G.FireEvent("UNIT_NAME_UPDATE", "nameplate3")
check(ns.GetSubtitleLine(uf("nameplate3")) is None or not ns.GetSubtitleLine(uf("nameplate3")).shown, "guild names off by default")
off_before = c3.points[1][5] if len(c3.points) else None
ns.Set("plates.guildFriends", True)
g3 = ns.GetSubtitleLine(uf("nameplate3"))
check(g3 is not None and g3.shown and g3.text == "<Орда навсегда>", "ally guild shown in angle brackets")
check(g3.points[1][1] == "BOTTOM" and g3.points[1][3] == "TOP", "plate with a health bar: guild above the name")
check(c3.points[1][5] > off_before, "aura row moved up to make room for the guild line")
check(ns.GetSubtitleLine(uf("nameplate2")) is None or not ns.GetSubtitleLine(uf("nameplate2")).shown, "allies only: no guild on enemies")
uf("nameplate3").showOnlyName = True
uf("nameplate3").UpdateAnchors(uf("nameplate3"))
check(g3.points[1][1] == "TOP" and g3.points[1][3] == "BOTTOM", "name-only ally: guild under the name")
check(c3.points[1][5] == off_before, "and the aura row back in place")
uf("nameplate3").showOnlyName = False
uf("nameplate3").UpdateAnchors(uf("nameplate3"))
ns.Set("plates.guildEnemies", True)
g2 = ns.GetSubtitleLine(uf("nameplate2"))
check(g2 is not None and g2.shown and g2.text == "<Альянс>", "enemy players' guilds turned on separately")
L.execute('UNITS.nameplate2.guild = SECRET_VALUE')
G.FireEvent("UNIT_NAME_UPDATE", "nameplate2")
check(not g2.shown, "secret guild: nothing shown")
ns.Set("plates.guildEnemies", True); ns.Set("plates.guildFriends", True)
ns.Set("look.friendGuild.place", "below")
check(g3.points[1][1] == "TOP" and g3.points[1][3] == "BOTTOM", "guild place 'under the name' even on a plate with a bar")
ns.Set("look.friendGuild.y", -3)
check(g3.points[1][5] == -1 - 3, "guild moved 3 px down")
ns.Set("look.friendGuild.place", "auto"); ns.Set("look.friendGuild.y", 0)
check(g3.points[1][1] == "BOTTOM", "auto place: above again")
ns.Set("plates.guildFriends", False); ns.Set("plates.guildEnemies", False)
check(not g3.shown and not g2.shown, "guild names off again")
check(S["FOREVERPLATESPLUS_PLATES_GUILDFRIENDS"].page == "Союзник" and S["FOREVERPLATESPLUS_PLATES_GUILDENEMIES"].page == "Враг", "guild options on the Ally and Enemy pages")
L.execute('UNITS.nameplate3.guild = nil; UNITS.nameplate2.guild = nil')

# name size
check(abs(uf("nameplate1").name.textScale - 1.15) < 1e-9 and abs(uf("nameplate3").name.textScale - 1.15) < 1e-9, "names 15% bigger by default, enemies and allies")
check(S["FOREVERPLATESPLUS_LOOK_ENEMYNAME_SCALE"].page == "Враг" and S["FOREVERPLATESPLUS_LOOK_FRIENDNAME_SCALE"].page == "Союзник", "name sizes on the Enemy and Ally pages")
ns.Set("look.enemyName.scale", 100)
check(uf("nameplate1").name.textScale == 1 and abs(uf("nameplate3").name.textScale - 1.15) < 1e-9, "enemy names at 100%: the game's size back, allies unchanged")
ns.Set("look.enemyName.scale", 115)

# ally name opacity
check(abs(uf("nameplate3").name.alpha - 0.55) < 1e-9, "ally name at 55% opacity by default")
check(uf("nameplate1").name.alpha is None, "enemy name untouched")
ns.Set("look.friendName.alpha", 100)
check(uf("nameplate3").name.alpha == 1, "100%: the game's own opacity back")
ns.Set("look.friendName.alpha", 55)
check(abs(uf("nameplate3").name.alpha - 0.55) < 1e-9, "back to 55%")
# ally pet: name only (white, transparent), like ally players
L.execute('UNITS.nameplate6 = { canAttack = false, isPlayer = false, isFriend = true, isPet = true, maxHealth = 500 }')
G.MakePlate("nameplate6")
L.execute("local uf = PLATES.nameplate6.UnitFrame; uf.CastBarsContainer = CreateFrame('Frame', nil, uf); uf.AurasFrame = CreateFrame('Frame', nil, uf)")
G.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate6"); G.RunTimers()
pet = uf("nameplate6")
check(pet.HealthBarsContainer.alpha == 0 and pet.CastBarsContainer.alpha == 0 and pet.AurasFrame.alpha == 0 and pet.PlayerLevelDiffFrame.alpha == 0, "ally pet: bar, cast bar, auras and level hidden")
check(list(pet.name.vertex.values()) == [1, 1, 1] and abs(pet.name.alpha - 0.55) < 1e-9, "ally pet with unknown owner: white name at 55%")
G.CompactUnitFrame_UpdateName(pet)
check(list(pet.name.vertex.values()) == [1, 1, 1], "the game's name update doesn't turn it green again")
ns.Set("plates.petNamesOnly", False)
check(pet.HealthBarsContainer.alpha == 1 and pet.AurasFrame.alpha == 1, "pets option off: plate parts back")
ns.Set("plates.petNamesOnly", True)
check(pet.HealthBarsContainer.alpha == 0, "on again")
check(uf("nameplate1").HealthBarsContainer.alpha is None, "enemy plate parts untouched")
G.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate6")
check(pet.HealthBarsContainer.alpha == 1 and pet.name.alpha == 1, "removed pet plate gets everything back before reuse")
check(G.SETTINGS["FOREVERPLATESPLUS_PLATES_PETNAMESONLY"] is not None, "pets checkbox in the panel")
# pet coloured by its owner's class
L.execute('UNITS.nameplate7 = { canAttack = false, isPlayer = false, isFriend = true, isPet = true, maxHealth = 500, name = "Костя", ownerLine = "Питомец Бу" }')
G.MakePlate("nameplate7"); G.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate7"); G.RunTimers()
pet7 = uf("nameplate7")
check(list(pet7.name.vertex.values()) == [1, 1, 1], "owner not around: pet name white")
L.execute('UNITS.party1 = { name = "Бу", class = "HUNTER", className = "Охотник", isPlayer = true }')
G.FireEvent("GROUP_ROSTER_UPDATE"); G.RunTimers()
check(list(pet7.name.vertex.values()) == [1, 1, 1], "pet colour follows friendly names: they are white, so the pet is white even with its owner known")
ns.Set("look.friendName.color", "class")
v = list(pet7.name.vertex.values())
check(abs(v[0] - 0.67) < 1e-9 and abs(v[1] - 0.83) < 1e-9, "friendly names in class colour: the pet in its owner's (hunter green)")
G.CompactUnitFrame_UpdateName(pet7)
v = list(pet7.name.vertex.values())
check(abs(v[0] - 0.67) < 1e-9, "the game's name update keeps the class colour")
# owner not in the group but with a plate nearby (names can have spaces in Forever)
L.execute('UNITS.party1 = nil; UNITS.nameplate8 = { canAttack = false, isPlayer = true, isFriend = true, name = "Caani Na", class = "WARLOCK", className = "Чернокнижник", maxHealth = 900 }')
G.MakePlate("nameplate8"); G.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate8"); G.RunTimers()
L.execute('UNITS.nameplate7.ownerLine = "Питомец Caani Na"')
G.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate7"); G.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate7"); G.RunTimers()
v = list(pet7.name.vertex.values())
check(abs(v[0] - 0.53) < 1e-9 and abs(v[2] - 0.93) < 1e-9, "owner found by the plate shown nearby: warlock purple")
# Russian tooltips decline the owner's name
L.execute('UNITS.nameplate8.name = "Артроз"; UNITS.nameplate7.ownerLine = "Питомец Артроза"')
G.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate7"); G.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate7"); G.RunTimers()
v = list(pet7.name.vertex.values())
check(abs(v[0] - 0.53) < 1e-9, "declined owner name (Артроза → Артроз) still matched")
sub7 = ns.GetSubtitleLine(pet7)
check(sub7 is not None and sub7.shown and sub7.text == "Артроз", "pet's owner written under its name")
check(sub7.points[1][1] == "TOP" and sub7.points[1][3] == "BOTTOM" and abs(sub7.textColor[1] - 0.53) < 1e-9, "owner line under the name, in the pet's colour")
L.execute('UNITS.nameplate8.surname = "Мьелнирович"')
G.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate7"); G.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate7"); G.RunTimers()
check(ns.GetSubtitleLine(pet7).text == "Артроз Мьелнирович", "owner with a surname (Forever): the owner line has the whole name")
L.execute('UNITS.nameplate8.surname = nil')
G.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate7"); G.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate7"); G.RunTimers()
pp7 = points("nameplate7")
check(len(pp7) == 1 and pp7[0][0] == "BOTTOM" and pp7[0][2] == "TOP" and pp7[0][3] == 0 and pp7[0][4] == 2 and pet7.name.justify == "CENTER", "pet name centred over its hidden bar (not over bar + level frame), like ally names")
ns.Set("plates.petOwner", False)
check(not sub7.shown, "owner line can be turned off")
ns.Set("plates.petOwner", True)
G.PRINTS = L.table()
L.execute("PLATES.mouseover = PLATES.nameplate7; UNITS.mouseover = UNITS.nameplate7")
G.SlashCmdList.FOREVERPLATESPLUS("debug")
dbg = " | ".join(G.PRINTS[i] for i in range(1, len(G.PRINTS) + 1))
check("pet=coloured owner=WARLOCK" in dbg, "/fpl debug shows the pet's owner class: " + dbg[-80:])
L.execute("PLATES.mouseover = nil; UNITS.mouseover = nil")
G.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate8")
ns.Set("look.petName.color", "white")
check(list(pet7.name.vertex.values()) == [1, 1, 1], "pet colour white")
ns.Set("look.petName.color", "custom"); ns.Set("look.petName.rgb", "ff336699")
v = list(pet7.name.vertex.values())
check(abs(v[0] - 0x33 / 255) < 1e-9 and abs(v[2] - 0x99 / 255) < 1e-9, "pet colour of your own")
ns.Set("look.petName.color", "friend")
ns.Set("look.friendName.color", "white")
L.execute('UNITS.party1 = nil')
G.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate7")
check(len(points("nameplate7")) == 2, "removed pet plate: the game's name points back")
check(G.SETTINGS["FOREVERPLATESPLUS_LOOK_FRIENDNAME_ALPHA"] is not None and G.SETTINGS["FOREVERPLATESPLUS_LOOK_PETNAME_ALPHA"] is not None, "opacity sliders for allies and pets")
# "Change friendly nameplates" off: friendly plates and the game's options for them are the game's
ns.Set("plates.guildFriends", True)
L.execute('UNITS.nameplate3.guild = "Орда навсегда"')
G.FireEvent("UNIT_NAME_UPDATE", "nameplate3"); G.RunTimers()
u3 = uf("nameplate3")
check(ns.GetSubtitleLine(u3).shown and len(points("nameplate3")) == 1, "ally: our guild line and name layout")
ns.Set("plates.friends", False); G.RunTimers()
check(not ns.GetSubtitleLine(u3).shown and len(points("nameplate3")) == 2 and abs(u3.name.alpha - 1) < 1e-9, "friendly plates off: the ally's name and guild line are the game's again")
check(cv["nameplateShowOnlyNameForFriendlyPlayerUnits"] == G.C_CVar.GetCVarDefault("nameplateShowOnlyNameForFriendlyPlayerUnits")
      and cv["nameplateUseClassColorForFriendlyPlayerUnitNames"] == G.C_CVar.GetCVarDefault("nameplateUseClassColorForFriendlyPlayerUnitNames"),
      "friendly plates off: the game's options for them back to the game's defaults")
check(ns.IsPartOn("ally", "name") is False and ns.IsPartOn("ally", "plate") is True, "sketch: ally parts drawn as off, the whole plate stays clickable")
check(G.SETTINGS["FOREVERPLATESPLUS_PLATES_FRIENDS"] is not None, "friendly switch in the panel")
ns.Set("plates.friends", True); G.RunTimers()
check(ns.GetSubtitleLine(u3).shown and len(points("nameplate3")) == 1, "on again: the addon's look again")
ns.Set("plates.guildFriends", False)
L.execute('UNITS.nameplate3.guild = nil')
G.FireEvent("UNIT_NAME_UPDATE", "nameplate3"); G.RunTimers()
# an enemy player's pet: the owner's class colour with "Class color (players and their pets)"
L.execute('UNITS.nameplate11 = { canAttack = true, isPlayer = true, isFriend = false, name = "Вражина", class = "HUNTER", maxHealth = 900 }')
L.execute('UNITS.nameplate12 = { canAttack = true, isPlayer = false, isFriend = false, isPet = true, name = "Волк", ownerLine = "Питомец Вражины", maxHealth = 400 }')
for n in ("nameplate11", "nameplate12"):
    G.MakePlate(n); G.FireEvent("NAME_PLATE_UNIT_ADDED", n)
G.RunTimers()
ns.Set("look.enemyName.color", "class")
v = list(uf("nameplate12").name.vertex.values())
check(len(v) == 3 and abs(v[0] - 0.67) < 1e-9 and abs(v[1] - 0.83) < 1e-9, "enemy pet in its owner's class colour (hunter green)")
ns.Set("look.enemyName.color", "game")
for n in ("nameplate11", "nameplate12"):
    G.FireEvent("NAME_PLATE_UNIT_REMOVED", n)
G.RunTimers()
# the game switches the ally to name-only and lays it out again
uf("nameplate3").showOnlyName = True
uf("nameplate3").UpdateAnchors(uf("nameplate3"))
p3 = points("nameplate3")
check(len(p3) == 1 and p3[0][0] == "BOTTOM" and p3[0][2] == "TOP" and p3[0][3] == 0 and p3[0][4] == 2, "name-only ally: one point, centred above, not cut")
L.execute("PLATES.mouseover = PLATES.nameplate3; UNITS.mouseover = UNITS.nameplate3")
G.PRINTS = L.table()
G.SlashCmdList.FOREVERPLATESPLUS("debug")
dbg = " | ".join(G.PRINTS[i] for i in range(1, len(G.PRINTS) + 1))
check("onlyName=true" in dbg and "ours=true" in dbg and "[BOTTOM bars TOP 0 2]" in dbg, "/fpl debug reports the name state: " + dbg[:160])
L.execute("PLATES.mouseover = nil; UNITS.mouseover = nil")
uf("nameplate3").showOnlyName = False
uf("nameplate3").UpdateAnchors(uf("nameplate3"))

# health number format (game update -> our format)
hb1 = uf("nameplate1").HealthBarsContainer.healthBar
hb1.UpdateTextStringWithValues(hb1, hb1.TextString, 12345)
check(hb1.RightText.text == "12.3к" and hb1.LeftText.text == "100%", "default: thousands with one decimal and 'к' (12345 -> 12.3к), percent untouched")
hb1.UpdateTextStringWithValues(hb1, hb1.TextString, 1234567)
check(hb1.RightText.text == "1.2м", "millions -> 1.2м")
hb1.UpdateTextStringWithValues(hb1, hb1.TextString, 850)
check(hb1.RightText.text == "850", "below a thousand: plain number")
hb1.value = 12345
ns.Set("health.decimals", 0)
check(hb1.RightText.text == "12к", "decimals 0 applied right away: 12к")
ns.Set("health.decimals", 2)
check(hb1.RightText.text == "12.34к", "decimals 2: 12.34к")
ns.Set("health.format", "full")
check(hb1.RightText.text == "12 345", "full format: 12 345")
ns.Set("health.format", "game")
check(hb1.RightText.text == "12.35K", "game format: the game's own text back")
hb1.UpdateTextStringWithValues(hb1, hb1.TextString, 23456)
check(hb1.RightText.text == "23.46K", "game format: game updates left alone")
ns.Set("health.format", "short"); ns.Set("health.decimals", 1)
hb1.UpdateTextStringWithValues(hb1, hb1.TextString, G.SECRET_VALUE)
check(G.issecretvalue(hb1.RightText.text), "secret health: formatted by the game function, passed straight to the text")
hb1.showPercentage = False; hb1.TextString.shown = True
hb1.UpdateTextStringWithValues(hb1, hb1.TextString, 5432)
check(hb1.TextString.text == "5.4к", "number only (no percent): main text formatted")
hb1.showPercentage = True
check(G.SETTINGS["FOREVERPLATESPLUS_HEALTH_FORMAT"] is not None and G.SETTINGS["FOREVERPLATESPLUS_HEALTH_DECIMALS"] is not None, "format settings in the panel")
check(G.ABBREV_CONFIGS > 0, "abbreviation config accepted (valid breakpoints)")

# early aggro warning
thr = L.eval("""function(unit)
  local uf = PLATES[unit].UnitFrame
  for _, f in ipairs(ALL_FRAMES) do if f.fpRole == "threat" and rawequal(f.parent, uf) then return f end end
end""")
L.execute("THREAT.nameplate1 = 80")
G.FireEvent("UNIT_THREAT_LIST_UPDATE", "nameplate1")
check(thr("nameplate1") is None, "solo: no aggro warning (like the game)")
G.IN_GROUP = True
G.FireEvent("GROUP_ROSTER_UPDATE")
t1 = thr("nameplate1")
check(t1 is not None and t1.shown and t1.min == 70 and t1.max == 100 and t1.value == 80, "in a group: glow range 70..100, threat 80% -> a third lit")
L.execute("THREAT.nameplate1 = SECRET_VALUE")
G.FireEvent("UNIT_THREAT_LIST_UPDATE", "nameplate1")
check(G.issecretvalue(t1.value) and t1.shown, "secret threat goes straight to the bar")
L.execute("THREAT.nameplate1 = nil")
G.FireEvent("UNIT_THREAT_LIST_UPDATE", "nameplate1")
check(not t1.shown, "not on the mob's threat list: hidden")
L.execute("THREAT.nameplate1 = 90; THREAT.nameplate3 = 90")
G.FireEvent("UNIT_THREAT_LIST_UPDATE", "nameplate1"); G.FireEvent("UNIT_THREAT_LIST_UPDATE", "nameplate3")
check(t1.shown and thr("nameplate3") is None, "allies never get it")
ns.Set("threat.warnFrom", 50)
check(t1.min == 50, "threshold setting applied")
G.PLAYER_ROLE = "TANK"; G.FireEvent("PLAYER_ROLES_ASSIGNED")
check(not t1.shown, "tank: no early warning")
G.PLAYER_ROLE = "HEALER"; G.FireEvent("PLAYER_ROLES_ASSIGNED")
check(t1.shown, "healer: shown")
ns.Set("threat.warn", False)
check(not t1.shown, "can be turned off")
ns.Set("threat.warn", True); ns.Set("threat.warnFrom", 70)
G.IN_GROUP = False; G.FireEvent("GROUP_ROSTER_UPDATE")
check(G.SETTINGS["FOREVERPLATESPLUS_THREAT_WARN"] is not None and G.SETTINGS["FOREVERPLATESPLUS_THREAT_WARNFROM"] is not None, "aggro warning settings in the panel")

# ---- settings pages
first = G.SETTINGS.layout.inits[1]
check(first.header == ns.L.ABOUT_PAGE and first.tooltip == ns.L.ABOUT_MAIN, "no description template: page text goes into a header tooltip")
pages = list(G.SETTINGS.pages.values())
check(pages == ["Враг", "Союзник", "Питомец союзника", "Фреймы"], "settings split by nameplate, then frames: " + ", ".join(pages))
S = G.SETTINGS
check(S["FOREVERPLATESPLUS_PROFILE_PRESET"].page == "ForeverPlatesPlus" and S["FOREVERPLATESPLUS_NATIVE_MANAGE"].page == "ForeverPlatesPlus" and S["FOREVERPLATESPLUS_NATIVE_ALWAYSSHOW"].page == "ForeverPlatesPlus", "preset, general and all-plates options on the main page")
for k in ("ENEMYTEXT_IDLE", "INFO_QUEST", "CAST_TIMER", "CAST_INTERRUPTREADY", "AURAS_PURGE", "NATIVE_NPCBUFFS", "FADE_RANGE", "NATIVE_STACKENEMIES", "THREAT_WARN", "KILLZONE_ENABLED", "NATIVE_MAXDISTANCE"):
    check(S["FOREVERPLATESPLUS_" + k].page == "Враг", f"{k} on the Enemy page")
check(S["FOREVERPLATESPLUS_NATIVE_FRIENDNAMESONLY"].page == "Союзник" and S["FOREVERPLATESPLUS_AURAS_DISPEL"].page == "Союзник", "ally look and dispel row on the Ally page")
check(S["FOREVERPLATESPLUS_PLATES_PETNAMESONLY"].page == "Питомец союзника" and S["FOREVERPLATESPLUS_PLATES_PETOWNER"].page == "Питомец союзника", "pets on their own page")
check(S["FOREVERPLATESPLUS_NATIVE_HEALTHVALUE"] is None and S["FOREVERPLATESPLUS_NATIVE_FRIENDCLASSCOLOR"] is None, "doubled options gone: health number switches (chosen per state instead), class colour checkbox (a colour choice instead)")

# ---- execute mark: only on the target, drawn as a line by default
ns.Set("killzone.targetOnly", True)
check(not kz1[0].shown, "execute mark only on the target: hidden on a mob you haven't targeted")
L.execute("PLATES.target = PLATES.nameplate1")
G.FireEvent("PLAYER_TARGET_CHANGED")
check(kz1[0].shown, "targeted: mark shown")
check(kz1[0].barColor[4] == 0 and cz1[0].barColor[4] == 0, "line style: no tint, only the marks")
ns.Set("killzone.style", "zone")
check(abs(kz1[0].barColor[4] - 0.85 * 0.35) < 1e-9, "zone style: part of the bar tinted")
edge = kz1[0].fpEdge
check(abs(edge.color[1] - 0x14 / 255) < 1e-9 and abs(edge.color[4] - 0.85) < 1e-9 and edge.width == 1, "the mark: a thin dark line by default (not a bright purple stripe)")
ns.Set("killzone.rgb", "ffffffff"); ns.Set("killzone.width", 2); ns.Set("killzone.alpha", 50)
check(edge.color[1] == 1 and abs(edge.color[4] - 0.5) < 1e-9 and edge.width == 2 and abs(cz1[0].fpEdge.color[4] - 0.25) < 1e-9, "its colour, width and opacity follow the settings (crit line half as visible)")
ns.Set("killzone.rgb", "ff141414"); ns.Set("killzone.width", 1); ns.Set("killzone.alpha", 85)
ns.Set("killzone.style", "line")
L.execute("PLATES.target = nil")
G.FireEvent("PLAYER_TARGET_CHANGED")
check(not kz1[0].shown, "target dropped: mark hidden")
ns.Set("killzone.targetOnly", False)

# ---- nameplate distance (a game option)
check(cv["nameplateMaxDistance"] == "41" and S["FOREVERPLATESPLUS_NATIVE_MAXDISTANCE"].get() == 41, "distance untouched until changed; panel shows the game's value")
S["FOREVERPLATESPLUS_NATIVE_MAXDISTANCE"].set(30)
check(cv["nameplateMaxDistance"] == "30", "distance slider writes the game option")

# ---- game options left to the game until changed
check(cv["nameplateShowEnemyMinions"] == "1" and cv["nameplateShowEnemyMinus"] == "0" and cv["nameplateSimplifiedTypes"] == "3", "minion/minor options untouched until changed")
check(S["FOREVERPLATESPLUS_NATIVE_ENEMYMINIONS"].get() is True and S["FOREVERPLATESPLUS_NATIVE_ENEMYMINUS"].get() is False and S["FOREVERPLATESPLUS_NATIVE_SMALLMINUS"].get() is True, "panel shows the game's current values")
S["FOREVERPLATESPLUS_NATIVE_ENEMYMINUS"].set(True)
S["FOREVERPLATESPLUS_NATIVE_SMALLMINIONS"].set(False)
check(cv["nameplateShowEnemyMinus"] == "1" and cv["nameplateSimplifiedTypes"] == "2", "changing them writes the game options")

# ---- purgeable enemy buffs row
check(c1.groups["purge"].enabled and c1.groups["purge"].filter == "HELPFUL|RAID_PLAYER_DISPELLABLE", "enemy: purgeable buffs row on")
check(not c3.groups["purge"].enabled, "ally: no purge row")
check(c1.groups["purge"].options["layout"]["layoutIndex"] < c1.groups["mine"].options["layout"]["layoutIndex"], "purge row before my debuffs")
ns.Set("auras.purge", False)
check(not c1.groups["purge"].enabled, "purge row can be turned off")
ns.Set("auras.purge", True)

# ---- cast bar extras
castbar = lambda u: uf(u).CastBarsContainer.castBar
holder_of = L.eval("""function(unit)
  local cb = PLATES[unit].UnitFrame.CastBarsContainer.castBar
  for _, f in ipairs(ALL_FRAMES) do if rawequal(f.parent, cb) and f.extra then return f end end
end""")
G.KNOWN_SPELLS[15487] = True
G.FireEvent("SPELLS_CHANGED")
check(G.PRINTS is not None and ns.GetInterruptSpell() == 15487, "priest with Silence: interrupt found")
h1 = holder_of("nameplate1")
check(h1 is not None, "enemy cast bar gets extras")
check(holder_of("nameplate3") is None, "ally cast bar: nothing added")
cb = castbar("nameplate1")
cb.casting = True; cb.channeling = False; cb.value = 0.4; cb.maxValue = 1.5
h1.scripts["OnUpdate"](h1, 0.1)
ex = h1.extra
check(ex.timer.shown and ex.timer.text == "1.1", "cast timer: 1.1 s left")
cb.casting = False; cb.channeling = True; cb.value = 2.0; cb.maxValue = 3.0
h1.scripts["OnUpdate"](h1, 0.1)
check(ex.timer.text == "2.0", "channel timer counts down")
cb.value = G.SECRET_VALUE
h1.scripts["OnUpdate"](h1, 0.1)
check(not ex.timer.shown, "secret cast timing: no timer")
cb.channeling = False; cb.casting = True; cb.value = 0.5; cb.maxValue = 2.0
L.execute("CASTS.nameplate1 = { notInterruptible = false }")
G.COOLDOWNS[15487] = True
h1.scripts["OnUpdate"](h1, 0.1)
check(ex.interruptLayer.shown and ex.interruptLayer.alpha == 1 and abs(ex.grey.alpha - 0.55) < 1e-9, "interrupt on cooldown: interruptible cast greyed")
G.COOLDOWNS[15487] = False
h1.scripts["OnUpdate"](h1, 0.1)
check(ex.grey.alpha == 0, "interrupt ready: no grey")
L.execute("CASTS.nameplate1 = { notInterruptible = true }")
G.COOLDOWNS[15487] = True
h1.scripts["OnUpdate"](h1, 0.1)
check(ex.interruptLayer.alpha == 0, "cast that can't be interrupted: never greyed")
L.execute("CASTS.nameplate1 = { notInterruptible = SECRET_VALUE }")
G.COOLDOWNS[15487] = G.SECRET_VALUE
h1.scripts["OnUpdate"](h1, 0.1)
check(ex.interruptLayer.alphaFromSecret and ex.grey.alphaFromSecret, "secret cast/cooldown flags go straight to the game")
L.execute("CASTS.nameplate1 = nil")
h1.scripts["OnUpdate"](h1, 0.1)
check(not ex.interruptLayer.shown, "no cast: no grey layer")
ns.Set("cast.timer", False)
cb.value = 0.5
h1.scripts["OnUpdate"](h1, 0.1)
check(not ex.timer.shown, "timer can be turned off")
ns.Set("cast.timer", True)
G.COOLDOWNS[15487] = None
G.KNOWN_SPELLS[15487] = None
G.FireEvent("SPELLS_CHANGED")

# ---- fading: out of range / not the target
check(ns.GetRangeSpell() == 585, "priest range check uses Smite")
L.execute("UNITS.nameplate1.inRange = false; UNITS.nameplate2.inRange = true; UNITS.nameplate3.inRange = false")
fader = [f for f in G.ALL_FRAMES.values() if f.events["PLAYER_TARGET_CHANGED"] and f.scripts["OnUpdate"] is not None and f.events["SPELLS_CHANGED"]]
check(len(fader) == 1, "range watch running")
fader[0].scripts["OnUpdate"](fader[0], 0.25)
check(abs(uf("nameplate1").alpha - 0.5) < 1e-9 and uf("nameplate2").alpha is None, "enemy out of range faded to 50%, in range untouched")
check(uf("nameplate3").alpha is None, "allies never faded")
L.execute("UNITS.nameplate1.inRange = true")
fader[0].scripts["OnUpdate"](fader[0], 0.25)
check(uf("nameplate1").alpha == 1, "back in range: full opacity")
ns.Set("fade.nonTarget", True)
L.execute("PLATES.target = PLATES.nameplate2")
G.FireEvent("PLAYER_TARGET_CHANGED")
check(abs(uf("nameplate1").alpha - 0.6) < 1e-9 and uf("nameplate2").alpha in (None, 1), "with a target, other enemies faded to 60%")
L.execute("PLATES.target = nil")
G.FireEvent("PLAYER_TARGET_CHANGED")
check(uf("nameplate1").alpha == 1, "no target: nothing faded")
ns.Set("fade.nonTarget", False)
ns.Set("fade.range", False)
check(fader[0].scripts["OnUpdate"] is None, "range watch stops when turned off")
ns.Set("fade.range", True)
L.execute("UNITS.nameplate1.inRange = nil; UNITS.nameplate2.inRange = nil; UNITS.nameplate3.inRange = nil")

# ---- quest marker
qmark = L.eval("""function(unit)
  local uf = PLATES[unit].UnitFrame
  for _, f in ipairs(ALL_FRAMES) do if rawequal(f.parent, uf) and f.width == 14 and f.height == 14 then return f end end
end""")
L.execute("UNITS.nameplate1.quest = true; UNITS.nameplate2.quest = true")
G.FireEvent("QUEST_LOG_UPDATE"); G.FireEvent("QUEST_LOG_UPDATE"); G.RunTimers()
q1 = qmark("nameplate1")
check(q1 is not None and q1.shown, "quest mob gets the marker")
check(qmark("nameplate2") is None, "players never get it")
sameq = L.eval("function(a, b) return rawequal(a, b) end")
bl1 = uf("nameplate1").AurasFrame.BuffListFrame
check(sameq(q1.points[1][2], uf("nameplate1").ClassificationFrame) and q1.points[1][4] == -3, "the marker joins the game's line of icons left of the bar")
check(sameq(bl1.points[1][2], q1) and bl1.points[1][4] == -3, "the game's buffs line up after the marker")
L.execute("UNITS.nameplate1.quest = false")
G.FireEvent("QUEST_REMOVED"); G.RunTimers()
check(not q1.shown, "quest done: marker gone")
check(sameq(bl1.points[1][2], uf("nameplate1").ClassificationFrame) and bl1.points[1][4] == -5, "marker gone: the game's buffs move up to where the game puts them, no gap")
L.execute("UNITS.nameplate1.quest = true")
ns.Set("info.quest", False)
check(not q1.shown, "marker can be turned off")
ns.Set("info.quest", True)
check(q1.shown, "and on again")
L.execute("UNITS.nameplate1.quest = nil; UNITS.nameplate2.quest = nil")
G.FireEvent("QUEST_LOG_UPDATE"); G.RunTimers()

# friendly health text
texts = lambda u: [uf(u).HealthBarsContainer.healthBar.Text, uf(u).HealthBarsContainer.healthBar.LeftText, uf(u).HealthBarsContainer.healthBar.RightText]
check(all(t.alpha == 0 for t in texts("nameplate3")), "health text hidden on friendly player")
check(all(t.width == 1 and t.wordWrap is False for t in texts("nameplate3")), "hidden friendly texts take no width, so the name gets the whole bar")
check(all(t.alpha == 0 and t.width == 1 for t in texts("nameplate1")), "enemy, normally: no numbers (level and name only)")
# target / mouseover
hbt = lambda u: uf(u).HealthBarsContainer.healthBar
L.execute("PLATES.target = PLATES.nameplate1")
G.FireEvent("PLAYER_TARGET_CHANGED")
check(all(t.alpha == 1 and t.width == 0 for t in texts("nameplate1")), "enemy in target: number and percent shown")
L.execute("PLATES.mouseover = PLATES.nameplate2")
G.FireEvent("UPDATE_MOUSEOVER_UNIT")
check(hbt("nameplate2").RightText.alpha == 1 and hbt("nameplate2").LeftText.alpha == 0, "enemy under the cursor: number only")
watcher = [f for f in G.ALL_FRAMES.values() if f.events["UPDATE_MOUSEOVER_UNIT"]][0]
check(watcher.scripts["OnUpdate"] is not None, "cursor watch runs while hovering")
L.execute("PLATES.mouseover = nil")
watcher.scripts["OnUpdate"](watcher, 0.05)
check(hbt("nameplate2").RightText.alpha == 1, "short hover gap ignored (checks every 0.1 s)")
watcher.scripts["OnUpdate"](watcher, 0.06)
check(hbt("nameplate2").RightText.alpha == 0 and watcher.scripts["OnUpdate"] is None, "cursor left: back to normal, watch stopped")
ns.Set("enemyText.idle", "percent")
check(hbt("nameplate2").LeftText.alpha == 1 and hbt("nameplate2").RightText.alpha == 0, "normal state set to percent: only percent")
ns.Set("enemyText.idle", "none")
L.execute("PLATES.target = nil")
G.FireEvent("PLAYER_TARGET_CHANGED")
check(all(t.alpha == 0 for t in texts("nameplate1")), "target cleared: numbers hidden again")
for k in ("FOREVERPLATESPLUS_ENEMYTEXT_IDLE", "FOREVERPLATESPLUS_ENEMYTEXT_MOUSEOVER", "FOREVERPLATESPLUS_ENEMYTEXT_TARGET", "FOREVERPLATESPLUS_PLATES_ENEMYFULLNAMES"):
    check(G.SETTINGS[k] is not None, f"setting {k} in the panel")
ns.Set("plates.friendHealth", "both")
check(all(t.alpha == 1 and t.width == 0 and t.wordWrap is True for t in texts("nameplate3")), "ally numbers 'both': health text on allies again (auto width, wrap restored)")
ns.Set("plates.friendHealth", "percent")
check(hbt("nameplate3").LeftText.alpha == 1 and hbt("nameplate3").RightText.alpha == 0, "ally numbers: percent only")
ns.Set("plates.friendHealth", "none")
check(all(t.alpha == 0 for t in texts("nameplate3")), "ally numbers off again")

# minimap button
mb = [f for f in G.ALL_FRAMES.values() if f.name == "ForeverPlatesPlusMinimapButton"]
check(len(mb) == 1 and mb[0].shown, "minimap button created and shown")
mb = mb[0]
mb.scripts["OnClick"](mb)
check(G.SETTINGS.opened == 42, "minimap click opens the settings")
mb.scripts["OnDragStart"](mb); mb.scripts["OnUpdate"](mb); mb.scripts["OnDragStop"](mb)
check(abs(ns.db.minimapAngle - 90) < 1e-6 and mb.scripts["OnUpdate"] is None, "dragging stores the angle (cursor straight above = 90)")
ns.Set("ui.minimap", False)
check(not mb.shown, "minimap button can be hidden")
ns.Set("ui.minimap", True)
check(mb.shown, "and shown again")
G.SETTINGS.opened = None
G.ForeverPlatesPlus_OnAddonCompartmentClick()
check(G.SETTINGS.opened == 42, "addon compartment entry opens the settings")
check(G.SETTINGS["FOREVERPLATESPLUS_PLATES_FRIENDHEALTH"] is not None and G.SETTINGS["FOREVERPLATESPLUS_UI_MINIMAP"] is not None, "ally numbers and minimap in the settings panel")

# changing settings
ns.Set("look.mine.scale", 150)
check(b.width == 33, "icon size change (150% of 22 px) restyles existing buttons")
check(c1.groups["mine"].layout.elementWidth == 33, "icon size change updates group layout")
ns.Set("auras.mineTimer", False)
check(b.durationText is None, "timer off clears duration text")
ns.Set("killzone.value", 500)
check(kz1[0].value == 412, "in spell mode the manual threshold is only a fallback")
ns.Set("killzone.spellBonus", 10)
check(kz1[0].value == 453, "spell damage correction +10% -> 453")
ns.Set("killzone.spellBonus", 0)
L.execute('SPELLS[32379].desc = "Слово, исполненное темной силы, наносит цели от 1 234 до 1 400 ед. урона."')
G.FireEvent("UNIT_AURA", "player"); G.FireEvent("PLAYER_EQUIPMENT_CHANGED"); G.RunTimers()
check(kz1[0].value == 1234, "spell power change: description re-read (minimum of the range, thousands separator)")
L.execute('SPELLS[32379].desc = ""')
G.FireEvent("SPELLS_CHANGED"); G.RunTimers()
check(kz1[0].value == 500 and G.SPELL_LOAD_REQUESTS > 0, "description not loaded: manual threshold as fallback, spell data requested")
check("не прочиталось" in ns.KillZoneSummary(), "summary says the description wasn't read")
L.execute('SPELLS[32379].desc = "Наносит 412 ед. урона."')
G.FireEvent("SPELL_TEXT_UPDATE", 32379); G.RunTimers()
check(kz1[0].value == 412, "SPELL_TEXT_UPDATE brings the description value back")
L.execute('SPELLS[48158] = { name = "Слово Тьмы: Смерть", desc = "Наносит 520 ед. урона." }; SPELL_BY_NAME["Слово Тьмы: Смерть"] = 48158')
G.FireEvent("SPELLS_CHANGED"); G.RunTimers()
check(kz1[0].value == 520, "uses the player's own rank of the spell (looked up by name)")
L.execute('SPELL_BY_NAME["Слово Тьмы: Смерть"] = nil; SPELLS[48158] = nil')
G.FireEvent("SPELLS_CHANGED"); G.RunTimers()
G.PRINTS = L.table()
G.SlashCmdList.FOREVERPLATESPLUS("status")
check(any("412" in G.PRINTS[i] and "Слово Тьмы: Смерть" in G.PRINTS[i] and "618" in G.PRINTS[i] for i in range(1, len(G.PRINTS) + 1)), "/fpl status shows the threshold, its source and the crit value")
ns.Set("killzone.critMult", 200)
check(cz1[0].value == 824, "crit damage 200% -> 824")
ns.Set("killzone.crit", False)
check(not cz1[0].shown and kz1[0].shown, "crit zone can be turned off")
ns.Set("killzone.crit", True); ns.Set("killzone.critMult", 150)
pn = ns.ParseSpellNumber
check(pn("inflicts 1,234 to 1,400 Shadow damage") == 1234 and pn("наносит от 450 до 522 ед.") == 450 and pn("$s1 ед. урона") is None and pn("12\u00a0345 ед.") == 12345 and pn("Наносит 350. Затем 12") == 350, "description number parsing")
G.SlashCmdList.FOREVERPLATESPLUS("kz 420")
check(kz1[0].value == 420 and ns.Get("killzone.value") == 420, "/fpl kz 420")
check(preset_setting.notified > 0, "settings panel notified after changes")

# combat deferral
G.IN_COMBAT = True
ns.Set("native.stackFriends", True)
check(not bit("nameplateStackingTypes", 2), "no CVar writes in combat")
G.IN_COMBAT = False
G.FireEvent("PLAYER_REGEN_ENABLED")
check(bit("nameplateStackingTypes", 2), "deferred CVar write runs after combat")
check(not kz1[0].shown and not cz1[0].shown, "combat ended: kill and crit zones hidden")
ns.Set("killzone.combatOnly", False)
check(kz1[0].shown, "'only in combat' off: zone shown out of combat")
ns.Set("killzone.combatOnly", True)
check(not kz1[0].shown, "'only in combat' on again: hidden")
G.FireEvent("PLAYER_REGEN_DISABLED")
check(kz1[0].shown, "next fight: shown again")
check(len(G.ERRORS) == 0, "no errors through setting changes")

# ---- pages by nameplate: pick a part, only its settings are listed
pe = S["FOREVERPLATESPLUS_UI_PART_ENEMY"]
shows = lambda var: S[var].init.ShouldShow(S[var].init)
check(pe.page == "Враг" and [d.value for d in pe.getOptions().values()][:4] == ["plate", "name", "guild", "health"], "part list on the Enemy page")
pe.set("plate")
check(shows("FOREVERPLATESPLUS_NATIVE_STACKENEMIES") and not shows("FOREVERPLATESPLUS_LOOK_ENEMYNAME_SCALE") and not shows("FOREVERPLATESPLUS_INFO_QUEST"), "'whole nameplate': only its options listed")
pe.set("quest")
check(shows("FOREVERPLATESPLUS_INFO_QUEST") and shows("FOREVERPLATESPLUS_LOOK_QUEST_SCALE") and not shows("FOREVERPLATESPLUS_NATIVE_STACKENEMIES"), "quest marker part: show it or not, its size...")
ns.Set("fade.range", False); pe.set("plate")
check(not shows("FOREVERPLATESPLUS_FADE_RANGEALPHA"), "out-of-range opacity hidden while fading is off")
ns.Set("fade.range", True)
check(shows("FOREVERPLATESPLUS_FADE_RANGEALPHA"), "and listed when it is on")
pe.set("name")
check(shows("FOREVERPLATESPLUS_LOOK_ENEMYNAME_COLOR") and not shows("FOREVERPLATESPLUS_LOOK_ENEMYNAME_RGB"), "own colour swatch hidden until 'own' is picked")
ns.Set("look.enemyName.color", "custom")
check(shows("FOREVERPLATESPLUS_LOOK_ENEMYNAME_RGB"), "own colour: swatch listed")
S["FOREVERPLATESPLUS_LOOK_ENEMYNAME_RGB"].set("FF00FF00")
check(ns.Get("look.enemyName.rgb") == "ff00ff00" and list(uf("nameplate1").name.vertex.values()) == [0, 1, 0], "enemy name in its own colour")
G.CompactUnitFrame_UpdateName(uf("nameplate1"))
check(list(uf("nameplate1").name.vertex.values()) == [0, 1, 0], "kept after the game's name update")
ns.Set("look.enemyName.color", "class")
check(list(uf("nameplate1").name.vertex.values()) == [0, 1, 0], "class colour on a mob: the game's own colour")
L.execute('UNITS.nameplate2.class = "HUNTER"')
G.FireEvent("UNIT_NAME_UPDATE", "nameplate2")
check(abs(uf("nameplate2").name.vertex[1] - 0.67) < 1e-9, "class colour on an enemy player")
ns.ResetLook("enemyName")
check(ns.Get("look.enemyName.color") == "game", "reset: as in the game")
pe.set("guild")
check(shows("FOREVERPLATESPLUS_PLATES_GUILDENEMIES") and shows("FOREVERPLATESPLUS_LOOK_ENEMYGUILD_PLACE"), "guild part: show it, where to write it")
# names
ns.Set("look.enemyName.scale", 130)
check(abs(uf("nameplate1").name.textScale - 1.3) < 1e-9 and abs(uf("nameplate3").name.textScale - 1.15) < 1e-9, "enemy name size: enemies only")
S["FOREVERPLATESPLUS_LOOK_ENEMYNAME_SCALE"].set(117)
check(ns.Get("look.enemyName.scale") == 115 and ns.db.overrides["look.enemyName.scale"] is None, "slider snaps to 5%; back at the preset value nothing is stored")
ns.Set("look.friendName.x", 10); ns.Set("look.friendName.y", 3)
p3 = points("nameplate3")
check(len(p3) == 1 and p3[0][3] == 24 and p3[0][4] == 5, "ally name moved 10 right, 3 up")
uf("nameplate3").UpdateAnchors(uf("nameplate3"))
p3 = points("nameplate3")
check(len(p3) == 1 and p3[0][3] == 24 and p3[0][4] == 5, "the game lays the plate out again: same place, offsets don't pile up")
ns.Set("plates.friendFullNames", False)
p3 = points("nameplate3")
check(len(p3) == 2 and p3[0][3] == 10 and p3[0][4] == 5, "full names off: the game's own points, moved")
ns.Set("plates.friendFullNames", True)
ns.Set("look.friendName.x", 0); ns.Set("look.friendName.y", 0)
p3 = points("nameplate3")
check(len(p3) == 1 and p3[0][3] == 14 and p3[0][4] == 2, "offsets back at 0: the name where the game puts it")
ns.Set("look.friendName.color", "custom"); ns.Set("look.friendName.rgb", "ffff0000")
check(list(uf("nameplate3").name.vertex.values()) == [1, 0, 0] and cv["nameplateUseClassColorForFriendlyPlayerUnitNames"] == "0", "ally name in its own colour")
ns.ResetLook("friendName")
# where the name goes
ns.Set("look.enemyName.where", "inside")
pn1 = points("nameplate1")
check(len(pn1) == 1 and pn1[0][0] == "LEFT" and pn1[0][2] == "LEFT" and pn1[0][3] == 4 and uf("nameplate1").name.justify == "LEFT", "enemy name inside the bar, from the left")
check(c1.points[1][5] == 2, "the addon's icon row comes down to the bar: no name above it")
uf("nameplate1").UpdateAnchors(uf("nameplate1"))
check(points("nameplate1")[0][0] == "LEFT" and uf("nameplate1").name.justify == "LEFT", "kept when the game lays the plate out again")
ns.Set("look.enemyName.where", "above")
pn1 = points("nameplate1")
check(pn1[0][0] == "BOTTOM" and pn1[0][2] == "TOP" and pn1[0][3] == 0 and uf("nameplate1").name.justify == "CENTER", "above the bar, centred")
ns.Set("look.enemyName.where", "game")
check(uf("nameplate1").name.justify == "CENTER" and c1.points[1][5] > 10, "as in the game again")
ns.Set("look.friendName.where", "inside")
check(uf("nameplate3").showOnlyName or points("nameplate3")[0][0] == "LEFT", "ally with a bar: name inside too")
ns.Set("look.friendName.where", "game")
# guild line relative to the name, with its own colour
L.execute('UNITS.nameplate3.guild = "Орда навсегда"')
ns.Set("plates.guildFriends", True)
g3 = ns.GetSubtitleLine(uf("nameplate3"))
check(g3.shown and abs(g3.alpha - 0.55 * 0.85) < 1e-9 and abs(g3.textScale - 1.15) < 1e-9, "guild: opacity and size follow the name's")
ns.Set("look.friendGuild.alpha", 50); ns.Set("look.friendGuild.scale", 80); ns.Set("look.friendGuild.rgb", "ff00ff00")
check(abs(g3.alpha - 0.275) < 1e-9 and abs(g3.textScale - 0.92) < 1e-9 and list(g3.textColor.values()) == [0, 1, 0], "guild at 50% of the name's opacity, 80% of its size, green")
ns.ResetLook("friendGuild"); ns.Set("plates.guildFriends", False)
L.execute('UNITS.nameplate3.guild = nil')
# health numbers
ns.Set("enemyText.idle", "both")
ns.Set("look.enemyHealth.alpha", 60); ns.Set("look.enemyHealth.scale", 120)
check(all(abs(t.alpha - 0.6) < 1e-9 and abs(t.textScale - 1.2) < 1e-9 for t in texts("nameplate1")), "enemy health numbers at 60% opacity, 120% size")
lt = hbt("nameplate1").LeftText
ns.Set("look.enemyHealth.x", -3)
check(lt.points[1][4] == -7, "health numbers 3 px further left")
uf("nameplate1").UpdateAnchors(uf("nameplate1"))
check(len(lt.points) == 1 and lt.points[1][4] == -7, "after the game re-anchors them: still 3 px, not 6")
ns.ResetLook("enemyHealth")
check(lt.points[1][4] == -4 and all(t.alpha == 1 and t.textScale == 1 for t in texts("nameplate1")), "reset this part: the game's look and place back")
ns.Set("enemyText.idle", "none")
# cast bar
cbt = castbar("nameplate1").Text
check(abs(cbt.textScale - 1.15) < 1e-9, "spell name 15% bigger by default")
ns.Set("look.castText.y", 2)
check(cbt.points[1][5] == 2, "spell name 2 px up")
uf("nameplate1").UpdateAnchors(uf("nameplate1"))
check(len(cbt.points) == 1 and cbt.points[1][5] == 2, "re-anchored by the game: moved once again, not twice")
ns.Set("look.castText.y", 0)
ns.Set("look.castTimer.x", 4)
tm = holder_of("nameplate1").extra.timer
check(tm.points[1][4] == 7 and abs(tm.textScale - 1.15) < 1e-9, "cast timer 4 px further right, 115%")
ns.Set("look.castTimer.x", 0)
# the game's aura lists
af = uf("nameplate1").AurasFrame
check(af.BuffListFrame.scale is None and af.BuffListFrame.alpha is None, "the game's lists untouched at 100%")
ns.Set("look.gameBuffs.scale", 150); ns.Set("look.gameBuffs.alpha", 50); ns.Set("look.gameBuffs.x", -6)
check(af.BuffListFrame.scale == 1.5 and af.BuffListFrame.alpha == 0.5 and af.BuffListFrame.points[1][4] == -9, "game buffs (PvP): 150%, 50%, 6 px further left")
check(uf("nameplate3").AurasFrame.BuffListFrame.scale is None, "allies' game icons follow their own setting")
ns.ResetLook("gameBuffs")
check(af.BuffListFrame.scale == 1 and af.BuffListFrame.alpha == 1 and af.BuffListFrame.points[1][4] == -5, "reset: the game's size, opacity and place")
ns.Set("look.friendGame.scale", 80)
check(uf("nameplate3").AurasFrame.BuffListFrame.scale == 0.8 and af.BuffListFrame.scale == 1, "ally game icons 80%, enemies unchanged")
ns.ResetLook("friendGame")
dl = af.DebuffListFrame
ys = lambda: sorted(dl.points[i][5] for i in range(1, len(dl.points) + 1))
ns.Set("look.gameDebuffs.y", 4)
check(ys() == [4, 6], "game debuffs 4 px up (both of its points)")
uf("nameplate1").UpdateAnchors(uf("nameplate1"))
uf("nameplate1").UpdateAnchors(uf("nameplate1"))
check(ys() == [4, 6], "the game re-sets one of its points twice: still 4 px")
ns.Set("look.gameDebuffs.y", 0)
check(ys() == [0, 2], "back at 0")
ns.Set("look.gameCC.scale", 120)
check(af.CrowdControlListFrame.scale == 1.2 and af.LossOfControlFrame.scale is None, "CC list scaled; loss of control left to the game (it scales it itself)")
ns.ResetLook("gameCC")
# our rows
ns.Set("look.mine.alpha", 50)
check(abs(b.alpha - 0.5) < 1e-9, "my debuff icons at 50%")
S["FOREVERPLATESPLUS_LOOK_ADDONAURAS_X_2"].set(5)
check(ns.Get("look.addonAuras.x") == 5 and c1.points[1][4] == 5 and S["FOREVERPLATESPLUS_LOOK_ADDONAURAS_X"].get() == 5, "one offset for the enemy's icon row, shown in both parts")
ns.Set("look.dispel.y", 3)
check(c1.points[1][4] == 5 and c3.points[1][4] == 0, "the ally row has its own offset")
ns.Set("look.addonAuras.x", 0); ns.Set("look.mine.alpha", 100); ns.Set("look.dispel.y", 0)
# quest marker
L.execute("UNITS.nameplate1.quest = true"); G.FireEvent("QUEST_LOG_UPDATE"); G.RunTimers()
ns.Set("look.quest.scale", 200); ns.Set("look.quest.y", -2)
check(q1.width == 28 and q1.points[1][5] == -2, "quest marker 200%, 2 px down")
ns.ResetLook("quest")
check(q1.width == 14, "quest marker reset")
L.execute("UNITS.nameplate1.quest = nil"); G.FireEvent("QUEST_LOG_UPDATE"); G.RunTimers()
# picking a part in the sketch; resetting a part with the button
ns.SelectPart("enemy", "killzone")
check(ns.db.parts["enemy"] == "killzone" and pe.get() == "killzone", "a part picked in the sketch is selected in the list")
check(shows("FOREVERPLATESPLUS_KILLZONE_ENABLED") and shows("FOREVERPLATESPLUS_KILLZONE_VALUE") and not shows("FOREVERPLATESPLUS_KILLZONE_PERCENT"), "execute mark part: options of the current mode only")
ns.Set("killzone.critMult", 200); ns.Set("info.quest", False)
buttons = [i for i in G.SETTINGS.layouts["Враг"].inits.values() if i.button == ns.L.RESET_PART]
visible = [i for i in buttons if all(fn() for fn in i.shown.values())]
check(len(visible) == 1, "one 'reset this part' button listed at a time")
visible[0].click()
check(ns.Get("killzone.critMult") == 150 and ns.Get("info.quest") is False, "reset this part: only the execute mark's settings")
ns.Set("info.quest", True)
check(len(G.ERRORS) == 0, "no errors on the nameplate pages: " + "; ".join(G.ERRORS[i] for i in range(1, len(G.ERRORS) + 1)))

# ---- unit frames: text on the health and mana bars (off by default)
L.execute("""
local function Bar(parent, withTexts)
  local bar = CreateFrame("StatusBar", nil, parent)
  if withTexts then
    bar.TextString = bar:CreateFontString(); bar.TextString:SetPoint("CENTER", bar, "CENTER")
    bar.LeftText = bar:CreateFontString(); bar.LeftText:SetPoint("LEFT", bar, "LEFT", 2, 0)
    bar.RightText = bar:CreateFontString(); bar.RightText:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
  end
  return bar
end
PlayerFrame = CreateFrame("Button"); PlayerFrame.unit = "player"
PlayerFrame.PlayerFrameContent = { PlayerFrameContentMain = { HealthBarsContainer = { HealthBar = Bar(PlayerFrame, true) }, ManaBarArea = { ManaBar = Bar(PlayerFrame, true) } } }
TargetFrame = CreateFrame("Button")
TargetFrame.TargetFrameContent = { TargetFrameContentMain = { HealthBarsContainer = { HealthBar = Bar(TargetFrame, true) }, ManaBar = Bar(TargetFrame, true) } }
TargetFrame.totFrame = CreateFrame("Button", nil, TargetFrame)
TargetFrame.totFrame.HealthBar = Bar(TargetFrame.totFrame, false)
TargetFrame.totFrame.ManaBar = Bar(TargetFrame.totFrame, false)
UNITS.player = UNITS.player or {}
UNITS.player.health = 12345; UNITS.player.maxHealth = 14500; UNITS.player.power = 8200; UNITS.player.maxPower = 10000
UNITS.target = { health = SECRET_VALUE, maxHealth = SECRET_VALUE, power = 100, maxPower = 100 }
UNITS.targettarget = { health = 3200, maxHealth = 9000, power = 0, maxPower = 0 }
""")
pmain = G.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
phb, pmb = pmain.HealthBarsContainer.HealthBar, pmain.ManaBarArea.ManaBar
thb = G.TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
tot = G.TargetFrame.totFrame.HealthBar
ns.UpdateUnitFrames()
check(ns.GetFrameOverlay(phb) is None and ns.GetFrameOverlay(thb) is None and phb.TextString.alpha != 0, "every bar as in the game by default: nothing touched")
ns.Set("frames.target.health", "current")
to = ns.GetFrameOverlay(thb)
check(to is not None and L.eval("function(t) return issecretvalue(t) end")(to.center.text) and thb.TextString.alpha == 0 and len(G.ERRORS) == 0, "target's health set to current: shown right away (secret here), the game's text hidden, no errors")
check(ns.GetFrameOverlay(phb) is None and phb.TextString.alpha != 0, "your frame still the game's")
L.execute("UNITS.target.health = 45600; UNITS.target.maxHealth = 80000"); ns.UpdateUnitFrames()
check(to.center.text == "45.6к", "target's current health: 45.6к")
ns.Set("frames.player.health", "currentPercent"); ns.Set("frames.player.mana", "current")
po = ns.GetFrameOverlay(phb)
check(po.center.text == "12.3к (85%)" and phb.LeftText.alpha == 0 and ns.GetFrameOverlay(pmb).center.text == "8.2к", "your health: current and percent; mana: current")
ns.Set("frames.tot.health", "percent")
check(ns.GetFrameOverlay(tot).center.text == "36%" and abs(ns.GetFrameOverlay(tot).center.textScale - 0.8) < 1e-9, "target of target: percent, smaller text, on a bar without the game's texts")
check(ns.GetFrameOverlay(G.TargetFrame.totFrame.ManaBar) is None, "its mana left to the game")
for fmt, expected in (("current", "12.3к"), ("percent", "85%"), ("currentMax", "12.3к / 14.5к"), ("currentMaxPercent", "12.3к / 14.5к (85%)"), ("missing", "-2.1к"), ("missingPercent", "-2.1к (85%)")):
    ns.Set("frames.player.health", fmt)
    check(po.center.text == expected, f"health as {fmt}: {po.center.text!r}")
ns.Set("frames.player.health", "split")
check(po.left.text == "85%" and po.right.text == "12.3к" and po.center.text == "", "percent left, current right")
ns.Set("frames.player.health", "none")
check(po.center.text == "" and po.left.text == "" and phb.TextString.alpha == 0, "nothing: no text at all")
ns.Set("frames.player.health", "game")
check(phb.TextString.alpha == 1 and po.center.text == "", "as in the game: the game's text back")
ns.Set("frames.player.health", "currentPercent")
ns.Set("frames.player.when", "combat")
check(po.center.text == "", "only in combat: nothing out of combat")
L.execute("IN_COMBAT = true"); ns.UpdateUnitFrames()
check(po.center.text == "12.3к (85%)", "in combat: shown")
L.execute("IN_COMBAT = false"); ns.Set("frames.player.when", "always")
L.execute("UNITS.player.dead = true"); ns.UpdateUnitFrames()
check(po.center.text == "", "dead: the game's own text says it")
L.execute("UNITS.player.dead = nil"); ns.UpdateUnitFrames()
ns.Set("frames.player.health", "missing"); ns.CopyFrameText("player")
check(ns.Get("frames.target.health") == "missing" and ns.Get("frames.tot.health") == "missing" and ns.Get("frames.tot.scale") == 80, "the same on the other frames (sizes stay)")
ns.ResetOverrides()
check(phb.TextString.alpha == 1 and thb.TextString.alpha == 1 and po.center.text == "" and to.center.text == "", "all as in the game again: the game's texts back")
pf = S["FOREVERPLATESPLUS_UI_PART_FRAMES"]
check(pf.page == "Фреймы" and [d.value for d in pf.getOptions().values()] == ["plate", "player", "target", "tot"], "Frames page: numbers, your frame, target, target of target")
check(S["FOREVERPLATESPLUS_FRAMES_ENABLED"] is None, "no separate switch for the block")
pf.set("tot")
check(shows("FOREVERPLATESPLUS_FRAMES_TOT_HEALTH") and not shows("FOREVERPLATESPLUS_FRAMES_PLAYER_HEALTH") and not shows("FOREVERPLATESPLUS_FRAMES_NUMBER"), "a frame's options listed alone")
pf.set("plate")
check(len(G.ERRORS) == 0, "no errors on frames: " + "; ".join(G.ERRORS[i] for i in range(1, len(G.ERRORS) + 1)))

# proxy settings round trip
s = S["FOREVERPLATESPLUS_NATIVE_CASTICON"]
s.set(False)
check(not bit("nameplateCastBarDisplay", 2) and s.get() is False, "checkbox proxy writes override and CVar")
slider = S["FOREVERPLATESPLUS_AURAS_MINEMAX"]
slider.set(4.4)
check(ns.Get("auras.mineMax") == 4 and c1.groups["mine"].max == 4, "slider rounds to integer and updates max icons")

# reset & presets
G.SlashCmdList.FOREVERPLATESPLUS("reset")
L.execute("PLATES.target = PLATES.nameplate1")  # the preset shows the mark on the target only
G.FireEvent("PLAYER_TARGET_CHANGED")
check(ns.CountOverrides() == 0 and bit("nameplateCastBarDisplay", 2) and ns.Get("killzone.value") == 350 and ns.Get("killzone.mode") == "spell" and kz1[0].value == 412, "/fpl reset restores preset values (spell mode, 412)")
for k in ("FOREVERPLATESPLUS_KILLZONE_COMBATONLY", "FOREVERPLATESPLUS_KILLZONE_SPELLBONUS"):
    check(S[k] is not None, f"setting {k} in the panel")
check([d.value for d in S["FOREVERPLATESPLUS_KILLZONE_MODE"].getOptions().values()] == ["spell", "value", "percent"], "zone type dropdown: spell, value, percent")
G.SlashCmdList.FOREVERPLATESPLUS("preset base")
check(ns.GetActivePreset() == "BASE" and not kz1[0].shown and not cz1[0].shown, "base preset turns the kill zone off")
G.SlashCmdList.FOREVERPLATESPLUS("preset auto")
check(ns.GetActivePreset() == "PRIEST" and kz1[0].shown, "auto brings the priest preset back")
G.SlashCmdList.FOREVERPLATESPLUS("preset nope")
check(ns.db.preset == "auto", "unknown preset is rejected")

# removal
G.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
check(not c1.enabled and not c1.shown and not kz1[0].shown, "removed plate: container disabled, zone hidden")
G.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate3")
check(all(t.alpha == 1 and t.width == 0 and t.wordWrap is True for t in texts("nameplate3")), "removed friendly plate gets its text back (alpha, width, wrap) before reuse")
check(len(points("nameplate3")) == 2, "removed friendly plate gets the game's name points back before reuse")
check(uf("nameplate3").name.alpha == 1, "removed friendly plate gets full name opacity back before reuse")

# game defaults
G.SlashCmdList.FOREVERPLATESPLUS("gamedefaults")
check(cv["nameplateShowOffscreen"] == "1" and cv["nameplateInfoDisplay"] == "0" and ns.Get("native.manage") is False, "/fpl gamedefaults restores game values and stops managing")
before = G.CVAR_SETS
ns.Set("native.castIcon", False)
check(G.CVAR_SETS == before, "with management off the addon leaves CVars alone")
check(len(G.ERRORS) == 0, "no errors at the end: " + "; ".join(G.ERRORS[i] for i in range(1, len(G.ERRORS) + 1)))

# ---------------------------------------------------------------- warrior, english, old stacking CVar, no LOS CVar
old = 'CVARS = { nameplateInfoDisplay = "0", nameplateCastBarDisplay = "0", nameplateThreatDisplay = "0", nameplateEnemyNpcAuraDisplay = "0", nameplateEnemyPlayerAuraDisplay = "0", nameplateFriendlyPlayerAuraDisplay = "0", nameplateMotion = "0", nameplateShowAll = "0", nameplateShowOffscreen = "1", nameplateShowFriendlyNpcs = "1", nameplateStyle = "0" }'
L2, ns2 = new_runtime(locale="enUS", player_class="WARRIOR", cvars_override=old + "; DESCRIPTIONS_AVAILABLE = true")
G2 = L2.globals()
G2.FireEvent("ADDON_LOADED", "ForeverPlatesPlus"); G2.FireEvent("PLAYER_LOGIN"); G2.FireEvent("PLAYER_ENTERING_WORLD"); G2.RunTimers()
check(ns2.GetActivePreset() == "BASE", "class without a preset uses BASE")
check(G2.CVARS["nameplateMotion"] == "1", "falls back to nameplateMotion when stacking types are missing")
check(G2.SETTINGS["FOREVERPLATESPLUS_NATIVE_LOSFADE"] is None, "LOS slider hidden when the client lacks the CVar")
check(ns2.L.PART_MINE == "Personal debuffs" and ns2.L.PART_DISPEL == "Dispellable debuffs", "English strings on non-Russian clients, in the game's own terms")
first = G2.SETTINGS.layout.inits[1]
check(first.template == "ForeverPlatesPlusDescriptionTemplate" and first.data["name"] == ns2.L.ABOUT_MAIN and first.GetExtent() >= 40, "page description drawn with our template, sized for its text")
fake = L2.eval("function() local f = CreateFrame('Frame'); f.Title = f:CreateFontString(); return f end")()
G2.ForeverPlatesPlusDescriptionMixin.Init(fake, first)
check(fake.Title.text == ns2.L.ABOUT_MAIN and fake.Title.width == 560 and fake.headerInit is not None, "description element: game header set up, then shown as wrapped text")
L2.execute('UNITS.nameplate1 = { canAttack = true, isPlayer = false, maxHealth = 1000 }')
G2.MakePlate("nameplate1"); G2.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1"); G2.RunTimers()
cont = [f for f in G2.ALL_FRAMES.values() if f.kind == "AuraContainer"]
anchored_to_bar = L2.eval("function(c) return rawequal(c.points[1][2], PLATES.nameplate1.UnitFrame.HealthBarsContainer) end")
check(len(cont) == 1 and anchored_to_bar(cont[0]), "Modern style (name inside bar): row anchored to the bar")
G2.FireEvent("PLAYER_REGEN_DISABLED")
check(not any(f.kind == "StatusBar" and f.parent == G2.PLATES["nameplate1"].UnitFrame.HealthBarsContainer.healthBar and f.shown for f in G2.ALL_FRAMES.values()), "base preset: no kill zone even in combat")
# Modern style (name inside the bar, ends where the numbers start)
L2.execute('UNITS.nameplate2 = { canAttack = false, isPlayer = true, isFriend = true, maxHealth = 3000 }')
G2.MakePlate("nameplate2"); G2.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate2"); G2.RunTimers()
pts2 = L2.eval("function(u) local out = {}; for i, p in ipairs(PLATES[u].UnitFrame.name.points) do out[i] = { p[1], p[3], p[4], p[5] } end; return out end")
pn2 = lambda u: [list(p.values()) for p in pts2(u).values()]
check(pn2("nameplate2") == [["LEFT", "LEFT", 4, 0]], "Modern, ally (numbers hidden): name pinned only on the left, grows freely")
ns2.Set("plates.friendHealth", "both")
check(len(pn2("nameplate2")) == 2, "Modern, ally with numbers shown: the game's layout (name stops before the numbers)")
L2.execute('UNITS.nameplate2.guild = "Орда"')
ns2.Set("plates.guildFriends", True)
gl = ns2.GetSubtitleLine(G2.PLATES["nameplate2"].UnitFrame)
check(gl.shown and gl.points[1][1] == "BOTTOMLEFT" and gl.points[1][3] == "TOPLEFT" and gl.justify == "LEFT", "name written from the left (Modern style): its guild line starts at the same left edge")
ns2.Set("plates.guildFriends", False)
ns2.Set("plates.friendHealth", "none")
check(len(pn2("nameplate2")) == 1, "numbers hidden again: name free again")
check(len(pn2("nameplate1")) == 1, "Modern, enemy normally (no numbers): name free")
L2.execute("PLATES.target = PLATES.nameplate1"); G2.FireEvent("PLAYER_TARGET_CHANGED")
check(len(pn2("nameplate1")) == 2, "Modern, enemy in target (numbers shown): the game's layout, name stops before them")
L2.execute("PLATES.target = nil"); G2.FireEvent("PLAYER_TARGET_CHANGED")
check(len(pn2("nameplate1")) == 1, "target cleared: name free again")
inits = G2.SETTINGS.layouts["Enemy"].inits
check(inits[1].template == "ForeverPlatesPlusDescriptionTemplate" and inits[2].template == "ForeverPlatesPlusPreviewTemplate" and inits[2].data["kind"] == "enemy" and inits[2].GetExtent() == 200, "Enemy page: description, then the sketch")
sketch_frame = L2.eval("function() local f = CreateFrame('Frame'); f.Title = f:CreateFontString(); return f end")()
G2.ForeverPlatesPlusPreviewMixin.Init(sketch_frame, inits[2])
enemy_sketch = sketch_frame.fpSketches["enemy"]
check(enemy_sketch is not None and sketch_frame.headerInit is not None and enemy_sketch.hint.text.startswith("The whole nameplate:"), "sketch drawn, the selected part explained under it: " + str(enemy_sketch.hint.text)[:60])
guild_button = [x for x in enemy_sketch.buttons.values() if x.part == "guild"]
check(len(guild_button) == 1, "the guild is a clickable part of the enemy sketch")
guild_button[0].scripts["OnClick"](guild_button[0])
check(ns2.db.parts["enemy"] == "guild" and "Currently off." in enemy_sketch.hint.text and guild_button[0].selected.shown, "click selects the part; the hint says it is off now")
check(abs(enemy_sketch.parts.enemyGuild.alpha - 0.85 * 0.25) < 1e-9, "parts turned off are drawn faint")
ns2.Set("look.enemyName.y", 6)
en = enemy_sketch.parts.enemyName
check(en.parent.GetFrameLevel(en.parent) > enemy_sketch.parts.bar.GetFrameLevel(enemy_sketch.parts.bar), "sketch: the name is drawn on a layer above the bar (inside the bar it stays visible)")
check(en.points[1][1] == "LEFT" and en.points[1][5] == 6, "the sketch follows the game's style (Modern: name inside the bar) and the settings (6 px up)")
ns2.Set("look.enemyName.where", "above")
check(en.points[1][1] == "BOTTOM" and en.points[1][5] == 8, "name above the bar in the sketch")
ns2.Set("look.enemyName.y", 0); ns2.Set("look.enemyName.where", "game")
qp = enemy_sketch.parts.gameBuffs.points[1]
same2 = L2.eval("function(a, b) return rawequal(a, b) end")
check(same2(qp[2], enemy_sketch.parts.quest), "sketch: the game's buffs follow the quest marker")
ns2.Set("info.quest", False)
qp = enemy_sketch.parts.gameBuffs.points[1]
check(same2(qp[2], enemy_sketch.parts.bar) and qp[4] == -5, "quest marker off: the game's buffs move up to the bar")
ns2.Set("info.quest", True)
ally_sketch = ns2.ShowSketch(sketch_frame, "ally")
check(not enemy_sketch.canvas.shown and ally_sketch.canvas.shown and len(ally_sketch.buttons) == 6, "the same list frame shows the ally sketch on the Ally page")
pet_sketch = ns2.ShowSketch(sketch_frame, "pet")
check(pet_sketch.canvas.shown and [x.part for x in pet_sketch.buttons.values()] == ["plate", "name", "owner"], "pet sketch: plate, name, owner")
check(G2.SETTINGS.layouts["Friendly"].inits[2].data["kind"] == "ally" and G2.SETTINGS.layouts["Friendly pet"].inits[2].data["kind"] == "pet", "each page has its own sketch")
frames_sketch = ns2.ShowSketch(sketch_frame, "frames")
ps = frames_sketch.parts.frameBars.player.health.center
check(ps.text == "12 345 / 14 500" and frames_sketch.parts.player.alpha == 0.25, "frames sketch: as in the game, drawn faint: " + str(ps.text))
ns2.Set("frames.player.health", "currentPercent")
check(ps.text == "12.3K (85%)" and frames_sketch.parts.player.alpha == 1, "a format chosen: shown in the sketch")
fbtn = [x for x in frames_sketch.buttons.values() if x.part == "target"][0]
fbtn.scripts["OnClick"](fbtn)
check(ns2.db.parts["frames"] == "target" and "Target:" in frames_sketch.hint.text and "The game writes this text now." in frames_sketch.hint.text, "a frame clicked in the sketch is selected")
nbtn = [x for x in frames_sketch.buttons.values() if x.part == "plate"]
check(len(nbtn) == 2 and frames_sketch.parts.numbers.text == "Number format: 12.3K", "a clickable label for how numbers are written")
ns2.Set("frames.player.health", "game")
check(G2.SETTINGS["FOREVERPLATESPLUS_UI_PART_ENEMY"] is not None and G2.SETTINGS["FOREVERPLATESPLUS_UI_PART_ENEMY"].control is None, "with the sketch on the page the part is picked there only (no second list)")
check(len(G2.ERRORS) == 0, "no errors for warrior run")

# ---------------------------------------------------------------- settings saved by 0.9 are carried over
old_db = 'ForeverPlatesPlusCharDB = { preset = "auto", overrides = { ["plates.nameScale"] = 130, ["plates.guild"] = "all", ["auras.mineSize"] = 33, ["plates.friendNameAlpha"] = 70, ["auras.purgeSize"] = 20 } }'
L3, ns3 = new_runtime(cvars_override=old_db)
G3 = L3.globals()
G3.FireEvent("ADDON_LOADED", "ForeverPlatesPlus"); G3.FireEvent("PLAYER_LOGIN"); G3.RunTimers()
o = ns3.db.overrides
check(ns3.Get("look.enemyName.scale") == 130 and ns3.Get("look.friendName.scale") == 130, "old name size moves to both names")
check(ns3.Get("plates.guildFriends") is True and ns3.Get("plates.guildEnemies") is True, "old 'guilds on allies and enemies' becomes both checkboxes")
check(ns3.Get("look.mine.scale") == 150 and ns3.Get("look.friendName.alpha") == 70 and ns3.Get("look.purge.scale") == 100, "icon sizes become percents, ally name opacity kept")
check(o["plates.nameScale"] is None and o["plates.guild"] is None and o["auras.mineSize"] is None and ns3.db.version == 4, "old keys removed, database version 4")
check(len(G3.ERRORS) == 0, "no errors after carrying settings over")

# ---------------------------------------------------------------- settings saved by 0.10 are carried over
old_db = 'ForeverPlatesPlusCharDB = { preset = "auto", version = 2, overrides = { ["look.guild.scale"] = 90, ["look.health.alpha"] = 70, ["look.friendName.alpha"] = 40, ["look.addonAuras.y"] = 3, ["native.friendClassColor"] = true, ["plates.petClassColor"] = false, ["plates.friendHealthText"] = true, ["auras.timer"] = false, ["native.healthValue"] = false } }'
L4, ns4 = new_runtime(cvars_override=old_db)
G4 = L4.globals()
G4.FireEvent("ADDON_LOADED", "ForeverPlatesPlus"); G4.FireEvent("PLAYER_LOGIN"); G4.RunTimers()
check(ns4.Get("look.enemyGuild.scale") == 90 and ns4.Get("look.friendGuild.scale") == 90 and ns4.Get("look.enemyHealth.alpha") == 70 and ns4.Get("look.friendHealth.alpha") == 70, "0.10 guild and numbers look goes to both sides")
check(ns4.Get("look.petName.alpha") == 40 and ns4.Get("look.dispel.y") == 3, "pets keep the ally name's opacity, the ally row keeps its offset")
check(ns4.Get("look.friendName.color") == "class" and ns4.Get("look.petName.color") == "white" and ns4.Get("plates.friendHealth") == "both", "switches become choices")
check(ns4.Get("auras.mineTimer") is False and ns4.Get("auras.dispelTimer") is False and ns4.Get("native.healthValue") is True, "timers per row; the game's number switch back on")
check(ns4.db.version == 4 and len(G4.ERRORS) == 0, "database version 4, no errors")

# ---------------------------------------------------------------- 0.12.0 frames switch
old_db = 'ForeverPlatesPlusCharDB = { preset = "auto", version = 3, overrides = { ["frames.enabled"] = true, ["frames.target.health"] = "current" } }'
L5, ns5 = new_runtime(cvars_override=old_db)
G5 = L5.globals()
G5.FireEvent("ADDON_LOADED", "ForeverPlatesPlus"); G5.FireEvent("PLAYER_LOGIN"); G5.RunTimers()
check(ns5.Get("frames.player.health") == "currentPercent" and ns5.Get("frames.target.health") == "current" and ns5.Get("frames.tot.mana") == "none" and ns5.db.overrides["frames.enabled"] is None, "a frames block that was on keeps its texts; the switch is gone")
check(len(G5.ERRORS) == 0, "no errors carrying the frames switch over")

# ---------------------------------------------------------------- every string in both languages
import re as _re
_missing = []
for _line in open(os.path.join(sys.argv[1], "Locale.lua"), encoding="utf-8"):
    if _line.startswith("T("):
        _m = _re.match(r'T\("([A-Za-z0-9_]+)",\s*"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"\)', _line)
        if not _m or not _m.group(2).strip() or not _m.group(3).strip():
            _missing.append(_line[:40])
check(not _missing, "every string has Russian and English text: " + "; ".join(_missing))
check("olour" not in open(os.path.join(sys.argv[1], "Locale.lua"), encoding="utf-8").read(), "English in the game's US spelling (color, not colour)")

print()
print("FAILURES:", len(failures))
sys.exit(1 if failures else 0)
