"""Load the addon's data and character files under a mock WoW API and assert
the class/spec plumbing behaves.

This does not need the game. It stands up just enough of the 3.3.5a API for
Statics.lua, AscensionData.lua and CharacterFunctions.lua to load, then checks
the parts that were rewritten for Ascension - most importantly that spec
detection copes with BOTH GetTalentTabInfo signatures, and that the class ID is
always a number.

Requires: pip install lupa

Usage:
    python tools/smoke-test.py
"""

import sys
from pathlib import Path

try:
    import lupa
except ImportError:
    sys.exit("lupa is not installed. Run: python -m pip install lupa")

REPO = Path(__file__).resolve().parent.parent

# Minimal stand-ins for the addon framework and the client API. Talent data is
# driven by the TALENT_TABS / TALENT_SIGNATURE globals so a test can reshape the
# character between calls.
PREAMBLE = r"""
GSE = {}
GSE.Static = {}
GSE.L = setmetatable({}, { __index = function(_, k) return k end })
GSE.isEmpty = function(v)
  if v == nil then return true end
  if type(v) == "string" and v == "" then return true end
  if type(v) == "table" and next(v) == nil then return true end
  return false
end
GSE.Print = function() end
GSE.PrintDebugMessage = function() end
GSE.TranslatorLanguageTables = { KEY = {}, HASH = {}, SHADOW = {} }

GSEOptions = {}

UNIT_CLASS_DISPLAY = "Warrior"
UNIT_CLASS_TOKEN = "WARRIOR"
TALENT_TABS = {}
TALENT_SIGNATURE = "ascension"

function UnitClass(_) return UNIT_CLASS_DISPLAY, UNIT_CLASS_TOKEN end
function GetActiveTalentGroup() return 1 end
function GetNumTalentTabs() return #TALENT_TABS end
function GetTalentTabInfo(index)
  local tab = TALENT_TABS[index]
  if not tab then return nil end
  if TALENT_SIGNATURE == "ascension" then
    -- id, name, description, icon, points, background, previewPoints, isUnlocked
    return index * 100, tab.name, "a description", tab.icon, tab.points, "bg", 0, true
  end
  -- stock 3.3.5a: name, icon, pointsSpent, background, previewPointsSpent
  return tab.name, tab.icon, tab.points, "bg", 0
end
function GetUnitName() return "Tester" end
function GetRealmName() return "TestRealm" end
function GetSpellInfo() return nil end
function GetSpellCooldown() return 0, 0, 0 end
function GetAddOnMetadata() return "test" end
function GetLocale() return "enUS" end
"""

LOAD_ORDER = [
    "GSE/API/Statics.lua",
    "GSE/API/AscensionData.lua",
    "GSE/API/CharacterFunctions.lua",
]

SPELL_TABLES = [
    "GSE/Localization/enUS.lua",
    "GSE/Localization/enUSHash.lua",
    "GSE/Localization/enUSSHADOW.lua",
]

failures = []
checks = 0


def check(label, condition, detail=""):
    global checks
    checks += 1
    if condition:
        print(f"  ok    {label}")
    else:
        print(f"  FAIL  {label}" + (f"  ({detail})" if detail else ""))
        failures.append(label)


