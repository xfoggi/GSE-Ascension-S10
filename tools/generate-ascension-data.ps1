<#
.SYNOPSIS
    Generates GSE's spell translation tables and Ascension class/spec statics
    from the live Project Ascension client data shipped with the launcher.

.DESCRIPTION
    GSE was originally built for retail WoW and its spell tables came from
    GSE 2.x (Legion-era). On Project Ascension those tables are wrong in two
    ways: most Ascension abilities are missing entirely, and a number of spell
    IDs carry retail names that Ascension never used (e.g. 99 is
    "Demoralizing Roar" on Ascension, not retail's "Incapacitating Roar").
    A macro written against the wrong name silently fails to translate.

    This script rebuilds, from CharacterAdvancementData.json:
      GSE/Localization/enUS.lua        spellID  -> spell name
      GSE/Localization/enUSHash.lua    name     -> spellID
      GSE/Localization/enUSSHADOW.lua  lowercase name -> spellID
      GSE/API/AscensionData.lua        class / spec / tab statics

    Re-run it after every Ascension patch or season to pick up new content.

.PARAMETER ContentPath
    Ascension launcher Content directory holding CharacterAdvancementData.json.

.PARAMETER RepoPath
    Root of the GSE-Ascension checkout to write into.

.EXAMPLE
    .\tools\generate-ascension-data.ps1
#>
[CmdletBinding()]
param(
  [string]$ContentPath = "C:\Ascension\Launcher\resources\ascension-live\Data\Content",
  [string]$RepoPath = (Split-Path -Parent $PSScriptRoot),

  # Which game modes' trees to offer in the spec dropdown. The launcher knows
  # four: wrath (the ten WotLK classes), classless (Ascension's hero classes),
  # reborn (the Reborn trees) and coa (Conquest of Azeroth). The data files carry
  # a Realms bitmask per record but nothing maps a bit to a named realm, so this
  # cannot be detected - it is a deliberate choice.
  #
  # Only tree entries are filtered. Every class keeps its class-level entry, so
  # sequences already saved under any class ID still resolve and still get a
  # readable heading in the viewer.
  [ValidateSet('wrath', 'classless', 'reborn', 'coa')]
  [string[]]$GameModes = @('classless', 'coa')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Web.Extensions

$cadPath = Join-Path $ContentPath 'CharacterAdvancementData.json'
if (-not (Test-Path $cadPath)) {
  throw "CharacterAdvancementData.json not found at '$cadPath'. Pass -ContentPath pointing at your launcher's Data\Content folder."
}

Write-Host "Reading $cadPath ..." -ForegroundColor Cyan
$ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$ser.MaxJsonLength = [int]::MaxValue
$ser.RecursionLimit = 200
$cad = $ser.DeserializeObject([System.IO.File]::ReadAllText($cadPath))
Write-Host ("  {0} advancement records" -f $cad.Count)

# ---------------------------------------------------------------------------
# Spell tables
# ---------------------------------------------------------------------------
# Only Ability and TalentAbility records are castable, so only those belong in
# the macro translator. Trait and Talent records are passive nodes: they carry
# ~17k further spell IDs, and 255 of their names duplicate the name of a real
# ability (Aimed Shot, Adrenaline Rush, Arcane Power, ...). Including them would
# let a passive win the name->ID hash entry, so "/cast Aimed Shot" would resolve
# to a passive's ID and the macro would quietly stop firing.
$CASTABLE = @{ 'Ability' = $true; 'TalentAbility' = $true }

function ConvertTo-LuaString {
  param([string]$Value)
  $Value.Replace('\', '\\').Replace('"', '\"')
}

$nameById = @{}   # spellID -> name  (every castable ID)
$skippedNoName = 0

# Lua tables are case-sensitive and Ascension ships names that differ only in
# capitalisation ("Wild Magic" vs "Wild MAGIC"), so every map keyed by a spell
# name has to compare ordinally. A default PowerShell hashtable folds the two
# into one entry, which then emits one casing against the other's spell ID.
function New-OrdinalMap { New-Object System.Collections.Hashtable -ArgumentList ([System.StringComparer]::Ordinal) }
$idsByName = New-OrdinalMap  # name -> candidate spell IDs, newest record first

# Sort by record ID so every choice below is stable across runs regardless of
# hashtable ordering.
$castable = @($cad | Where-Object { $CASTABLE[[string]$_["Type"]] }) |
  Sort-Object { [int]$_["ID"] }

# Ascension keeps superseded advancement records alongside the live ones, so
# several records claim the same spell ID under different names. They come in
# generations that only the record ID separates: Realms=0, then Realms=6144 with
# the old thematic tabs, then the current Tab="Class" trees. Spell 801576 is
# "Ancestor's Fury" in record 18845 and "Ancestral Strike" in record 32076 - the
# latter is what the client shows. The newest record therefore owns the name,
# which iterating in ascending ID order and letting the last write win gives us.
foreach ($rec in $castable) {
  $name = [string]$rec["Name"]
  if ([string]::IsNullOrWhiteSpace($name)) { $skippedNoName++; continue }

  $spellIds = @($rec["Spells"])
  if ($spellIds.Count -eq 0) { continue }

  $ids = @($spellIds | ForEach-Object { [int]$_ })
  foreach ($id in $ids) { $nameById[$id] = $name }

  # Prepend, so the newest record's IDs are considered first while each record
  # keeps its own rank order.
  if ($idsByName.ContainsKey($name)) { $idsByName[$name] = @($ids) + $idsByName[$name] }
  else { $idsByName[$name] = $ids }
}

# GSE.TranslateSpell resolves a name to an ID through the hash table and then
# writes back whatever the key table calls that ID, so the two have to
# round-trip. A name pointing at an ID the key table names differently does not
# fail loudly - it silently rewrites the macro, which is how "/cast Ancestral
# Strike" used to come back from a save as "/cast Ancestor's Fury". So only
# accept an ID that maps back to this exact name, newest record first.
#
# A name with no such ID exists only on superseded records: every spell it once
# granted is now called something else. Leaving it out of the hash is the point -
# GSE.TranslateSpell then falls through to GetSpellInfo and passes the text
# through untouched (or flags it unknown), rather than renaming the player's
# spell to whatever supplanted it.
$idByName = New-OrdinalMap
$superseded = @()
foreach ($name in ($idsByName.Keys | Sort-Object)) {
  $pick = $null
  foreach ($id in $idsByName[$name]) {
    if ($nameById[$id] -ceq $name) { $pick = $id; break }
  }
  if ($null -ne $pick) { $idByName[$name] = $pick } else { $superseded += $name }
}

Write-Host ("  castable records: {0}  unique IDs: {1}  unique names: {2}" -f `
  $castable.Count, $nameById.Count, $idByName.Count) -ForegroundColor Green
if ($skippedNoName) { Write-Host ("  skipped (no name): {0}" -f $skippedNoName) -ForegroundColor DarkYellow }
if ($superseded.Count) {
  Write-Host ("  superseded names left out of the hash: {0}" -f $superseded.Count) -ForegroundColor DarkYellow
  foreach ($n in $superseded) { Write-Verbose ("    {0} -> now {1}" -f $n, $nameById[$idsByName[$n][0]]) }
}

$header = @"
-- GENERATED FILE - DO NOT EDIT BY HAND
-- Source : Project Ascension CharacterAdvancementData.json
-- Script : tools/generate-ascension-data.ps1
-- Regenerate after every Ascension patch/season.
"@

# --- enUS.lua : spellID -> name --------------------------------------------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine($header)
[void]$sb.AppendLine('local GSE = GSE')
[void]$sb.AppendLine('local Statics = GSE.Static')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('GSE.TranslatorLanguageTables[Statics.TranslationKey]["enUS"] = {')
foreach ($id in ($nameById.Keys | Sort-Object)) {
  [void]$sb.AppendLine(("`t[{0}] = `"{1}`"," -f $id, (ConvertTo-LuaString $nameById[$id])))
}
[void]$sb.AppendLine('}')
$enUS = $sb.ToString()

# --- enUSHash.lua : name -> spellID ---------------------------------------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine($header)
[void]$sb.AppendLine('local GSE = GSE')
[void]$sb.AppendLine('local Statics = GSE.Static')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('GSE.TranslatorLanguageTables[Statics.TranslationHash]["enUS"] = {')
foreach ($name in ($idByName.Keys | Sort-Object)) {
  [void]$sb.AppendLine(("`t[`"{0}`"] = {1}," -f (ConvertTo-LuaString $name), $idByName[$name]))
}
[void]$sb.AppendLine('}')
$enUSHash = $sb.ToString()

# --- enUSSHADOW.lua : lowercase name -> spellID ---------------------------
# Case-insensitive fallback for hand-written macros. Names that collapse to the
# same lowercase form keep the alphabetically first spelling's ID.
$shadow = @{}
foreach ($name in ($idByName.Keys | Sort-Object)) {
  $lower = $name.ToLowerInvariant()
  if (-not $shadow.ContainsKey($lower)) { $shadow[$lower] = $idByName[$name] }
}
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine($header)
[void]$sb.AppendLine('local GSE = GSE')
[void]$sb.AppendLine('local Statics = GSE.Static')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('GSE.TranslatorLanguageTables[Statics.TranslationShadow]["enUS"] = {')
foreach ($lower in ($shadow.Keys | Sort-Object)) {
  [void]$sb.AppendLine(("`t[`"{0}`"] = {1}," -f (ConvertTo-LuaString $lower), $shadow[$lower]))
}
[void]$sb.AppendLine('}')
$enUSShadow = $sb.ToString()

# ---------------------------------------------------------------------------
# Class / spec statics
# ---------------------------------------------------------------------------
# GSELibrary is keyed by class ID, so existing saved macros must keep resolving
# to the same key. The ten WotLK classes therefore keep their original IDs
# (and Monk/Demon Hunter take the retail 10/12 that GSE already reserved);
# Ascension's hero classes and Reborn trees get fresh IDs above them.
$BASE_CLASS_IDS = [ordered]@{
  'Warrior' = 1; 'Paladin' = 2; 'Hunter' = 3; 'Rogue' = 4; 'Priest' = 5
  'DeathKnight' = 6; 'Shaman' = 7; 'Mage' = 8; 'Warlock' = 9
  'Monk' = 10; 'Druid' = 11; 'DemonHunter' = 12
}

# Hero classes, alphabetical, from ID 20 up. Explicit so the IDs stay stable
# even if a future season adds or reorders classes in the source data.
$HERO_CLASS_IDS = [ordered]@{
  'Barbarian' = 20; 'Chronomancer' = 21; 'Cultist' = 22; 'Guardian' = 23
  'KnightOfXoroth' = 24; 'Necromancer' = 25; 'Primalist' = 26; 'Pyromancer' = 27
  'Ranger' = 28; 'Reaper' = 29; 'Runemaster' = 30; 'SonOfArugal' = 31
  'Starcaller' = 32; 'Stormbringer' = 33; 'SunCleric' = 34; 'Tinker' = 35
  'Venomancer' = 36; 'WitchDoctor' = 37; 'WitchHunter' = 38
}

# Reborn variants sit at 300 + the base class ID, so RebornWarrior is 301 and
# so on; RebornGeneral (class-wide Reborn content) takes the 300 slot itself.
# They deliberately clear the 62-267 band, which the retail spec IDs below
# occupy - class IDs and spec IDs share one table in wotlkSpecIDList, so an
# overlap would silently drop an entry.
$REBORN_BASE = 300
$SPECIAL_CLASS_IDS = [ordered]@{ 'RebornGeneral' = 300; 'ConquestOfAzeroth' = 320 }

$classIds = [ordered]@{}
foreach ($k in $BASE_CLASS_IDS.Keys) { $classIds[$k] = $BASE_CLASS_IDS[$k] }
foreach ($k in $HERO_CLASS_IDS.Keys) { $classIds[$k] = $HERO_CLASS_IDS[$k] }
foreach ($k in $BASE_CLASS_IDS.Keys) {
  $classIds["Reborn$k"] = $REBORN_BASE + $BASE_CLASS_IDS[$k]
}
foreach ($k in $SPECIAL_CLASS_IDS.Keys) { $classIds[$k] = $SPECIAL_CLASS_IDS[$k] }

# Retail spec IDs for the WotLK class/tree pairs, kept so sequences shared with
# or imported from other GSE builds still land in the right tree.
$BASE_SPEC_IDS = @{
  'Warrior|Arms' = 71; 'Warrior|Fury' = 72; 'Warrior|Protection' = 73
  'Paladin|Holy' = 65; 'Paladin|Protection' = 66; 'Paladin|Retribution' = 70
  'Hunter|BeastMastery' = 253; 'Hunter|Marksmanship' = 254; 'Hunter|Survival' = 255
  'Rogue|Assassination' = 259; 'Rogue|Combat' = 260; 'Rogue|Subtlety' = 261
  'Priest|Discipline' = 256; 'Priest|Holy' = 257; 'Priest|Shadow' = 258
  'DeathKnight|Blood' = 250; 'DeathKnight|Frost' = 251; 'DeathKnight|Unholy' = 252
  'Shaman|Elemental' = 262; 'Shaman|Enhancement' = 263; 'Shaman|Restoration' = 264
  'Mage|Arcane' = 62; 'Mage|Fire' = 63; 'Mage|Frost' = 64
  'Warlock|Affliction' = 265; 'Warlock|Demonology' = 266; 'Warlock|Destruction' = 267
  'Druid|Balance' = 102; 'Druid|Feral' = 103; 'Druid|Restoration' = 105
}

# Collect the class/tab pairs that actually exist in the data.
$classTabs = @{}
foreach ($rec in $cad) {
  $cls = [string]$rec["Class"]
  $tab = [string]$rec["Tab"]
  if ([string]::IsNullOrWhiteSpace($cls) -or $cls -eq 'None') { continue }
  if ([string]::IsNullOrWhiteSpace($tab) -or $tab -eq 'None') { continue }
  if (-not $classTabs.ContainsKey($cls)) { $classTabs[$cls] = @{} }
  $classTabs[$cls][$tab] = $true
}

$unknownClasses = @($classTabs.Keys | Where-Object { -not $classIds.Contains($_) })
if ($unknownClasses.Count) {
  Write-Host ("  NOTE: classes present in data but unmapped, assigning IDs from 400: {0}" -f ($unknownClasses -join ', ')) -ForegroundColor Yellow
  $next = 400
  foreach ($c in ($unknownClasses | Sort-Object)) { $classIds[$c] = $next; $next++ }
}

# Assign each class to one of the launcher's four game modes.
# Monk and Demon Hunter are Ascension hero classes that happen to sit on the
# retail IDs 10 and 12, so they belong to 'classless', not 'wrath'.
$WRATH_CLASSES = @('Warrior', 'Paladin', 'Hunter', 'Rogue', 'Priest', 'DeathKnight', 'Shaman', 'Mage', 'Warlock', 'Druid')
$classMode = @{}
foreach ($c in $WRATH_CLASSES) { $classMode[$c] = 'wrath' }
foreach ($c in $HERO_CLASS_IDS.Keys) { $classMode[$c] = 'classless' }
$classMode['Monk'] = 'classless'
$classMode['DemonHunter'] = 'classless'
foreach ($c in $BASE_CLASS_IDS.Keys) { $classMode["Reborn$c"] = 'reborn' }
$classMode['RebornGeneral'] = 'reborn'
$classMode['ConquestOfAzeroth'] = 'coa'
foreach ($c in $unknownClasses) { $classMode[$c] = 'classless' }

$activeModes = @{}
foreach ($m in $GameModes) { $activeModes[$m] = $true }
Write-Host ("  game modes: {0}" -f ($GameModes -join ', ')) -ForegroundColor Cyan

# The ID tables stay COMPLETE. GameModes only decides what the editor offers in
# its dropdown - it must not shrink the data, or a sequence carrying a spec ID
# from another mode (say 64, Frost - Mage, imported from another GSE build) would
# no longer resolve to a class and would lose its heading in the viewer.
$emitClasses = [ordered]@{}
foreach ($cls in ($classIds.Keys | Sort-Object { $classIds[$_] })) {
  if ($classTabs.ContainsKey($cls) -or $BASE_CLASS_IDS.Contains($cls)) {
    $emitClasses[$cls] = $classIds[$cls]
  }
}

# Spec IDs outside the retail set are derived as 1000 + classID*10 + tab index
# (tabs alphabetical), which is collision-free for class IDs up to 299.
$specNames = @{}      # specID -> "Tab - Class"   (complete)
$specMode = @{}       # specID -> game mode
foreach ($cls in ($classTabs.Keys | Sort-Object)) {
  $cid = $classIds[$cls]
  $tabs = @($classTabs[$cls].Keys | Sort-Object)
  for ($i = 0; $i -lt $tabs.Count; $i++) {
    $tab = $tabs[$i]
    $key = "$cls|$tab"
    $sid = if ($BASE_SPEC_IDS.ContainsKey($key)) { $BASE_SPEC_IDS[$key] } else { 1000 + ($cid * 10) + ($i + 1) }
    if ($specNames.ContainsKey($sid)) {
      throw "Spec ID collision on $sid ('$($specNames[$sid])' vs '$tab - $cls'). Adjust the ID scheme."
    }
    $specNames[$sid] = "$tab - $cls"
    $specMode[$sid] = $classMode[$cls]
  }
}

# The subset the editor dropdown offers.
$activeSpecIds = @($specNames.Keys | Where-Object { $specMode[$_] -and $activeModes[$specMode[$_]] } | Sort-Object)
$activeClassIds = @($emitClasses.Keys |
  Where-Object { $classMode[$_] -and $activeModes[$classMode[$_]] } |
  ForEach-Object { $emitClasses[$_] } | Sort-Object)
Write-Host ("  dropdown offers {0} classes + {1} trees (of {2} + {3} total)" -f `
  $activeClassIds.Count, $activeSpecIds.Count, $emitClasses.Count, $specNames.Count) -ForegroundColor Green

# Class IDs and spec IDs are emitted into the single wotlkSpecIDList table, so
# any overlap between the two sets would make one entry vanish at load time.
foreach ($cls in $emitClasses.Keys) {
  $cid = $emitClasses[$cls]
  if ($specNames.ContainsKey($cid)) {
    throw "Class ID $cid ('$cls') collides with spec ID $cid ('$($specNames[$cid])'). Adjust the ID scheme."
  }
}

Write-Host ("  classes: {0}  specs: {1}" -f $emitClasses.Count, $specNames.Count) -ForegroundColor Green

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine($header)
[void]$sb.AppendLine(@'
-- Ascension is classless: a character draws abilities from any tree, so these
-- tables are an organisational scheme for the macro library rather than a
-- description of what the character can cast. "Global" (0) stays the sensible
-- default for Ascension sequences.

local GSE = GSE
local Statics = GSE.Static

--- Class ID -> Ascension class name.
-- IDs 1-12 match the WotLK/retail class IDs so previously saved macros keep
-- resolving; 20+ are Ascension hero classes, 50+ the Reborn trees.
Statics.wotlkClassIDList = {
	[0] = "Global",
'@)
foreach ($cls in $emitClasses.Keys) {
  [void]$sb.AppendLine(("`t[{0}] = `"{1}`"," -f $emitClasses[$cls], (ConvertTo-LuaString $cls)))
}
[void]$sb.AppendLine('}')
[void]$sb.AppendLine('')
[void]$sb.AppendLine(@'
--- Spec ID -> "Tree - Class".
-- GSE.GetClassIDforSpec splits on " - " to recover the class, so the suffix
-- must stay exactly as spelled in Statics.wotlkClassIDList.
Statics.wotlkSpecIDList = {
	[0] = "Global",
'@)
# Class-level entries first (bare class name, no " - "), matching how GSE has
# always let a sequence target a whole class rather than one tree.
foreach ($cls in $emitClasses.Keys) {
  [void]$sb.AppendLine(("`t[{0}] = `"{1}`"," -f $emitClasses[$cls], (ConvertTo-LuaString $cls)))
}
foreach ($sid in ($specNames.Keys | Sort-Object)) {
  [void]$sb.AppendLine(("`t[{0}] = `"{1}`"," -f $sid, (ConvertTo-LuaString $specNames[$sid])))
}
[void]$sb.AppendLine('}')
[void]$sb.AppendLine('')
[void]$sb.AppendLine(@'
--- Class name -> ordered list of its trees, for GUI grouping.
Statics.AscensionClassTabs = {
'@)
foreach ($cls in ($classTabs.Keys | Sort-Object)) {
  $tabs = @($classTabs[$cls].Keys | Sort-Object) | ForEach-Object { '"' + (ConvertTo-LuaString $_) + '"' }
  [void]$sb.AppendLine(("`t[`"{0}`"] = {{ {1} }}," -f (ConvertTo-LuaString $cls), ($tabs -join ', ')))
}
[void]$sb.AppendLine('}')
[void]$sb.AppendLine((@'
--- The subset of IDs the editor's Specialisation/Class dropdown offers.
-- Generated for game mode(s): {0}
-- Every ID above stays resolvable regardless of what is listed here - this only
-- shortens the dropdown. GSE.GetSpecNames() reads it; if it is missing or empty
-- the dropdown falls back to offering everything.
Statics.ActiveSpecIDs = {{
'@ -f ($GameModes -join ', ')))
[void]$sb.AppendLine("`t[0] = true, -- Global")
foreach ($cid in $activeClassIds) {
  [void]$sb.AppendLine(("`t[{0}] = true," -f $cid))
}
foreach ($sid in $activeSpecIds) {
  [void]$sb.AppendLine(("`t[{0}] = true," -f $sid))
}
[void]$sb.AppendLine('}')
[void]$sb.AppendLine('')
[void]$sb.AppendLine(@'
--- Class IDs that UnitClass("player") can actually report on a 3.3.5a client.
-- Everything else - Ascension's hero classes, the Reborn trees, CoA - can only
-- be reached by filing a sequence under it by hand, so GSE.GetCurrentClassID()
-- will never return one. Code that decides whether a sequence belongs to the
-- player has to treat those as always-visible, or they become unreachable.
Statics.UnitClassResolvableIDs = {
'@)
foreach ($cls in $WRATH_CLASSES) {
  if ($emitClasses.Contains($cls)) {
    [void]$sb.AppendLine(("`t[{0}] = true, -- {1}" -f $emitClasses[$cls], (ConvertTo-LuaString $cls)))
  }
}
[void]$sb.AppendLine('}')
[void]$sb.AppendLine('')
[void]$sb.AppendLine(@'
-- The viewer and the remote browser both read Statics.SpecIDList; keep it as
-- the same table so the two can never drift apart.
Statics.SpecIDList = Statics.wotlkSpecIDList

Statics.SpecIDHashList = {}
for k, v in pairs(Statics.wotlkSpecIDList) do
	Statics.SpecIDHashList[v] = k
end
'@)
$ascData = $sb.ToString()

# ---------------------------------------------------------------------------
# Write output (UTF-8 without BOM - the 3.3.5a Lua loader chokes on a BOM)
# ---------------------------------------------------------------------------
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$outputs = [ordered]@{
  'GSE\Localization\enUS.lua'       = $enUS
  'GSE\Localization\enUSHash.lua'   = $enUSHash
  'GSE\Localization\enUSSHADOW.lua' = $enUSShadow
  'GSE\API\AscensionData.lua'       = $ascData
}
foreach ($rel in $outputs.Keys) {
  $full = Join-Path $RepoPath $rel
  $dir = Split-Path -Parent $full
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  [System.IO.File]::WriteAllText($full, $outputs[$rel], $utf8NoBom)
  Write-Host ("  wrote {0} ({1:N0} bytes)" -f $rel, (Get-Item $full).Length) -ForegroundColor Green
}

Write-Host "Done." -ForegroundColor Cyan
