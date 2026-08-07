-- GLOBALS: GSE
GSE = LibStub("AceAddon-3.0"):NewAddon("GSE", "AceConsole-3.0", "AceEvent-3.0", "AceComm-3.0", "AceSerializer-3.0", "AceTimer-3.0")
GSE.L = LibStub("AceLocale-3.0"):GetLocale("GSE")
GSE.Static = {}

GSE.VersionString = GetAddOnMetadata("GSE", "Version");

GSE.MediaPath = "Interface\\Addons\\GSE\\Media"

GSE.OutputQueue = {}
GSE.DebugOutput = ""
GSE.SequenceDebugOutput = ""
GSE.GUI = {}
GSE.isNewFirstTimeCreated = false
local L = GSE.L
local Statics = GSE.Static
local GNOME = "GSE"

-- Initialisation Functions


--- When the Addon loads, printing is paused until after every other mod has loaded.
--    This method prints the print queue.
function GSE.PerformPrint()
  for k,v in ipairs(GSE.OutputQueue) do
    print(v)
    GSE.OutputQueue[k] = nil
  end
end


--- Prints <code>filepath</code>to the chat handler.  This accepts an optional
--    <code>title</code> to be prepended to that message.
function GSE.Print(message, title)
  -- store this for later on.
  if not GSE.isEmpty(title) then
    message = GSEOptions.TitleColour .. title .. Statics.StringReset .." " .. message
  end
  table.insert(GSE.OutputQueue, message)
  if GSE.PrintAvailable then
    GSE.PerformPrint()
  end
end

--- Send the message string to an output source.
--    If <code>GSEOptions.sendDebugOutputGSE.DebugOutput</code> then the output will
--    be appended to variable <code>GSE.DebugOutput</code>
--    If <code>GSEOptions.sendDebugOutputToChat</code> then the output will
--    be sent to variable <code>GSE.Print</code>
--    The Title is stripped for intermod debug output via GSE.DebugOutput
local function determineOutputDestination(message, title)
  if GSE.UnsavedOptions.DebugSequenceExecution then
    GSE.DebugOutput = GSE.DebugOutput .. message .. "\n"
	elseif GSEOptions.sendDebugOutputToDebugOutput   then
    GSE.DebugOutput = GSE.DebugOutput .. message .. "\n"
  end
	if GSEOptions.sendDebugOutputToChatWindow  then
    GSE.Print(message, title)
	end
end

--- Prints <code>message</code>to the chat handler.  This accepts an optional
--    <code>module</code> that is used to identify whether debugging for that module
--    is currently enabled.
function GSE.PrintDebugMessage(message, module)
    if GSE.isEmpty(module) then
      module = "GS-Core"
    end
    if module == Statics.SequenceDebug then
      determineOutputDestination(message, GSEOptions.TitleColour .. GNOME .. ':|r ' .. GSEOptions.AuthorColour .. L["<SEQUENCEDEBUG> |r "] )
		elseif GSEOptions.debug and module ~= Statics.SequenceDebug and GSEOptions.DebugModules[module] == true then
      determineOutputDestination(GSEOptions.TitleColour .. (GSE.isEmpty(module) and GNOME or module) .. ':|r ' .. GSEOptions.AuthorColour .. L["<DEBUG> |r "] .. message )
    end
end

--- Append a line to the GSE debug log kept in GSEOptions.DebugLog.
-- WoW Lua cannot write files, and the chat frame is not captured by /chatlog,
-- so diagnostics that need to be read outside the game have to ride out in
-- saved variables. The log is flushed on reload or logout like any other saved
-- variable and is capped so it cannot grow without bound.
-- Wipe it with /gse clearlog.
function GSE.LogToFile(message)
  -- Deliberately inside GSEOptions rather than a GSEDebugLog global of its own.
  -- Adding a name to ## SavedVariables does not take on this client - two
  -- separate variables declared that way were never written to disk - while
  -- GSEOptions has always persisted.
  if type(GSEOptions) ~= "table" then
    return
  end
  if type(GSEOptions.DebugLog) ~= "table" then
    GSEOptions.DebugLog = {}
  end
  table.insert(GSEOptions.DebugLog, date("%Y-%m-%d %H:%M:%S") .. "  " .. tostring(message))
  while table.getn(GSEOptions.DebugLog) > 500 do
    table.remove(GSEOptions.DebugLog, 1)
  end
end

--- One-line summary of a macro version, for GSE.LogToFile.
function GSE.DescribeMacroVersion(macroversion)
  if type(macroversion) ~= "table" then
    return "<" .. type(macroversion) .. ">"
  end
  local function count(t)
    if type(t) ~= "table" then return "nil" end
    return tostring(table.getn(t))
  end
  return string.format("lines=%s KeyPress=%s PreMacro=%s KeyRelease=%s PostMacro=%s Step=%s",
    tostring(table.getn(macroversion)),
    count(macroversion.KeyPress), count(macroversion.PreMacro),
    count(macroversion.KeyRelease), count(macroversion.PostMacro),
    tostring(macroversion.StepFunction))
end

GSE.CurrentGCD = GetSpellCooldown(61304)
GSE.RecorderActive = false

-- Macro mode Status
GSE.PVPFlag = false
GSE.inRaid = false
GSE.inMythic = false
GSE.inDungeon = false
GSE.inHeroic = false
GSE.inParty = false