def main():
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PREAMBLE)

    print("loading addon files...")
    for rel in LOAD_ORDER + SPELL_TABLES:
        source = (REPO / rel).read_text(encoding="utf-8")
        try:
            lua.execute(source)
        except lupa.LuaError as exc:
            sys.exit(f"FAILED loading {rel}: {exc}")
        print(f"  loaded {rel}")

    g = lua.globals()
    GSE = g.GSE
    Statics = GSE.Static

    print("\nstatics:")
    classes = Statics.wotlkClassIDList
    specs = Statics.wotlkSpecIDList
    n_classes = sum(1 for _ in classes.items())
    n_specs = sum(1 for _ in specs.items())
    check("class table populated", n_classes > 30, f"{n_classes} entries")
    check("spec table populated", n_specs > 100, f"{n_specs} entries")
    check("Global is class 0", classes[0] == "Global")
    check("base WotLK IDs preserved", classes[1] == "Warrior" and classes[8] == "Mage" and classes[11] == "Druid")
    check("hero classes present", classes[25] == "Necromancer" and classes[35] == "Tinker")
    check("Reborn classes clear the spec ID band", classes[301] == "RebornWarrior")
    check("retail spec IDs preserved", specs[64] == "Frost - Mage" and specs[71] == "Arms - Warrior")
    check("SpecIDList aliases spec table", Statics.SpecIDList[64] == "Frost - Mage")
    check("SpecIDHashList inverted", Statics.SpecIDHashList["Frost - Mage"] == 64)

    # A class ID must never collide with a spec ID: both live in one table.
    overlap = [cid for cid, _ in classes.items()
               if cid != 0 and specs[cid] is not None and specs[cid] != classes[cid]]
    check("no class/spec ID collision", not overlap, f"overlapping: {overlap[:5]}")

    print("\nspec detection - Ascension GetTalentTabInfo signature:")
    g.TALENT_SIGNATURE = "ascension"
    g.UNIT_CLASS_DISPLAY, g.UNIT_CLASS_TOKEN = "Mage", "MAGE"
    lua.execute("""
      TALENT_TABS = {
        { name = "Arcane", icon = "i1", points = 11 },
        { name = "Fire",   icon = "i2", points = 3  },
        { name = "Frost",  icon = "i3", points = 51 },
      }
    """)
    spec_id, spec_name, spec_icon = GSE.GetCurrentSpecID()
    check("picks the most-invested tree", spec_name == "Frost", f"got {spec_name}")
    check("resolves to Frost - Mage (64)", spec_id == 64, f"got {spec_id}")
    check("returns the tree icon", spec_icon == "i3", f"got {spec_icon}")
    check("spec ID is numeric", isinstance(spec_id, (int, float)), f"got {type(spec_id)}")

    print("\nspec detection - stock 3.3.5a signature:")
    g.TALENT_SIGNATURE = "stock"
    spec_id, spec_name, _ = GSE.GetCurrentSpecID()
    check("still picks the most-invested tree", spec_name == "Frost", f"got {spec_name}")
    check("still resolves to 64", spec_id == 64, f"got {spec_id}")

    print("\nspec detection - Ascension hero-class tree:")
    g.TALENT_SIGNATURE = "ascension"
    g.UNIT_CLASS_DISPLAY, g.UNIT_CLASS_TOKEN = "Death Knight", "DEATHKNIGHT"
    lua.execute("""
      TALENT_TABS = {
        { name = "Death",     icon = "d1", points = 30 },
        { name = "Animation", icon = "d2", points = 11 },
        { name = "Rime",      icon = "d3", points = 5  },
      }
    """)
    spec_id, spec_name, _ = GSE.GetCurrentSpecID()
    check("hero tree name resolves", spec_name == "Death", f"got {spec_name}")
    check("hero tree maps to a spec ID", isinstance(spec_id, (int, float)) and spec_id > 0, f"got {spec_id}")
    resolved = specs[spec_id]
    check("maps into a Necromancer tree", resolved is not None and "Necromancer" in resolved, f"got {resolved}")

    print("\nspec detection - display names with spaces:")
    g.UNIT_CLASS_DISPLAY, g.UNIT_CLASS_TOKEN = "Hunter", "HUNTER"
    lua.execute("""TALENT_TABS = { { name = "Beast Mastery", icon = "h1", points = 40 } }""")
    spec_id, _, _ = GSE.GetCurrentSpecID()
    check("'Beast Mastery' matches data's 'BeastMastery'", spec_id == 253, f"got {spec_id}")

    print("\nno talent data at all:")
    lua.execute("TALENT_TABS = {}")
    g.UNIT_CLASS_DISPLAY, g.UNIT_CLASS_TOKEN = "Rogue", "ROGUE"
    spec_id, spec_name, _ = GSE.GetCurrentSpecID()
    check("falls back to a number, not nil", isinstance(spec_id, (int, float)), f"got {spec_id!r}")
    check("falls back to the class (Rogue = 4)", spec_id == 4, f"got {spec_id}")
    check("still returns a usable name", bool(spec_name), f"got {spec_name!r}")

    print("\nclass detection:")
    for display, token, expected in [
        ("Warrior", "WARRIOR", 1),
        ("Death Knight", "DEATHKNIGHT", 6),
        ("Druid", "DRUID", 11),
    ]:
        g.UNIT_CLASS_DISPLAY, g.UNIT_CLASS_TOKEN = display, token
        got = GSE.GetCurrentClassID()
        check(f"{display} -> {expected}", got == expected, f"got {got}")

    g.UNIT_CLASS_DISPLAY, g.UNIT_CLASS_TOKEN = "Ascendant", "ASCENDANT"
    lua.execute("TALENT_TABS = {}")
    got = GSE.GetCurrentClassID()
    check("unknown class returns 0, never ''", got == 0, f"got {got!r}")
    check("unknown class result is numeric", isinstance(got, (int, float)), f"got {type(got)}")

    # An unrecognised class used to fall through as "", so macros were filed
    # under GSELibrary[""] where nothing could find them again.
    lua.execute("""TALENT_TABS = { { name = "Necromancer", icon = "n", points = 20 } }""")
    got = GSE.GetCurrentClassID()
    check("unknown class falls back to hero tree name", got == 25, f"got {got}")

    print("\nspec -> class mapping:")
    for spec, expected in [(64, 8), (71, 1), (253, 3), (105, 11), (0, 0)]:
        got = GSE.GetClassIDforSpec(spec)
        check(f"spec {spec} -> class {expected}", got == expected, f"got {got}")
    check("garbage spec is handled", GSE.GetClassIDforSpec("nonsense") == 0)
    check("nil spec is handled", GSE.GetClassIDforSpec(None) == 0)

    print("\nclass icons:")
    check("base class has an icon", "inv_sword_27" in GSE.GetClassIcon(1))
    check("hero class falls back, not nil", GSE.GetClassIcon(25) is not None)
    check("garbage ID falls back, not nil", GSE.GetClassIcon("x") is not None)

    print("\nspell tables:")
    key = GSE.TranslatorLanguageTables["KEY"]["enUS"]
    hash_t = GSE.TranslatorLanguageTables["HASH"]["enUS"]
    shadow = GSE.TranslatorLanguageTables["SHADOW"]["enUS"]
    n_key = sum(1 for _ in key.items())
    n_hash = sum(1 for _ in hash_t.items())
    check("key table has Ascension-scale content", n_key > 3500, f"{n_key} entries")
    check("hash table populated", n_hash > 3000, f"{n_hash} entries")

    # Every hash ID must resolve in the key table or TranslateSpell reports the
    # spell as unknown.
    missing = [(name, sid) for name, sid in hash_t.items() if key[sid] is None]
    check("every hash ID resolves in key table", not missing, f"{len(missing)} missing e.g. {missing[:3]}")

    check("Ascension-corrected name for 99", key[99] == "Demoralizing Roar", f"got {key[99]}")
    check("Ascension-corrected name for 1719", key[1719] == "Recklessness", f"got {key[1719]}")
    check("retail-only name is gone", hash_t["Incapacitating Roar"] is None)
    check("high-ID custom spell present", key[1191234] == "Brilliance Aura", f"got {key[1191234]}")
    check("shadow table is lower-cased", shadow["frostbolt"] is not None)
    check("shadow maps to a real ID", key[shadow["power word: shield"]] == "Power Word: Shield")

    print(f"\n{checks} checks, {len(failures)} failed.")
    if failures:
        for f in failures:
            print(f"  - {f}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
