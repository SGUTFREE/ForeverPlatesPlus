"""Load Forever Plates into a mocked WoW API and check its behaviour.

usage: python3 -I run_tests.py <addon_dir> <harness_dir>
"""
import os
import re
import sys

from lupa import lua51

addon_dir, harness_dir = sys.argv[1], sys.argv[2]
toc = open(os.path.join(addon_dir, "ForeverPlates.toc"), encoding="utf-8").read()
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
        chunk("ForeverPlates", ns)
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
        check(name in ("ForeverPlatesCharDB", "SLASH_FOREVERPLATES1", "SLASH_FOREVERPLATES2"), f"{f}: global assignment {name} is expected")

# ---------------------------------------------------------------- priest, full flow
L, ns = new_runtime()
G = L.globals()
G.FireEvent("ADDON_LOADED", "ForeverPlates")
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
ns.Set("native.friendClassColor", True)
check(cv["nameplateUseClassColorForFriendlyPlayerUnitNames"] == "1", "class colour can be turned on")
ns.Set("native.friendClassColor", False)
check(G.SETTINGS["FOREVERPLATES_NATIVE_FRIENDCLASSCOLOR"] is not None, "class colour checkbox in the panel")
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
check(G.SETTINGS["FOREVERPLATES_NATIVE_FRIENDNAMESONLY"] is not None, "names-only dropdown in the panel")
sets_after_login = G.CVAR_SETS
G.FireEvent("PLAYER_ENTERING_WORLD"); G.RunTimers()
check(G.CVAR_SETS == sets_after_login, "re-applying unchanged settings writes no CVars")

# settings panel
S = G.SETTINGS
check(S.registered is not None, "settings category registered")
preset_setting = S["FOREVERPLATES_PROFILE_PRESET"]
check(preset_setting is not None and preset_setting.default == "auto", "preset dropdown default is auto")
check(S["FOREVERPLATES_NATIVE_LOSFADE"] is not None, "LOS slider shown when client has the CVar")

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
check(G.SETTINGS["FOREVERPLATES_PLATES_FRIENDFULLNAMES"] is not None, "full names checkbox in the panel")
# ally name opacity
check(abs(uf("nameplate3").name.alpha - 0.55) < 1e-9, "ally name at 55% opacity by default")
check(uf("nameplate1").name.alpha is None, "enemy name untouched")
ns.Set("plates.friendNameAlpha", 100)
check(uf("nameplate3").name.alpha == 1, "100%: the game's own opacity back")
ns.Set("plates.friendNameAlpha", 55)
check(abs(uf("nameplate3").name.alpha - 0.55) < 1e-9, "back to 55%")
# ally pet: name only (white, transparent), like ally players
L.execute('UNITS.nameplate6 = { canAttack = false, isPlayer = false, isFriend = true, isPet = true, maxHealth = 500 }')
G.MakePlate("nameplate6")
L.execute("local uf = PLATES.nameplate6.UnitFrame; uf.CastBarsContainer = CreateFrame('Frame', nil, uf); uf.AurasFrame = CreateFrame('Frame', nil, uf)")
G.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate6"); G.RunTimers()
pet = uf("nameplate6")
check(pet.HealthBarsContainer.alpha == 0 and pet.CastBarsContainer.alpha == 0 and pet.AurasFrame.alpha == 0 and pet.PlayerLevelDiffFrame.alpha == 0, "ally pet: bar, cast bar, auras and level hidden")
check(list(pet.name.vertex.values()) == [1, 1, 1] and abs(pet.name.alpha - 0.55) < 1e-9, "ally pet: white name at 55%")
G.CompactUnitFrame_UpdateName(pet)
check(list(pet.name.vertex.values()) == [1, 1, 1], "the game's name update doesn't turn it green again")
ns.Set("plates.petNamesOnly", False)
check(pet.HealthBarsContainer.alpha == 1 and pet.AurasFrame.alpha == 1, "pets option off: plate parts back")
ns.Set("plates.petNamesOnly", True)
check(pet.HealthBarsContainer.alpha == 0, "on again")
check(uf("nameplate1").HealthBarsContainer.alpha is None, "enemy plate parts untouched")
G.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate6")
check(pet.HealthBarsContainer.alpha == 1 and pet.name.alpha == 1, "removed pet plate gets everything back before reuse")
check(G.SETTINGS["FOREVERPLATES_PLATES_PETNAMESONLY"] is not None, "pets checkbox in the panel")
check(G.SETTINGS["FOREVERPLATES_PLATES_FRIENDNAMEALPHA"] is not None, "opacity slider in the panel")
# the game switches the ally to name-only and lays it out again
uf("nameplate3").showOnlyName = True
uf("nameplate3").UpdateAnchors(uf("nameplate3"))
p3 = points("nameplate3")
check(len(p3) == 1 and p3[0][0] == "BOTTOM" and p3[0][2] == "TOP" and p3[0][3] == 0 and p3[0][4] == 2, "name-only ally: one point, centred above, not cut")
L.execute("PLATES.mouseover = PLATES.nameplate3; UNITS.mouseover = UNITS.nameplate3")
G.PRINTS = L.table()
G.SlashCmdList.FOREVERPLATES("debug")
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
check(G.SETTINGS["FOREVERPLATES_HEALTH_FORMAT"] is not None and G.SETTINGS["FOREVERPLATES_HEALTH_DECIMALS"] is not None, "format settings in the panel")
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
check(G.SETTINGS["FOREVERPLATES_THREAT_WARN"] is not None and G.SETTINGS["FOREVERPLATES_THREAT_WARNFROM"] is not None, "aggro warning settings in the panel")

