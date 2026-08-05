local GSE = GSE
local L = GSE.L

local Statics = GSE.Static

--- Strip a name down to comparable characters.
--    Ascension's data files spell trees as identifiers ("BeastMastery") while
--    the client reports them for display ("Beast Mastery"), so neither side can
--    be compared verbatim.
local function normaliseKey(str)
  if not str then
    return ""
  end
  return (string.gsub(string.upper(str), "[^A-Z0-9]", ""))
end

--- Read one talent tab, normalising the two GetTalentTabInfo signatures.
--    Stock 3.3.5a returns  name, icon, pointsSpent, background, previewPoints
--    Ascension returns     id, name, description, icon, points, background,
--                          previewPoints, isUnlocked
--    The shape is detected from the type of the first return value rather than
--    assumed, so this works on both clients. Reading the stock layout on
--    Ascension used to hand a description string to a numeric comparison and
--    error out, which left the addon with no spec at all.
--    Returns: name, icon, pointsSpent, tabId
local function getTalentTab(tabIndex, talentGroup)
  if not GetTalentTabInfo then
    return nil
  end
  local ok, a, b, c, d, e = pcall(GetTalentTabInfo, tabIndex, false, false, talentGroup)
  if not ok or a == nil then
    return nil
  end
  if type(a) == "number" then
    -- Ascension: a=id, b=name, c=description, d=icon, e=points
    return b, d, (tonumber(e) or 0), a
  end
  -- Stock 3.3.5a: a=name, b=icon, c=pointsSpent
  return a, b, (tonumber(c) or 0), nil
end

--- Lookup tables built from Statics.wotlkSpecIDList, which holds entries in the
--    form "Tree - Class" plus bare class names. Built on first use because
--    AscensionData.lua has to be loaded before it can be read.
local specByTreeAndClass, specByTree
local function buildSpecLookups()
  if specByTreeAndClass then
    return
  end
  specByTreeAndClass, specByTree = {}, {}
  for id, label in pairs(Statics.wotlkSpecIDList or {}) do
    local sep = string.find(label, " - ", 1, true)
    if sep then
      local tree = string.sub(label, 1, sep - 1)
      local class = string.sub(label, sep + 3)
      specByTreeAndClass[normaliseKey(tree) .. "|" .. normaliseKey(class)] = id
      local treeKey = normaliseKey(tree)
      -- A tree name such as "Frost" belongs to several classes; keep the lowest
      -- ID so the class-less fallback is at least deterministic.
      if not specByTree[treeKey] or id < specByTree[treeKey] then
        specByTree[treeKey] = id
      end
    end
  end
end

--- Return the characters current spec id
function GSE.GetSpecialization()
  return GSE.GetCurrentSpecID()
end

--- Return the tree the character has invested the most points in.
--    Returns: specID, treeName, treeIcon. specID is always a number so callers
--    can index GSELibrary with it; 0 (Global) is the fallback.
function GSE.GetCurrentSpecID()
  buildSpecLookups()

  local activeGroup = 1
  if GetActiveTalentGroup then
    local ok, group = pcall(GetActiveTalentGroup, false, false)
    if ok then
      activeGroup = tonumber(group) or 1
    end
  end

  local numTabs = 0
  if GetNumTalentTabs then
    local ok, tabs = pcall(GetNumTalentTabs, false, false)
    if ok then
      numTabs = tonumber(tabs) or 0
    end
  end

  local bestName, bestIcon, bestPoints
  for tab = 1, numTabs do
    local name, icon, points = getTalentTab(tab, activeGroup)
    if name and (not bestPoints or points > bestPoints) then
      bestName, bestIcon, bestPoints = name, icon, points
    end
  end

  if not bestName then
    -- No usable talent information: fall back to the class so sequences at
    -- least group under something meaningful.
    local classID = GSE.GetCurrentClassID()
    return classID, (Statics.wotlkClassIDList[classID] or Statics.Global), nil
  end

  local _, className = UnitClass("player")
  local specID = specByTreeAndClass[normaliseKey(bestName) .. "|" .. normaliseKey(className)]
    or specByTree[normaliseKey(bestName)]

  if not specID then
    local classID = GSE.GetCurrentClassID()
    return classID, bestName, bestIcon
  end

  return specID, bestName, bestIcon
end

