local GSE = GSE
local Statics = GSE.Static
local L = GSE.L
GSELibrary = {}

Statics.CastCmds = { use = true, cast = true, spell = true, cancelaura = true, cancelform = true, stopmacro = true, petautocastoff = true, petautocaston = true, petattack = true }

Statics.CleanStrings = {
  [1] = "/console Sound_EnableSFX 0%;",
  [2] = "/console Sound_EnableSFX 1%;",
  [3] = "/script UIErrorsFrame:Hide%(%)%;",
  [4] = "/run UIErrorsFrame:Clear%(%)%;",
  [5] = "/script UIErrorsFrame:Clear%(%)%;",
  [6] = "/run UIErrorsFrame:Hide%(%)%;",
  [7] = "/console Sound_EnableErrorSpeech 1",
  [8] = "/console Sound_EnableErrorSpeech 0",

  [11] = "/console Sound_EnableSFX 0",
  [12] = "/console Sound_EnableSFX 1",
  [13] = "/script UIErrorsFrame:Hide%(%)",
  [14] = "/run UIErrorsFrame:Clear%(%)",
  [15] = "/script UIErrorsFrame:Clear%(%)",
  [16] = "/run UIErrorsFrame:Hide%(%)",
  [17] = "/console Sound_EnableErrorSpeech 1%;",
  [18] = "/console Sound_EnableErrorSpeech 0%;",
  [19] = [[""]],
  [20] = "/stopmacro [@playertarget, noexists]",

  [30] = "/use 2",
  [31] = "/use [combat] 11",
  [32] = "/use [combat] 12",
  [33] = "/use [combat] 13",
  [34] = "/use [combat] 14",
  [35] = "/use 11",
  [36] = "/use 12",
  [37] = "/use 13",
  [38] = "/use 14",
  [39] = "/Use [combat] 11",
  [40] = "/Use [combat] 12",
  [41] = "/Use [combat] 13",
  [42] = "/Use [combat] 14",
  [43] = "/use [combat]11",
  [44] = "/use [combat]12",
  [45] = "/use [combat]13",
  [46] = "/use [combat]14",
  [47] = "/use [combat]2",
  [48] = "/use [combat] 2",
  [49] = "/use [combat]5",
  [50] = "/use [combat] 5",
  [51] = "/use [combat]1",
  [52] = "/use [combat] 1",
  [53] = "/use 1",
  [54] = "/use 5",
  [101] = "\n\n",
}

Statics.StringReset =  "|r"
Statics.CoreLoadedMessage = "GS-CoreLoaded"

-- The class, spec and tab tables live in API\AscensionData.lua, which is
-- generated from the live Ascension client data by
-- tools/generate-ascension-data.ps1 and loaded immediately after this file.
-- Ascension has 30+ classes and reshuffles them between seasons, so keeping
-- them hand-written here went stale every patch.

Statics.SequenceDebug = "SEQUENCEDEBUG"

Statics.Priority = "Priority"
Statics.Sequential = "Sequential"

--- <code>GSStaticPriority</code> is a static step function that goes 1121231234123451234561234567
--    use this like StepFunction = GSStaticPriority, in a macro
--    This overides the sequential behaviour that is standard in GS
Statics.PriorityImplementation = [[
  limit = limit or 1
  if step == limit then
    limit = limit % #macros + 1
    step = 1
  else
    step = step % #macros + 1
  end
]]

--- <code>GSStaticLoopPriority</code> is a static step function that goes 1121231234123451234561234567
--    but it does this within an internal loop.  So more like 123343456
--    If the macro has loopstart or loopstop defined then it will use this instead of GSStaticPriority
Statics.LoopPriorityImplementation = [[
  if step < loopstart then
    step = step + 1

  elseif step > loopstop and loopstop == #macros then
    if step >= #macros then
      loopiter = 1
      step = loopstart
      if looplimit > 0 then
        step = 1
        limit = loopstart
      end
    else
      step = step + 1
    end
  elseif step == loopstop then
    if looplimit > 0 then
      if loopiter >= looplimit then
        if loopstop >= #macros then
          step = 1
          limit = loopstart
        else
          step = step + 1
          loopiter = 1
        end
      else
        step = loopstart
        loopiter = loopiter + 1
      end
    else
      step = loopstart
    end
  elseif step >= #macros then
    loopiter = 1
    step = loopstart
    if looplimit > 0 then
      step = 1
      limit = loopstart
    end
  else
    limit = limit or loopstart
    if step == limit then
      limit = limit % loopstop + 1
      step = loopstart
      if limit == loopiter then
        loopiter = loopiter + 1
      end
    else
      step = step + 1
    end
  end
]]