# ---- settings pages
pages = list(G.SETTINGS.pages.values())
check(pages == ["Враги", "Союзники", "Полоса заклинаний", "Эффекты", "Видимость", "Угроза", "Добивание"], "settings split into pages: " + ", ".join(pages))
S = G.SETTINGS
check(S["FOREVERPLATES_PROFILE_PRESET"].page == "Forever Plates" and S["FOREVERPLATES_NATIVE_MANAGE"].page == "Forever Plates", "preset and general on the main page")
check(S["FOREVERPLATES_ENEMYTEXT_IDLE"].page == "Враги" and S["FOREVERPLATES_INFO_QUEST"].page == "Враги", "enemy numbers and quest marker on Enemies")
check(S["FOREVERPLATES_NATIVE_FRIENDNAMESONLY"].page == "Союзники" and S["FOREVERPLATES_PLATES_PETNAMESONLY"].page == "Союзники", "ally look on Allies")
check(S["FOREVERPLATES_CAST_TIMER"].page == "Полоса заклинаний" and S["FOREVERPLATES_CAST_INTERRUPTREADY"].page == "Полоса заклинаний", "cast extras on Cast bar")
check(S["FOREVERPLATES_AURAS_PURGE"].page == "Эффекты" and S["FOREVERPLATES_NATIVE_NPCBUFFS"].page == "Эффекты", "aura rows and game auras on Auras")
check(S["FOREVERPLATES_FADE_RANGE"].page == "Видимость" and S["FOREVERPLATES_NATIVE_STACKENEMIES"].page == "Видимость", "fading and stacking on Visibility")
check(S["FOREVERPLATES_THREAT_WARN"].page == "Угроза" and S["FOREVERPLATES_KILLZONE_ENABLED"].page == "Добивание", "threat and execute pages")