--- Return the characters class id.
--    Ascension is classless, but UnitClass still reports the base template and
--    that is what previously saved macros are filed under, so it stays the
--    primary source. Hero-class and Reborn IDs exist in the tables so a
--    sequence can be assigned to one by hand in the editor.
--    Always returns a number - returning "" here used to file macros under an
--    empty GSELibrary key where nothing could find them again.
function GSE.GetCurrentClassID()
  local classDisplayName, classToken = UnitClass("player")
  local wanted = { normaliseKey(classToken), normaliseKey(classDisplayName) }

  for id, name in pairs(Statics.wotlkClassIDList or {}) do
    local key = normaliseKey(name)
    for _, w in ipairs(wanted) do
      if w ~= "" and key == w then
        return id
      end
    end
  end

  -- Nothing matched the base class: try the dominant talent tree, which on
  -- Ascension is often named after a hero class (e.g. "Necromancer").
  local activeGroup = 1
  if GetActiveTalentGroup then
    local ok, group = pcall(GetActiveTalentGroup, false, false)
    if ok then
      activeGroup = tonumber(group) or 1
    end
  end
  local numTabs = 0
  if GetNumTalentTabs then
    local ok, tabs = pcall(GetNumTalentTabs, false, false)
    if ok then
      numTabs = tonumber(tabs) or 0
    end
  end
  for tab = 1, numTabs do
    local name = getTalentTab(tab, activeGroup)
    if name then
      local key = normaliseKey(name)
      for id, className in pairs(Statics.wotlkClassIDList or {}) do
        if normaliseKey(className) == key then
          return id
        end
      end
    end
  end

  return 0
end

--- Return the characters class id
function GSE.GetCurrentClassNormalisedName()
  local _, classnormalisedname = UnitClass("player")
  return string.upper(classnormalisedname or "")
end

--- Map a spec ID back to the class ID that owns it.
function GSE.GetClassIDforSpec(specid)
  specid = tonumber(specid)
  if not specid then
    return 0
  end

  -- Class-level IDs are their own answer.
  if Statics.wotlkClassIDList and Statics.wotlkClassIDList[specid] then
    return specid
  end

  local label = Statics.wotlkSpecIDList and Statics.wotlkSpecIDList[specid]
  if not label then
    return 0
  end

  local sep = string.find(label, " - ", 1, true)
  if not sep then
    return 0
  end

  local class = normaliseKey(string.sub(label, sep + 3))
  for id, name in pairs(Statics.wotlkClassIDList or {}) do
    if normaliseKey(name) == class then
      return id
    end
  end

  return 0
end

--- Icon for a class ID.
--    Only the twelve base classes have a distinct icon; Ascension's hero and
--    Reborn classes fall back to a question mark rather than returning nil,
--    which would leave an empty button in the remote macro browser.
local classIcons = {
  [0] = "Interface\\Icons\\INV_MISC_QUESTIONMARK", -- Global
  [1] = "Interface\\Icons\\inv_sword_27", -- Warrior
  [2] = "Interface\\Icons\\ability_thunderbolt", -- Paladin
  [3] = "Interface\\Icons\\inv_weapon_bow_07", -- Hunter
  [4] = "Interface\\Icons\\inv_throwingknife_04", -- Rogue
  [5] = "Interface\\Icons\\INV_Staff_30", -- Priest
  [6] = "Interface\\Icons\\Spell_Deathknight_ClassIcon", -- Death Knight
  [7] = "Interface\\Icons\\Spell_Nature_BloodLust", -- Shaman
  [8] = "Interface\\Icons\\INV_Staff_13", -- Mage
  [9] = "Interface\\Icons\\Spell_Nature_FaerieFire", -- Warlock
  [10] = "Interface\\Icons\\Spell_Holy_FistOfJustice", -- Monk
  [11] = "Interface\\Icons\\INV_Misc_MonsterClaw_04", -- Druid
  [12] = "Interface\\Icons\\INV_Weapon_Glave_01", -- Demon Hunter
}

function GSE.GetClassIcon(classid)
  return classIcons[tonumber(classid) or -1] or "Interface\\Icons\\INV_MISC_QUESTIONMARK"
end

--- Check if the specID provided matches the players current class.
function GSE.isSpecIDForCurrentClass(specID)
  specID = tonumber(specID)
  if not specID then
    return false
  end
  local currentClassID = GSE.GetCurrentClassID()
  return specID == currentClassID or GSE.GetClassIDforSpec(specID) == currentClassID
end

--- Names offered by the editor's Specialisation/Class dropdown.
--    Restricted to Statics.ActiveSpecIDs, which the generator fills for the
--    configured Ascension game mode - listing all 145 trees made the dropdown
--    unusable. Everything outside the active set stays resolvable, so a sequence
--    carrying a spec ID from another mode keeps working; it just is not offered
--    as a new choice. Falls back to offering everything if the table is absent.
function GSE.GetSpecNames()
  local keyset = {}
  local active = Statics.ActiveSpecIDs
  local restrict = not GSE.isEmpty(active)

  for id, v in pairs(Statics.wotlkSpecIDList or {}) do
    if not restrict or active[id] then
      keyset[v] = v
    end
  end
  return keyset
end

--- Returns the Character Name in the form Player@server
function GSE.GetCharacterName()
  return GetUnitName("player", true) .. '@' .. GetRealmName()
end

--- Returns the current Talent Selections as a string
function GSE.GetCurrentTalents()
  local talents = ""
  for talentTier = 1, 7 do
    talents = talents .. ("?" .. ",")
  end
  return talents
end


--- Experimental attempt to load a WeakAuras string.
function GSE.LoadWeakauras(str)
  local WeakAuras = WeakAuras

  if WeakAuras then
    WeakAuras.ImportString(str)
  end
end