--- Injected into the OnClick snippet when DebugPrintModConditionsOnKeyPress is
--    set, so it runs in the secure restricted environment.
--    The last line used to be  print("..." .. GetMouseButtonClicked()), with no
--    tostring. GetMouseButtonClicked returns nil whenever the snippet runs
--    outside a mouse click, and concatenating nil raises an error. A snippet
--    that errors stops dead, so it never reached the line that sets macrotext:
--    the sequence then clicked with an empty macro and cast nothing at all,
--    silently. Everything is stringified now.
--    The modifier calls, including the sided ones, are all present in
--    FrameXML/RestrictedEnvironment.lua - they were never the problem.
Statics.PrintKeyModifiers = [[
print("alt " .. tostring(IsAltKeyDown()))
print("ctrl " .. tostring(IsControlKeyDown()))
print("shift " .. tostring(IsShiftKeyDown()))
print("any mod " .. tostring(IsModifierKeyDown()))
print("button " .. tostring(GetMouseButtonClicked()))
]]

Statics.OnClick = [=[
local step = self:GetAttribute('step')
local loopstart = self:GetAttribute('loopstart') or 1
local loopstop = self:GetAttribute('loopstop') or #macros
local loopiter = self:GetAttribute('loopiter') or 1
local looplimit = self:GetAttribute('looplimit') or 0
loopstart = tonumber(loopstart)
loopstop = tonumber(loopstop)
loopiter = tonumber(loopiter)
looplimit = tonumber(looplimit)
step = tonumber(step)
-- Channel hold. Any /cast issued during a channel cancels it, so spamming a
-- sequence that contains a channelled spell means the channel never completes
-- a single tick. PlayerIsChanneling is one of the few pieces of player state
-- the restricted environment exposes (see FrameXML/RestrictedEnvironment.lua),
-- so the snippet can see this and stand down: while a channel is running the
-- macro is built from KeyPress and KeyRelease only, no /cast is re-issued and
-- the step stays where it is.
-- There is no equivalent for ordinary casts - the environment offers no
-- PlayerIsCasting and no GetTime, so a time based throttle is not possible.
local hold = false
if self:GetAttribute('gsechannelhold') and PlayerIsChanneling and PlayerIsChanneling() then
  hold = true
end
if hold then
  self:SetAttribute('macrotext', self:GetAttribute('KeyPress') .. "\n" .. self:GetAttribute('KeyRelease'))
else
self:SetAttribute('macrotext', self:GetAttribute('KeyPress') .. "\n" .. macros[step] .. "\n" .. self:GetAttribute('KeyRelease'))
self:SetAttribute('gsemacroset', (self:GetAttribute('gsemacroset') or 0) + 1)
%s
end
if not step or not macros[step] then -- User attempted to write a step method that doesn't work, reset to 1
  print('|cffff0000Invalid step assigned by custom step sequence', self:GetName(), step or 'nil', '|r')
  step = 1
end
self:SetAttribute('step', step)
self:SetAttribute('loopiter', loopiter)
--self:CallMethod('UpdateIcon')
]=]

--- <code>GSStaticLoopPriority</code> is a static step function that
--    operates in a sequential mode but with an internal loop.
--    eg 12342345
Statics.LoopSequentialImplementation = [[
if step < loopstart then
  -- I am before the loop increment to next step.
  step = step + 1
elseif step > loopstop then
  if step >= #macros then
    loopiter = 1
    step = loopstart
    if looplimit > 0 then
      step = 1
    end
  else
    step = step + 1
  end
elseif step == loopstop then
  if looplimit > 0 then
    if loopiter >= looplimit then
      if loopstop >= #macros then
        step = 1
      else
        step = step + 1
      end
      loopiter = 1
    else
      step = loopstart
      loopiter = loopiter + 1
    end
  else
    step = loopstart
  end
elseif step >= #macros then
  loopiter = 1
  step = loopstart
  if looplimit > 0 then
    step = 1
  end
else
  step = step + 1
end
]]

Statics.StringFormatEscapes = {
    ["|c%x%x%x%x%x%x%x%x"] = "", -- color start
    ["|r"] = "", -- color end
    ["|H.-|h(.-)|h"] = "%1", -- links
    ["|T.-|t"] = "", -- textures
    ["{.-}"] = "", -- raid target icons
}

Statics.MacroResetSkeleton = [[
if %s then
  self:SetAttribute('step', 1)
  self:SetAttribute('loopiter', 1)
end
]]

Statics.SourceLocal = "Local"
Statics.SourceTransmission = "Transmission"
Statics.DebugModules = {}
Statics.DebugModules["Translator"] = "Translator"
Statics.DebugModules["Storage"] = "Storage"
Statics.DebugModules["Editor"] ="Editor"
Statics.DebugModules["Viewer"] = "Viewer"
Statics.DebugModules["Versions"] = "Versions"
Statics.DebugModules[Statics.SourceTransmission] = Statics.SourceTransmission
Statics.DebugModules["API"] = "API"
Statics.DebugModules["GUI"] = "GUI"
Statics.DebugModules["Events"] = "Events"


Statics.TranslationKey = "KEY"
Statics.TranslationHash = "HASH"
Statics.TranslationShadow = "SHADOW"

Statics.Spec = "Spec"
Statics.Class = "Class"
Statics.All = "All"
Statics.Global = "Global"

Statics.SampleMacros = {}
Statics.QuestionMark = "INV_MISC_QUESTIONMARK"

Statics.ReloadMessage = "Reload"
Statics.CommPrefix = "GSE"