# ---- game options left to the game until changed
check(cv["nameplateShowEnemyMinions"] == "1" and cv["nameplateShowEnemyMinus"] == "0" and cv["nameplateSimplifiedTypes"] == "3", "minion/minor options untouched until changed")
check(S["FOREVERPLATES_NATIVE_ENEMYMINIONS"].get() is True and S["FOREVERPLATES_NATIVE_ENEMYMINUS"].get() is False and S["FOREVERPLATES_NATIVE_SMALLMINUS"].get() is True, "panel shows the game's current values")
S["FOREVERPLATES_NATIVE_ENEMYMINUS"].set(True)
S["FOREVERPLATES_NATIVE_SMALLMINIONS"].set(False)
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
L.execute("UNITS.nameplate1.quest = false")
G.FireEvent("QUEST_REMOVED"); G.RunTimers()
check(not q1.shown, "quest done: marker gone")
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
for k in ("FOREVERPLATES_ENEMYTEXT_IDLE", "FOREVERPLATES_ENEMYTEXT_MOUSEOVER", "FOREVERPLATES_ENEMYTEXT_TARGET", "FOREVERPLATES_PLATES_ENEMYFULLNAMES"):
    check(G.SETTINGS[k] is not None, f"setting {k} in the panel")
ns.Set("plates.friendHealthText", True)
check(all(t.alpha == 1 and t.width == 0 and t.wordWrap is True for t in texts("nameplate3")), "toggle shows health text on allies again (auto width, wrap restored)")
ns.Set("plates.friendHealthText", False)
check(all(t.alpha == 0 for t in texts("nameplate3")), "toggle hides it again")

# minimap button
mb = [f for f in G.ALL_FRAMES.values() if f.name == "ForeverPlatesMinimapButton"]
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
G.ForeverPlates_OnAddonCompartmentClick()
check(G.SETTINGS.opened == 42, "addon compartment entry opens the settings")
check(G.SETTINGS["FOREVERPLATES_PLATES_FRIENDHEALTHTEXT"] is not None and G.SETTINGS["FOREVERPLATES_UI_MINIMAP"] is not None, "new checkboxes in the settings panel")

# changing settings
ns.Set("auras.mineSize", 28)
check(b.width == 28, "icon size change restyles existing buttons")
check(c1.groups["mine"].layout.elementWidth == 28, "icon size change updates group layout")
ns.Set("auras.timer", False)
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
G.SlashCmdList.FOREVERPLATES("status")
check(any("412" in G.PRINTS[i] and "Слово Тьмы: Смерть" in G.PRINTS[i] and "618" in G.PRINTS[i] for i in range(1, len(G.PRINTS) + 1)), "/fpl status shows the threshold, its source and the crit value")
ns.Set("killzone.critMult", 200)
check(cz1[0].value == 824, "crit damage 200% -> 824")
ns.Set("killzone.crit", False)
check(not cz1[0].shown and kz1[0].shown, "crit zone can be turned off")
ns.Set("killzone.crit", True); ns.Set("killzone.critMult", 150)
pn = ns.ParseSpellNumber
check(pn("inflicts 1,234 to 1,400 Shadow damage") == 1234 and pn("наносит от 450 до 522 ед.") == 450 and pn("$s1 ед. урона") is None and pn("12\u00a0345 ед.") == 12345 and pn("Наносит 350. Затем 12") == 350, "description number parsing")
G.SlashCmdList.FOREVERPLATES("kz 420")
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

# proxy settings round trip
s = S["FOREVERPLATES_NATIVE_HEALTHVALUE"]
s.set(False)
check(not bit("nameplateInfoDisplay", 2) and s.get() is False, "checkbox proxy writes override and CVar")
slider = S["FOREVERPLATES_AURAS_MINEMAX"]
slider.set(4.4)
check(ns.Get("auras.mineMax") == 4 and c1.groups["mine"].max == 4, "slider rounds to integer and updates max icons")

# reset & presets
G.SlashCmdList.FOREVERPLATES("reset")
check(ns.CountOverrides() == 0 and bit("nameplateInfoDisplay", 2) and ns.Get("killzone.value") == 350 and ns.Get("killzone.mode") == "spell" and kz1[0].value == 412, "/fpl reset restores preset values (spell mode, 412)")
for k in ("FOREVERPLATES_KILLZONE_COMBATONLY", "FOREVERPLATES_KILLZONE_SPELLBONUS"):
    check(S[k] is not None, f"setting {k} in the panel")
