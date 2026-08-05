<#
.SYNOPSIS
    Sanity-checks the generated Lua data files.

.DESCRIPTION
    Lua silently keeps only the last assignment when a table literal repeats a
    key, so a duplicate in a generated table loses data with no error at load
    time. This script fails loudly instead, and cross-checks that the three
    spell tables agree with each other.

.EXAMPLE
    .\tools\validate-generated-data.ps1
#>
[CmdletBinding()]
param([string]$RepoPath = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$problems = @()

function Get-LuaTableEntries {
  param([string]$Path)
  $entries = @()
  foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
    $m = [regex]::Match($line, '^\s*\[(?<key>"(?:[^"\\]|\\.)*"|-?\d+)\]\s*=\s*(?<val>"(?:[^"\\]|\\.)*"|-?\d+)\s*,\s*$')
    if ($m.Success) {
      $entries += [pscustomobject]@{ Key = $m.Groups['key'].Value; Value = $m.Groups['val'].Value }
    }
  }
  $entries
}

function Test-NoDuplicateKeys {
  param([string]$Path, [string]$Label)
  $entries = Get-LuaTableEntries -Path $Path
  $dupes = $entries | Group-Object Key | Where-Object { $_.Count -gt 1 }
  if ($dupes) {
    foreach ($d in $dupes) {
      $script:problems += "$Label : duplicate key $($d.Name) x$($d.Count) -> $(($d.Group.Value | Select-Object -Unique) -join ' | ')"
    }
  }
  Write-Host ("{0,-34} {1,6} entries, {2} duplicate keys" -f $Label, $entries.Count, @($dupes).Count) `
    -ForegroundColor $(if ($dupes) { 'Red' } else { 'Green' })
  $entries
}

$keyPath    = Join-Path $RepoPath 'GSE\Localization\enUS.lua'
$hashPath   = Join-Path $RepoPath 'GSE\Localization\enUSHash.lua'
$shadowPath = Join-Path $RepoPath 'GSE\Localization\enUSSHADOW.lua'
$dataPath   = Join-Path $RepoPath 'GSE\API\AscensionData.lua'

$key    = Test-NoDuplicateKeys -Path $keyPath    -Label 'enUS.lua (id -> name)'
$hash   = Test-NoDuplicateKeys -Path $hashPath   -Label 'enUSHash.lua (name -> id)'
$shadow = Test-NoDuplicateKeys -Path $shadowPath -Label 'enUSSHADOW.lua (lower -> id)'

# AscensionData.lua holds several tables; check each independently, since the
# same key legitimately appears once per table.
$currentTable = $null
$perTable = @{}
foreach ($line in [System.IO.File]::ReadAllLines($dataPath)) {
  $t = [regex]::Match($line, '^Statics\.(?<name>\w+)\s*=\s*\{')
  if ($t.Success) { $currentTable = $t.Groups['name'].Value; $perTable[$currentTable] = @(); continue }
  if ($null -eq $currentTable) { continue }
  if ($line -match '^\}') { $currentTable = $null; continue }
  $m = [regex]::Match($line, '^\s*\[(?<key>"(?:[^"\\]|\\.)*"|-?\d+)\]\s*=')
  if ($m.Success) { $perTable[$currentTable] += $m.Groups['key'].Value }
}
foreach ($name in ($perTable.Keys | Sort-Object)) {
  $dupes = $perTable[$name] | Group-Object | Where-Object { $_.Count -gt 1 }
  if ($dupes) {
    foreach ($d in $dupes) { $problems += "Statics.$name : duplicate key $($d.Name) x$($d.Count)" }
  }
  Write-Host ("{0,-34} {1,6} entries, {2} duplicate keys" -f "Statics.$name", $perTable[$name].Count, @($dupes).Count) `
    -ForegroundColor $(if ($dupes) { 'Red' } else { 'Green' })
}

# GSE.TranslateSpell resolves a name to an ID via the hash table and then looks
# that ID up in the key table; a hash ID missing from the key table is reported
# to the user as an unknown spell.
$keyIds = @{}
foreach ($e in $key) { $keyIds[$e.Key.Trim('[',']')] = $true }
$missing = @($hash | Where-Object { -not $keyIds.ContainsKey($_.Value) })
if ($missing.Count) {
  $problems += "enUSHash.lua : {0} IDs absent from enUS.lua (e.g. {1})" -f `
    $missing.Count, (($missing | Select-Object -First 5 | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')
}
Write-Host ("{0,-34} {1} hash IDs missing from key table" -f 'cross-check hash -> key', $missing.Count) `
  -ForegroundColor $(if ($missing.Count) { 'Red' } else { 'Green' })

$missingShadow = @($shadow | Where-Object { -not $keyIds.ContainsKey($_.Value) })
if ($missingShadow.Count) { $problems += "enUSSHADOW.lua : $($missingShadow.Count) IDs absent from enUS.lua" }
Write-Host ("{0,-34} {1} shadow IDs missing from key table" -f 'cross-check shadow -> key', $missingShadow.Count) `
  -ForegroundColor $(if ($missingShadow.Count) { 'Red' } else { 'Green' })

Write-Host ''
if ($problems.Count) {
  Write-Host "FAILED:" -ForegroundColor Red
  $problems | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
  exit 1
}
Write-Host "All checks passed." -ForegroundColor Green