check([d.value for d in S["FOREVERPLATES_KILLZONE_MODE"].getOptions().values()] == ["spell", "value", "percent"], "zone type dropdown: spell, value, percent")
G.SlashCmdList.FOREVERPLATES("preset base")
check(ns.GetActivePreset() == "BASE" and not kz1[0].shown and not cz1[0].shown, "base preset turns the kill zone off")
G.SlashCmdList.FOREVERPLATES("preset auto")
check(ns.GetActivePreset() == "PRIEST" and kz1[0].shown, "auto brings the priest preset back")
G.SlashCmdList.FOREVERPLATES("preset nope")
check(ns.db.preset == "auto", "unknown preset is rejected")

# removal
G.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
check(not c1.enabled and not c1.shown and not kz1[0].shown, "removed plate: container disabled, zone hidden")
G.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate3")
check(all(t.alpha == 1 and t.width == 0 and t.wordWrap is True for t in texts("nameplate3")), "removed friendly plate gets its text back (alpha, width, wrap) before reuse")
check(len(points("nameplate3")) == 2, "removed friendly plate gets the game's name points back before reuse")
check(uf("nameplate3").name.alpha == 1, "removed friendly plate gets full name opacity back before reuse")

# game defaults
G.SlashCmdList.FOREVERPLATES("gamedefaults")
check(cv["nameplateShowOffscreen"] == "1" and cv["nameplateInfoDisplay"] == "0" and ns.Get("native.manage") is False, "/fpl gamedefaults restores game values and stops managing")
before = G.CVAR_SETS
ns.Set("native.healthValue", False)
check(G.CVAR_SETS == before, "with management off the addon leaves CVars alone")
check(len(G.ERRORS) == 0, "no errors at the end: " + "; ".join(G.ERRORS[i] for i in range(1, len(G.ERRORS) + 1)))

# ---------------------------------------------------------------- warrior, english, old stacking CVar, no LOS CVar
old = 'CVARS = { nameplateInfoDisplay = "0", nameplateCastBarDisplay = "0", nameplateThreatDisplay = "0", nameplateEnemyNpcAuraDisplay = "0", nameplateEnemyPlayerAuraDisplay = "0", nameplateFriendlyPlayerAuraDisplay = "0", nameplateMotion = "0", nameplateShowAll = "0", nameplateShowOffscreen = "1", nameplateShowFriendlyNpcs = "1", nameplateStyle = "0" }'
L2, ns2 = new_runtime(locale="enUS", player_class="WARRIOR", cvars_override=old)
G2 = L2.globals()
G2.FireEvent("ADDON_LOADED", "ForeverPlates"); G2.FireEvent("PLAYER_LOGIN"); G2.FireEvent("PLAYER_ENTERING_WORLD"); G2.RunTimers()
check(ns2.GetActivePreset() == "BASE", "class without a preset uses BASE")
check(G2.CVARS["nameplateMotion"] == "1", "falls back to nameplateMotion when stacking types are missing")
check(G2.SETTINGS["FOREVERPLATES_NATIVE_LOSFADE"] is None, "LOS slider hidden when the client lacks the CVar")
check(ns2.L.MINE == "My debuffs with timers", "English strings on non-Russian clients")
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
ns2.Set("plates.friendHealthText", True)
check(len(pn2("nameplate2")) == 2, "Modern, ally with numbers shown: the game's layout (name stops before the numbers)")
ns2.Set("plates.friendHealthText", False)
check(len(pn2("nameplate2")) == 1, "numbers hidden again: name free again")
check(len(pn2("nameplate1")) == 1, "Modern, enemy normally (no numbers): name free")
L2.execute("PLATES.target = PLATES.nameplate1"); G2.FireEvent("PLAYER_TARGET_CHANGED")
check(len(pn2("nameplate1")) == 2, "Modern, enemy in target (numbers shown): the game's layout, name stops before them")
L2.execute("PLATES.target = nil"); G2.FireEvent("PLAYER_TARGET_CHANGED")
check(len(pn2("nameplate1")) == 1, "target cleared: name free again")
check(len(G2.ERRORS) == 0, "no errors for warrior run")

print()
print("FAILURES:", len(failures))
sys.exit(1 if failures else 0)
