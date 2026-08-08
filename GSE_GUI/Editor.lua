local GNOME,_ = ...
local Statics = GSE.Static
local GSE = GSE

local AceGUI = LibStub("AceGUI-3.0")
local L = GSE.L
local libS = LibStub:GetLibrary("AceSerializer-3.0")
local libC = LibStub:GetLibrary("LibCompress")
local libCE = libC:GetAddonEncodeTable()

-- Field help. Kept here rather than in a file of its own because this client
-- only enumerates an add-on's files at startup: a newly added one is reported
-- as "Error loading" in Logs/FrameXML.log until the game is fully restarted,
-- and /reload is not enough. Living in a file that already loads avoids that.

--- Translate if the string has been registered, otherwise use it as written.
--    GSE.L is a non-silent AceLocale table: indexing it with a key nobody
--    registered returns the key but also fires the error handler every time.
--    These texts are far too long to carry in every locale file, so ask with
--    rawget, which does not trip that.
local function T(text)
  return rawget(GSE.L, text) or text
end

--- Help text for the sequence editor's fields, written against how the addon
--    actually behaves. Several of these are the answer to a problem that cost
--    a lot of time to find, so the surprises are called out rather than buried.
local FIELD_HELP = {

  KeyPress = {
    T("KeyPress"),
    T("Lines pasted at the top of the macro on EVERY press, ahead of the current step.\n\nNEVER PUT A SPELL HERE THAT COSTS A RESOURCE YOU CAN RUN OUT OF. A spell on cooldown reports itself unusable and the macro moves on to the next line, but a spell you merely cannot afford still counts as usable: it claims the one cast this press allowed, errors, and nothing below it runs - the step included. If the step is where your resource generator lives, that is a deadlock, not a stall.\n\nCooldown-gated abilities are what belongs here. They fire the moment they come up, ahead of the step, which no ordering in the sequence can achieve.\n\nWatch the length. KeyPress, the step's line and KeyRelease become one macro and WoW cuts that at 255 characters without a word. Prevent Sound Errors alone adds about 220."),
  },

  PreMacro = {
    T("PreMacro"),
    T("Extra steps that run once at the start of the sequence, before the loop begins.\n\nThese are steps, not per-press lines: each one costs a press. The button resets when you leave combat, so they run again on every pull.\n\nIMPORTANT: a single line here switches the step function to its looping variant, and the looping variant of Priority collapses into plain sequential walking after about twenty presses. If you are relying on Priority weighting, this box must stay empty."),
  },

  Sequence = {
    T("Sequence"),
    T("The looping list. One line is one step, and exactly one step runs per press.\n\nThe step advances on every press whether or not the spell actually cast, because a macro cannot know. A step whose spell is on cooldown costs one press, and the next press is already trying the next step. Nothing here can block anything else, which is why every spell that costs a resource belongs here rather than in KeyPress.\n\nAt spam speed the pointer laps the whole list several times per global cooldown, so what decides the mix is how many copies of a line you put in, not where you put it."),
  },

  KeyRelease = {
    T("KeyRelease"),
    T("Lines pasted at the bottom of the macro on every press, after the current step.\n\nShares the 255 character budget with KeyPress and the step, and because it sits last it is the first thing cut when the macro overflows.\n\nBe careful with [nocombat] here. Out of combat that condition is true on every press, so an instant spell parked here fires continuously and jams the rest of the rotation."),
  },

  PostMacro = {
    T("PostMacro"),
    T("Steps appended after the loop.\n\nIn a looping sequence these are NEVER REACHED. The loop's end stops short of the end of the list, so the pointer turns back to the start and never walks into them. They run only when Inner Loop Limit is set.\n\nLike PreMacro, a line here also switches the step function to its looping variant and costs Priority its weighting."),
  },

  StepFunction = {
    T("Step Function"),
    T("How the pointer moves through the sequence.\n\nSequential walks 1, 2, 3, 4 and back to the start.\n\nPriority walks 1, then 1-2, then 1-2-3, so the first line takes the largest share of presses and the last the smallest. With six steps that is roughly 29% down to 5%.\n\nThat weighting only holds while PreMacro, PostMacro and Inner Loop Limit are all empty. Fill any of them in and Priority degrades to plain Sequential after about twenty presses."),
  },

  LoopLimit = {
    T("Inner Loop Limit"),
    T("How many times the inner loop repeats before the pointer is allowed past it.\n\nLeave it empty and the sequence loops forever, which is what you want almost always. Setting it is the only way PostMacro ever runs - and it also costs Priority its weighting."),
  },

  ChannelHold = {
    T("Hold while channelling"),
    T("While a channel is running, build the macro from KeyPress with every casting line stripped out: nothing can be re-issued and the step stays where it is.\n\nAny /cast issued during a channel cancels it, so without this a spammed sequence containing a channelled spell never completes a single tick.\n\nThere is no equivalent for ordinary casts. The secure environment a macro runs in can see a channel, but it cannot see a cast, and it has no clock."),
  },

  CombatReset = {
    T("Resets"),
    T("Send the pointer back to the first step when you leave combat, so every pull starts at the top and PreMacro runs again."),
  },

  ItemSlot = {
    T("Use"),
    T("Append /use [combat] for this equipment slot to KeyRelease.\n\nLeft unticked these follow the global setting in the options rather than being off, and the lines they add never appear in the boxes above - but they still count against the 255 character macro limit."),
  },

  SpecID = {
    T("Specialisation / Class ID"),
    T("Which class the sequence is filed under. Ascension is classless, so Global is the sensible choice for most sequences; the hero classes and Reborn trees are there if you would rather group them."),
  },

  Talents = {
    T("Talents"),
    T("Free text note about the build this sequence was written for. Not used for anything, purely a reminder."),
  },

  Help = {
    T("Help"),
    T("Free text shown next to the sequence in the viewer. Worth a line on what the rotation assumes."),
  },

  Helplink = {
    T("Help Link"),
    T("A URL shown with the sequence in the viewer."),
  },

  Author = {
    T("Author"),
    T("Who wrote it. Filled in automatically for new sequences."),
  },

  VersionDefault = {
    T("Default"),
    T("Which macro version is used when nothing more specific applies."),
  },

  MacroLength = {
    T("Macro length"),
    T("Every press builds ONE macro out of three pieces: KeyPress, the line of whichever step is current, and KeyRelease. This counts that macro at its worst - the longest step you have - against the 255 characters WoW allows.\n\nGo over and WoW truncates without a word of warning. It cuts from the end, so KeyRelease goes first and the step's own /cast next, which looks exactly like the rotation doing nothing while KeyPress carries on working.\n\nThe number includes lines you never typed and cannot see in these boxes, which is what usually causes an overflow. From the Options panel:\n\n  Prevent Sound Errors    226 characters (144 in KeyPress, 82 in KeyRelease)\n  Require Target           74 characters (37 in each)\n  Prevent UI Errors        30 characters in KeyRelease\n  Clear UI Errors          27 characters in KeyRelease\n  each ticked item slot    17 characters in KeyRelease\n\nPrevent Sound Errors alone leaves under 30 characters for everything else, so it is almost always the thing to turn off first."),
  },

  VersionContext = {
    T("Raid / Party / Dungeon / Heroic / Mythic / PVP"),
    T("Use a different macro version in this situation. Point it at the Default version if you do not want a separate one - a version is only worth having when the rotation genuinely differs."),
  },
}

--- Put a small help icon on a widget, showing the text on hover.
--    The icon is a plain child frame of the widget rather than another AceGUI
--    child, so it takes no part in the flow layout and cannot push anything
--    onto a new line. AceGUI pools its widgets, so the key lives on the frame
--    and is refreshed on every attach - otherwise a recycled box would keep
--    showing the previous field's text.
local function attachHelpIcon(widget, key)
  if not widget or not widget.frame or not FIELD_HELP[key] then
    return
  end
  local frame = widget.frame

  if not frame.GSEHelpIcon then
    local icon = CreateFrame("Button", nil, frame)
    icon:SetWidth(16)
    icon:SetHeight(16)
    -- Inside the frame, not above it: these widgets sit in a ScrollFrame, which
    -- clips anything poking out past its edge.
    icon:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -2)
    icon:SetFrameLevel(frame:GetFrameLevel() + 5)

    -- Drawn as text rather than a texture. A texture that fails to load leaves
    -- an invisible button, and a help icon nobody can find is no help icon.
    local glyph = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    glyph:SetPoint("CENTER", icon, "CENTER", 0, 0)
    glyph:SetText("|cff33ccff[?]|r")
    icon.glyph = glyph

    icon:SetScript("OnEnter", function(self)
      local entry = FIELD_HELP[frame.GSEHelpKey]
      if not entry then
        return
      end
      self.glyph:SetText("|cffffd100[?]|r")
      GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
      GameTooltip:AddLine(entry[1], 1, 0.82, 0)
      GameTooltip:AddLine(entry[2], 1, 1, 1, true)
      GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function(self)
      self.glyph:SetText("|cff33ccff[?]|r")
      GameTooltip:Hide()
    end)

    frame.GSEHelpIcon = icon
  end

  frame.GSEHelpKey = key
  frame.GSEHelpIcon:Show()
end

local otherversionlistboxvalue = ""
local default = 1
local raid = 1
local pvp = 1
local mythic = 1
local classid = GSE.GetCurrentClassID()

local editframe = AceGUI:Create("Frame")
editframe:Hide()
GSE.GUIEditFrame = editframe
editframe.Sequence = {}
editframe.Sequence.MacroVersions = {}
editframe.SequenceName = ""
editframe.Default = 1
editframe.Raid = 1
editframe.PVP = 1
editframe.Mythic = 1
editframe.Dungeon = 1
editframe.Heroic = 1
editframe.Party = 1
editframe.ClassID = classid
editframe.save = false
editframe.SelectedTab = "group"

local fleft, fbottom, fwidth, fheight = editframe.frame:GetBoundsRect()
editframe.Left = fleft
editframe.Bottom = fbottom
editframe.Width = fwidth
editframe.Height = fheight

editframe:SetTitle(L["Sequence Editor"])
--editframe:SetStatusText(L["Gnome Sequencer: Sequence Editor."])
editframe:SetCallback("OnClose", function (self)
  editframe:Hide();
  if editframe.save then
    local event = {}
    event.action = "openviewer"
    table.insert(GSE.OOCQueue, event)
  else
    GSE.GUIShowViewer()
  end
end)
editframe:SetLayout("List")
-- Set resize bounds based on screen size
local maxHeight = GetScreenHeight() - 40
local maxWidth = GetScreenWidth() - 40
editframe.frame:SetMaxResize(maxWidth, maxHeight)
-- Set minimum size to prevent content overflow
editframe.frame:SetMinResize(600, 500)

-- Set initial size to a reasonable default
-- Use 100% of screen height which should be constrained by system limits
local defaultHeight = GetScreenHeight() * 1.0
editframe:SetCallback("OnShow", function()
  editframe.frame:SetHeight(defaultHeight)
end)
editframe.frame:SetScript("OnSizeChanged", function ()
  editframe.Left, editframe.Bottom, editframe.Width, editframe.Height = editframe.frame:GetBoundsRect()
  local screenHeight = GetScreenHeight()
  local screenWidth = GetScreenWidth()
  local maxHeight = screenHeight - 40  -- Leave some space at top/bottom
  local maxWidth = screenWidth - 40    -- Leave some space at sides
  
  -- Get current position
  local top = editframe.frame:GetTop()
  local bottom = editframe.frame:GetBottom()
  local left = editframe.frame:GetLeft()
  local right = editframe.frame:GetRight()
  
  -- Check if we need to constrain the size or reposition
  local needsResize = false
  local needsMove = false
  local newHeight = editframe.Height
  local newWidth = editframe.Width
  
  if editframe.Height > maxHeight then
    newHeight = maxHeight
    needsResize = true
  end
  
  if editframe.Width > maxWidth then
    newWidth = maxWidth
    needsResize = true
  end
  
  -- Check if window is going off screen edges
  if top and top > screenHeight then
    needsMove = true
  end
  
  if bottom and bottom < 0 then
    needsMove = true
  end
  
  if left and left < 0 then
    needsMove = true
  end
  
  if right and right > screenWidth then
    needsMove = true
  end
  
  -- Apply constraints if needed
  if needsResize then
    editframe.frame:SetHeight(newHeight)
    editframe.frame:SetWidth(newWidth)
    editframe.Height = newHeight
    editframe.Width = newWidth
  end
  
  -- Reposition if off screen
  if needsMove then
    local newPoint = {}
    newPoint.x = math.min(math.max(left or 20, 20), screenWidth - newWidth - 20)
    newPoint.y = math.min(math.max(bottom or 20, 20), screenHeight - newHeight - 20)
    editframe.frame:ClearAllPoints()
    editframe.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", newPoint.x, newPoint.y)
  end
  
  -- Update TabGroup height and layout
  if editframe.updateTabGroupHeight then
    editframe.updateTabGroupHeight()
  end
  editframe:DoLayout()
  
  -- Trigger a layout refresh on the TabGroup's content
  if editframe.ContentContainer and editframe.ContentContainer.LayoutFinished then
    editframe.ContentContainer:Fire("OnHeightSet")
  end
end)


local specdropdownvalue = editframe.SpecID


--- Attach a field help icon, saying so if it cannot.
--    The attach calls sit at the very end of the draw functions, and AceGUI
--    wraps those in safecall, so anything wrong here vanishes without a trace
--    and simply leaves the icons missing. Report it once instead.
--- Update the "Macro: n / 255" readout from what is currently in the boxes.
--    Counts the whole macro a click will build - KeyPress, the longest step and
--    KeyRelease - and runs it through GSE.PrepareKeyPress/PrepareKeyRelease so
--    the lines GSE adds behind your back are included. Those are exactly what
--    catches people out: Prevent Sound Errors alone contributes about 220
--    characters that appear in none of these boxes.
local function refreshMacroLength()
  local widgets = editframe.MacroWidgets
  if not widgets or not widgets.LengthLabel then
    return
  end
  local stored = editframe.Sequence
    and editframe.Sequence.MacroVersions
    and editframe.Sequence.MacroVersions[widgets.version]
  if type(stored) ~= "table" then
    return
  end

  -- A throwaway version built from the screen, so the number tracks typing
  -- rather than the last save. The slot flags come from the stored version
  -- because their checkboxes write straight to it.
  local probe = {
    KeyPress = GSE.SplitMeIntolines(widgets.KeyPress:GetText() or ""),
    KeyRelease = GSE.SplitMeIntolines(widgets.KeyRelease:GetText() or ""),
    Head = stored.Head, Neck = stored.Neck, Belt = stored.Belt,
    Ring1 = stored.Ring1, Ring2 = stored.Ring2,
    Trinket1 = stored.Trinket1, Trinket2 = stored.Trinket2,
  }
  local keypress = table.concat(GSE.PrepareKeyPress(probe), "\n")
  local keyrelease = table.concat(GSE.PrepareKeyRelease(probe), "\n")

  local longest = 0
  for _, line in ipairs(GSE.SplitMeIntolines(widgets.Sequence:GetText() or "")) do
    if string.len(line) > longest then
      longest = string.len(line)
    end
  end
  for _, line in ipairs(GSE.SplitMeIntolines(widgets.PreMacro:GetText() or "")) do
    if string.len(line) > longest then
      longest = string.len(line)
    end
  end

  local total = string.len(keypress) + 1 + longest + 1 + string.len(keyrelease)
  local colour = (total > 255) and "|cffff4040" or "|cff40ff40"
  local note = (total > 255) and " - too long" or ""
  widgets.LengthLabel:SetText(string.format("%sMacro: %d / 255|r%s", colour, total, note))
end

local function attachHelp(widget, key)
  local ok, err = pcall(attachHelpIcon, widget, key)
  if not ok and not editframe.helpWarned then
    editframe.helpWarned = true
    GSE.Print("Field help icon failed: " .. tostring(err), GNOME)
  end
end

function GSE.GUICreateEditorTabs()
  local tabl = {
    {
      text=L["Configuration"],
      value="config"
    },
  }
  if editframe.Sequence.MacroVersions and type(editframe.Sequence.MacroVersions) == "table" then
    for k,v in ipairs(editframe.Sequence.MacroVersions) do
      local insline = {}
      insline.text = tostring(k)
      insline.value = tostring(k)
      table.insert(tabl, insline)
    end
  end
  table.insert(tabl,   {
      text=L["New"],
      value="new"
    }  )
  return tabl
end

function GSE.GUIEditorPerformLayout(frame)
  -- Everything is about to be released, so the remembered widgets go stale.
  editframe.MacroWidgets = nil

  -- AceGUI:Release calls widget:OnRelease() before it empties widget.events,
  -- and an EditBox clears itself in OnRelease. Its OnTextChanged does not test
  -- userInput, so the handler below still fired and wiped SequenceName to "".
  -- Every save from then on hit the empty-name guard in
  -- GUIUpdateSequenceDefinition and silently did nothing. Hold the name across
  -- the release.
  local sequenceName = editframe.SequenceName
  editframe.releasing = true
  frame:ReleaseChildren()
  editframe.releasing = false
  editframe.SequenceName = sequenceName
  local headerGroup = AceGUI:Create("SimpleGroup")
  headerGroup:SetFullWidth(true)
  headerGroup:SetLayout("Flow")


  local nameeditbox = AceGUI:Create("EditBox")
  nameeditbox:SetLabel(L["Sequence Name"])
  nameeditbox:SetWidth(250)
  nameeditbox:SetCallback("OnTextChanged", function()
    -- AceGUI fires this while releasing the widget, with the text it just
    -- blanked. Taking that value wiped the sequence name, and every save
    -- after the first hit the empty-name guard and did nothing.
    if editframe.releasing then return end
    editframe.SequenceName = nameeditbox:GetText()
  end)
  nameeditbox:DisableButton( true)
  nameeditbox:SetText(editframe.SequenceName)
  editframe.nameeditbox = nameeditbox
  headerGroup:AddChild(nameeditbox)

  local spacerlabel = AceGUI:Create("Label")
  spacerlabel:SetWidth(300)
  headerGroup:AddChild(spacerlabel)

  local iconpicker = AceGUI:Create("Icon")
  iconpicker:SetLabel(L["Macro Icon"])
  iconpicker.frame:RegisterForDrag("LeftButton")
  iconpicker.frame:SetScript("OnDragStart", function()
    if not GSE.isEmpty(editframe.SequenceName) then
      PickupMacro(editframe.SequenceName)
    end
  end)
  iconpicker:SetImage(GSEOptions.DefaultDisabledMacroIcon)
  headerGroup:AddChild(iconpicker)
  editframe.iconpicker = iconpicker

  frame:AddChild(headerGroup)

  local tabgrp =  AceGUI:Create("TabGroup")
  tabgrp:SetLayout("Flow")
  tabgrp:SetTabs(GSE.GUICreateEditorTabs())
  editframe.ContentContainer = tabgrp


  tabgrp:SetCallback("OnGroupSelected",  function (container, event, group)
    GSE.GUISelectEditorTab(container, event, group)
  end)
  tabgrp:SetFullWidth(true)
  -- Don't use SetFullHeight(true) as it causes unbounded growth
  -- Instead, calculate available height after accounting for header and buttons
  local function updateTabGroupHeight()
    local availableHeight = editframe.Height - 150 -- Account for header, buttons, and padding
    tabgrp:SetHeight(math.max(300, availableHeight)) -- Minimum height of 300
  end
  updateTabGroupHeight()
  editframe.updateTabGroupHeight = updateTabGroupHeight

  tabgrp:SelectTab("config")
  frame:AddChild(tabgrp)



  local editOptionsbutton = AceGUI:Create("Button")
  editOptionsbutton:SetText(L["Options"])
  editOptionsbutton:SetWidth(150)
  editOptionsbutton:SetCallback("OnClick", function() GSE.OpenOptionsPanel() end)

  local transbutton = AceGUI:Create("Button")
  transbutton:SetText(L["Send"])
  transbutton:SetWidth(150)
  transbutton:SetCallback("OnClick", function() GSE.GUIShowTransmissionGui(editframe.ClassID.. "," ..editframe.SequenceName) end)

  local editButtonGroup = AceGUI:Create("SimpleGroup")
  editButtonGroup:SetWidth(602)
  editButtonGroup:SetLayout("Flow")
  editButtonGroup:SetHeight(15)

  local savebutton = AceGUI:Create("Button")
  savebutton:SetText(L["Save"])
  savebutton:SetWidth(150)
  savebutton:SetCallback("OnClick", function()
    editframe.Sequence.ManualIntervention = true
    -- Only take the box when it holds something. An empty box is never a
    -- rename, and copying it over the real name is what made every save after
    -- the first one silently do nothing.
    local typedName = GSE.TrimWhiteSpace(nameeditbox:GetText() or "")
    if not GSE.isEmpty(typedName) then
      editframe.SequenceName = typedName
    end
    nameeditbox:SetText(editframe.SequenceName)
    -- AceGUI swallows errors thrown inside a button handler, so a fault in the
    -- commit would abort the save with no sign of it. Contain it and carry on.
    GSE.LogToFile("---- Save clicked: " .. tostring(editframe.SequenceName)
      .. " classid=" .. tostring(editframe.ClassID))
    local committed, err = pcall(GSE.GUICommitMacroEditor)
    if not committed then
      GSE.Print("GSE could not read the editor boxes: " .. tostring(err))
      GSE.LogToFile("commit FAILED: " .. tostring(err))
    end
    GSE.GUIUpdateSequenceDefinition(editframe.ClassID, editframe.SequenceName, editframe.Sequence)
    editframe.save = true
  end)
  editButtonGroup:AddChild(savebutton)

  local delbutton = AceGUI:Create("Button")
  delbutton:SetText(L["Delete"])
  delbutton:SetWidth(150)
  delbutton:SetCallback("OnClick", function() GSE.GUIDeleteSequence(editframe.ClassID, editframe.SequenceName) end)
  editButtonGroup:AddChild(delbutton)

  editButtonGroup:AddChild(transbutton)
  editButtonGroup:AddChild(editOptionsbutton)
  frame:AddChild(editButtonGroup)

end

function GSE.GetVersionList()
  local tabl = {}
  classid = tonumber(classid)
  if editframe and editframe.Sequence and editframe.Sequence.MacroVersions and type(editframe.Sequence.MacroVersions) == "table" then
    for k,v in ipairs(editframe.Sequence.MacroVersions) do
      tabl[tostring(k)] = tostring(k)
    end
  end
  return tabl
end

function GSE:GUIDrawMetadataEditor(container)
  -- Default frame size = 700 w x 500 h

  editframe.iconpicker:SetImage(GSE.GetMacroIcon(editframe.ClassID, editframe.SequenceName))


  local scrollcontainer = AceGUI:Create("SimpleGroup") -- "InlineGroup" is also good
  scrollcontainer:SetFullWidth(true)
  -- Better height calculation that accounts for minimum space needed
  local availableHeight = math.max(100, editframe.Height - 280) -- Ensure minimum height
  scrollcontainer:SetHeight(availableHeight)
  scrollcontainer:SetLayout("Fill") -- important!

  local contentcontainer = AceGUI:Create("ScrollFrame")
  -- Ensure the scroll frame doesn't grow beyond available space
  contentcontainer:SetAutoAdjustHeight(false)
  scrollcontainer:AddChild(contentcontainer)

  local metasimplegroup = AceGUI:Create("SimpleGroup")
  metasimplegroup:SetLayout("Flow")
  metasimplegroup:SetWidth(editframe.Width - 100)

  local speciddropdown = AceGUI:Create("Dropdown")
  speciddropdown:SetLabel(L["Specialisation / Class ID"])
  speciddropdown:SetWidth(200)
  speciddropdown:SetList(GSE.GetSpecNames())
  speciddropdown:SetCallback("OnValueChanged", function (obj,event,key)
    local sid = Statics.SpecIDHashList[key]
    specdropdownvalue = key;
    editframe.SpecID = sid
    editframe.Sequence.SpecID = sid

    if tonumber(sid) > 12 then
      editframe.ClassID = GSE.GetClassIDforSpec(tonumber(sid))
    else
      editframe.ClassID = tonumber(sid)
    end
  end)
  metasimplegroup:AddChild(speciddropdown)
  speciddropdown:SetValue(Statics.wotlkSpecIDList[editframe.Sequence.SpecID])


  local spacerlabel1 = AceGUI:Create("Label")
  spacerlabel1:SetWidth(80)
  metasimplegroup:AddChild(spacerlabel1)

  local talentseditbox = AceGUI:Create("EditBox")
  talentseditbox:SetLabel(L["Talents"])
  talentseditbox:SetWidth(200)
  talentseditbox:DisableButton( true)
  metasimplegroup:AddChild(talentseditbox)
  contentcontainer:AddChild(metasimplegroup)
  talentseditbox:SetText(editframe.Sequence.Talents)
  talentseditbox:SetCallback("OnTextChanged", function (obj,event,key)
    if editframe.releasing then return end
    editframe.Sequence.Talents = key
  end)
  local helpeditbox = AceGUI:Create("MultiLineEditBox")
  helpeditbox:SetLabel(L["Help Information"])
  helpeditbox:SetWidth(250)
  helpeditbox:DisableButton( true)
  helpeditbox:SetNumLines(4)
  helpeditbox:SetFullWidth(true)
  if not GSE.isEmpty(editframe.Sequence.Help) then
    helpeditbox:SetText(editframe.Sequence.Help)
  end
  helpeditbox:SetCallback("OnTextChanged", function (obj,event,key)
    if editframe.releasing then return end
    editframe.Sequence.Help = key
  end)
  contentcontainer:AddChild(helpeditbox)

  local helpgroup1 = AceGUI:Create("SimpleGroup")
  helpgroup1:SetLayout("Flow")
  helpgroup1:SetWidth(editframe.Width - 100)


  local helplinkeditbox = AceGUI:Create("EditBox")
  helplinkeditbox:SetLabel(L["Help Link"])
  helplinkeditbox:SetWidth(250)
  helplinkeditbox:DisableButton( true)
  if not GSE.isEmpty(editframe.Sequence.Helplink) then
    helplinkeditbox:SetText(editframe.Sequence.Helplink)
  end
  helplinkeditbox:SetCallback("OnTextChanged", function (obj,event,key)
    if editframe.releasing then return end
    editframe.Sequence.Helplink = key
  end)
  helpgroup1:AddChild(helplinkeditbox)

  local spacerlabel3 = AceGUI:Create("Label")
  spacerlabel3:SetWidth(100)
  helpgroup1:AddChild(spacerlabel3)

  local authoreditbox = AceGUI:Create("EditBox")
  authoreditbox:SetLabel(L["Author"])
  authoreditbox:SetWidth(250)
  authoreditbox:DisableButton( true)
  if not GSE.isEmpty(editframe.Sequence.Author) then
    authoreditbox:SetText(editframe.Sequence.Author)
  end
  authoreditbox:SetCallback("OnTextChanged", function (obj,event,key)
    if editframe.releasing then return end
    editframe.Sequence.Author = key
  end)
  helpgroup1:AddChild(authoreditbox)

  contentcontainer:AddChild(helpgroup1)

  local defgroup1 = AceGUI:Create("SimpleGroup")
  defgroup1:SetLayout("Flow")
  defgroup1:SetWidth(editframe.Width - 100)


  local defaultdropdown = AceGUI:Create("Dropdown")
  defaultdropdown:SetLabel(L["Default Version"])
  defaultdropdown:SetWidth(250)
  defaultdropdown:SetList(GSE.GetVersionList())
  defaultdropdown:SetValue(tostring(editframe.Default))
  defgroup1:AddChild(defaultdropdown)
  defaultdropdown:SetCallback("OnValueChanged", function (obj,event,key)
    editframe.Sequence.Default = tonumber(key)
    editframe.Default = tonumber(key)
  end)

  local spacerlabel4 = AceGUI:Create("Label")
  spacerlabel4:SetWidth(100)
  defgroup1:AddChild(spacerlabel4)

  local raiddropdown = AceGUI:Create("Dropdown")
  raiddropdown:SetLabel(L["Raid"])
  raiddropdown:SetWidth(250)
  raiddropdown:SetList(GSE.GetVersionList())
  raiddropdown:SetValue(tostring(editframe.Raid))
  defgroup1:AddChild(raiddropdown)
  raiddropdown:SetCallback("OnValueChanged", function (obj,event,key)
    if editframe.Sequence.Default == tonumber(key) then
      editframe.Sequence.Raid = nil
    else
      editframe.Sequence.Raid = tonumber(key)
      editframe.Raid = tonumber(key)
    end
  end)

  contentcontainer:AddChild(defgroup1)

  local defgroup2 = AceGUI:Create("SimpleGroup")
  defgroup2:SetLayout("Flow")
  defgroup2:SetWidth(editframe.Width - 100)

  local mythicdropdown = AceGUI:Create("Dropdown")
  mythicdropdown:SetLabel(L["Mythic"])
  mythicdropdown:SetWidth(250)
  mythicdropdown:SetList(GSE.GetVersionList())
  mythicdropdown:SetValue(tostring(editframe.Mythic))
  mythicdropdown:SetCallback("OnValueChanged", function (obj,event,key)
    if editframe.Sequence.Default == tonumber(key) then
      editframe.Sequence.Mythic = nil
    else
      editframe.Sequence.Mythic = tonumber(key)
      editframe.Mythic = tonumber(key)
    end
  end)
  defgroup2:AddChild(mythicdropdown)

  local spacerlabel5 = AceGUI:Create("Label")
  spacerlabel5:SetWidth(100)
  defgroup2:AddChild(spacerlabel5)

  local pvpdropdown = AceGUI:Create("Dropdown")
  pvpdropdown:SetLabel(L["PVP"])
  pvpdropdown:SetWidth(250)
  pvpdropdown:SetList(GSE.GetVersionList())
  pvpdropdown:SetValue(tostring(editframe.PVP))
  defgroup2:AddChild(pvpdropdown)
  contentcontainer:AddChild(defgroup2)

  pvpdropdown:SetCallback("OnValueChanged", function (obj,event,key)
    if editframe.Sequence.Default == tonumber(key) then
      editframe.Sequence.PVP = nil
    else
      editframe.Sequence.PVP = tonumber(key)
      editframe.PVP = tonumber(key)
    end
  end)

  local defgroup3 = AceGUI:Create("SimpleGroup")
  defgroup3:SetLayout("Flow")
  defgroup3:SetWidth(editframe.Width - 100)


  local dungeondropdown = AceGUI:Create("Dropdown")
  dungeondropdown:SetLabel(L["Dungeon"])
  dungeondropdown:SetWidth(250)
  dungeondropdown:SetList(GSE.GetVersionList())
  dungeondropdown:SetValue(tostring(editframe.Dungeon))
  defgroup3:AddChild(dungeondropdown)
  dungeondropdown:SetCallback("OnValueChanged", function (obj,event,key)
    if editframe.Sequence.Default == tonumber(key) then
      editframe.Sequence.Dungeon = nil
    else
      editframe.Sequence.Dungeon = tonumber(key)
      editframe.Dungeon = tonumber(key)
    end
  end)

  local spacerlabel6 = AceGUI:Create("Label")
  spacerlabel6:SetWidth(100)
  defgroup3:AddChild(spacerlabel6)

  local heroicdropdown = AceGUI:Create("Dropdown")
  heroicdropdown:SetLabel(L["Heroic"])
  heroicdropdown:SetWidth(250)
  heroicdropdown:SetList(GSE.GetVersionList())
  heroicdropdown:SetValue(tostring(editframe.Heroic))
  defgroup3:AddChild(heroicdropdown)
  heroicdropdown:SetCallback("OnValueChanged", function (obj,event,key)
    if editframe.Sequence.Default == tonumber(key) then
      editframe.Sequence.Heroic = nil
    else
      editframe.Sequence.Heroic = tonumber(key)
      editframe.Heroic = tonumber(key)
    end
  end)

  local defgroup4 = AceGUI:Create("SimpleGroup")
  defgroup4:SetLayout("Flow")
  defgroup4:SetWidth(editframe.Width - 100)

  local partydropdown = AceGUI:Create("Dropdown")
  partydropdown:SetLabel(L["Party"])
  partydropdown:SetWidth(250)
  partydropdown:SetList(GSE.GetVersionList())
  partydropdown:SetValue(tostring(editframe.Party))
  defgroup4:AddChild(partydropdown)
  partydropdown:SetCallback("OnValueChanged", function (obj,event,key)
    if editframe.Sequence.Default == tonumber(key) then
      editframe.Sequence.Party = nil
    else
      editframe.Sequence.Party = tonumber(key)
      editframe.Party = tonumber(key)
    end
  end)

  local spacerlabel7 = AceGUI:Create("Label")
  spacerlabel7:SetWidth(100)
  defgroup4:AddChild(spacerlabel7)
  contentcontainer:AddChild(defgroup3)
  contentcontainer:AddChild(defgroup4)
  container:AddChild(scrollcontainer)

  attachHelp(speciddropdown, "SpecID")
  attachHelp(talentseditbox, "Talents")
  attachHelp(helpeditbox, "Help")
  attachHelp(helplinkeditbox, "Helplink")
  attachHelp(authoreditbox, "Author")
  attachHelp(defaultdropdown, "VersionDefault")
  attachHelp(raiddropdown, "VersionContext")
  attachHelp(mythicdropdown, "VersionContext")
  attachHelp(pvpdropdown, "VersionContext")
  attachHelp(dungeondropdown, "VersionContext")
  attachHelp(heroicdropdown, "VersionContext")
  attachHelp(partydropdown, "VersionContext")
end

function GSE:GUIDrawMacroEditor(container, version)
  version = tonumber(version)
  if GSE.isEmpty(editframe.Sequence.MacroVersions[version]) then
    editframe.Sequence.MacroVersions[version] = {}
    editframe.Sequence.MacroVersions[version].PreMacro = {}
    editframe.Sequence.MacroVersions[version].PostMacro = {}
    editframe.Sequence.MacroVersions[version].KeyPress = {}
    editframe.Sequence.MacroVersions[version].KeyRelease = {}
    editframe.Sequence.MacroVersions[version].StepFunction = "Sequential"
    editframe.Sequence.MacroVersions[version][1] = "/say Hello"
  end

  editframe.Sequence.MacroVersions[version] = GSE.TranslateSequence(editframe.Sequence.MacroVersions[version], "From Editor")

  local layoutcontainer = AceGUI:Create("SimpleGroup")
  layoutcontainer:SetFullWidth(true)
  -- Use same height calculation as scrollcontainer to ensure consistency
  local availableHeight = math.max(100, editframe.Height - 280) -- Ensure minimum height
  layoutcontainer:SetHeight(availableHeight)
  layoutcontainer:SetLayout("Flow") -- important!

  local scrollcontainer = AceGUI:Create("SimpleGroup") -- "InlineGroup" is also good
  --scrollcontainer:SetFullWidth(true)
  --scrollcontainer:SetFullHeight(true) -- probably?
  scrollcontainer:SetWidth(editframe.Width - 200)
  -- Use the same availableHeight as layoutcontainer
  scrollcontainer:SetHeight(availableHeight)
  scrollcontainer:SetLayout("Fill") -- important!

  local contentcontainer = AceGUI:Create("ScrollFrame")
  -- Ensure the scroll frame doesn't grow beyond available space
  contentcontainer:SetAutoAdjustHeight(false)
  scrollcontainer:AddChild(contentcontainer)

  local linegroup1 = AceGUI:Create("SimpleGroup")
  linegroup1:SetLayout("Flow")
  linegroup1:SetWidth(editframe.Width - 100)
  linegroup1:SetAutoAdjustHeight(false)

  local stepdropdown = AceGUI:Create("Dropdown")
  stepdropdown:SetLabel(L["Step Function"])
  stepdropdown:SetWidth((editframe.Width - 210) * 0.48)
  stepdropdown:SetList({
    ["Sequential"] = L["Sequential (1 2 3 4)"],
    ["Priority"] = L["Priority List (1 12 123 1234)"],

  })
  if GSE.isEmpty(editframe.Sequence.MacroVersions[version].StepFunction) then
    editframe.Sequence.MacroVersions[version].StepFunction = "Sequential"
  end
  stepdropdown:SetValue(editframe.Sequence.MacroVersions[version].StepFunction)
  stepdropdown:SetCallback("OnValueChanged", function (sel, object, value)
      editframe.Sequence.MacroVersions[version].StepFunction = value
    end)
  linegroup1:AddChild(stepdropdown)

  local spacerlabel1 = AceGUI:Create("Label")
  spacerlabel1:SetWidth(5)
  linegroup1:AddChild(spacerlabel1)

  local looplimit = AceGUI:Create("EditBox")
  looplimit:SetLabel(L["Inner Loop Limit"])
  looplimit:DisableButton(true)
  looplimit:SetMaxLetters(4)
  looplimit:SetWidth(100)

  linegroup1:AddChild(looplimit)
  if not GSE.isEmpty(editframe.Sequence.MacroVersions[version].LoopLimit) then
    looplimit:SetText(tonumber(editframe.Sequence.MacroVersions[version].LoopLimit))
  end
  looplimit.editbox:SetNumeric()
  looplimit:SetCallback("OnTextChanged", function (sel, object, value)
    if editframe.releasing then return end
    editframe.Sequence.MacroVersions[version].LoopLimit = value
  end)

  local spacerlabelthrottle = AceGUI:Create("Label")
  spacerlabelthrottle:SetWidth(5)
  linegroup1:AddChild(spacerlabelthrottle)

  local channelhold = AceGUI:Create("CheckBox")
  channelhold:SetLabel(L["Hold while channelling"])
  channelhold:SetType("checkbox")
  channelhold:SetWidth(200)
  channelhold:SetValue(editframe.Sequence.MacroVersions[version].ChannelHold ~= false)
  channelhold:SetCallback("OnValueChanged", function (sel, object, value)
    if editframe.releasing then return end
    editframe.Sequence.MacroVersions[version].ChannelHold = value
  end)
  linegroup1:AddChild(channelhold)

  local macrolength = AceGUI:Create("Label")
  macrolength:SetWidth(160)
  macrolength:SetText("")
  linegroup1:AddChild(macrolength)

  local spacerlabel7 = AceGUI:Create("Label")
  spacerlabel7:SetWidth(5)
  linegroup1:AddChild(spacerlabel7)

  local delversionbutton = AceGUI:Create("Button")
  delversionbutton:SetText(L["Delete Version"])
  delversionbutton:SetWidth(150)
  delversionbutton:SetCallback("OnClick", function()
    GSE.GUIDeleteVersion(version)
  end)
  linegroup1:AddChild(delversionbutton)

  contentcontainer:AddChild(linegroup1)
  local linegroup2 = AceGUI:Create("SimpleGroup")
  linegroup2:SetLayout("Flow")
  linegroup2:SetWidth(editframe.Width - 100)
  linegroup2:SetAutoAdjustHeight(false)

  local KeyPressbox = AceGUI:Create("MultiLineEditBox")
  KeyPressbox:SetLabel(L["KeyPress"])
  KeyPressbox:SetNumLines(2)
  KeyPressbox:DisableButton(true)
  KeyPressbox:SetWidth((editframe.Width - 210) * 0.48)
  KeyPressbox.editBox:SetScript( "OnLeave",  function() GSE.GUIParseText(KeyPressbox) end)
  if not GSE.isEmpty(editframe.Sequence.MacroVersions[version].KeyPress) then
    KeyPressbox:SetText(table.concat(editframe.Sequence.MacroVersions[version].KeyPress, "\n"))
  end
  KeyPressbox:SetCallback("OnTextChanged", function (sel, object, value)
    editframe.Sequence.MacroVersions[version].KeyPress = GSE.SplitMeIntolines(value)
    refreshMacroLength()
  end)
  linegroup2:AddChild(KeyPressbox)

  local spacerlabel2 = AceGUI:Create("Label")
  spacerlabel2:SetWidth(6)
  linegroup2:AddChild(spacerlabel2)

  local PreMacro = AceGUI:Create("MultiLineEditBox")
  PreMacro:SetLabel(L["PreMacro"])
  PreMacro:SetNumLines(2)
  PreMacro:DisableButton(true)
  PreMacro:SetWidth((editframe.Width - 210) * 0.48)
  PreMacro.editBox:SetScript( "OnLeave",  function() GSE.GUIParseText(PreMacro) end)
  if not GSE.isEmpty(editframe.Sequence.MacroVersions[version].PreMacro) then
    PreMacro:SetText(table.concat(editframe.Sequence.MacroVersions[version].PreMacro, "\n"))
  end
  PreMacro:SetCallback("OnTextChanged", function (sel, object, value)
    editframe.Sequence.MacroVersions[version].PreMacro = GSE.SplitMeIntolines(value)
    refreshMacroLength()
  end)
  linegroup2:AddChild(PreMacro)

  contentcontainer:AddChild(linegroup2)

  local spellbox = AceGUI:Create("MultiLineEditBox")
  spellbox:SetLabel(L["Sequence"])
  spellbox:SetNumLines(8)
  spellbox:DisableButton(true)
  spellbox:SetFullWidth(true)
  spellbox.editBox:SetScript( "OnLeave",  function() GSE.GUIParseText(spellbox) end)
  if not GSE.isEmpty(editframe.Sequence.MacroVersions[version]) then
    spellbox:SetText(table.concat(editframe.Sequence.MacroVersions[version], "\n"))
  end
  spellbox:SetCallback("OnTextChanged", function (sel, object, value)
    if editframe.Sequence.MacroVersions[version] and type(editframe.Sequence.MacroVersions[version]) == "table" then
      for k,v in ipairs(editframe.Sequence.MacroVersions[version]) do
        editframe.Sequence.MacroVersions[version][k] = nil
      end
    end
    local newpairs = GSE.SplitMeIntolines(value)
    for k,v in ipairs(newpairs) do
      editframe.Sequence.MacroVersions[version][k] = v
    end
    refreshMacroLength()
  end)
  contentcontainer:AddChild(spellbox)

  local linegroup3 = AceGUI:Create("SimpleGroup")
  linegroup3:SetLayout("Flow")
  linegroup3:SetWidth(editframe.Width - 100)
  linegroup3:SetAutoAdjustHeight(false)

  local KeyReleasebox = AceGUI:Create("MultiLineEditBox")
  KeyReleasebox:SetLabel(L["KeyRelease"])
  KeyReleasebox:SetNumLines(2)
  KeyReleasebox:DisableButton(true)
  KeyReleasebox:SetWidth((editframe.Width - 210) * 0.48)
  KeyReleasebox.editBox:SetScript( "OnLeave",  function() GSE.GUIParseText(KeyReleasebox) end)
  if not GSE.isEmpty(editframe.Sequence.MacroVersions[version].KeyRelease) then
    KeyReleasebox:SetText(table.concat(editframe.Sequence.MacroVersions[version].KeyRelease, "\n"))
  end
  KeyReleasebox:SetCallback("OnTextChanged", function (sel, object, value)
    editframe.Sequence.MacroVersions[version].KeyRelease = GSE.SplitMeIntolines(value)
    refreshMacroLength()
  end)
  linegroup3:AddChild(KeyReleasebox)

  local spacerlabel3 = AceGUI:Create("Label")
  spacerlabel3:SetWidth(6)
  linegroup3:AddChild(spacerlabel3)

  local PostMacro = AceGUI:Create("MultiLineEditBox")
  PostMacro:SetLabel(L["PostMacro"])
  PostMacro:SetNumLines(2)
  PostMacro:DisableButton(true)
  PostMacro:SetWidth((editframe.Width - 210) * 0.48)
  PostMacro.editBox:SetScript( "OnLeave",  function() GSE.GUIParseText(PostMacro) end)
  linegroup3:AddChild(PostMacro)
  if not GSE.isEmpty(editframe.Sequence.MacroVersions[version].PostMacro) then
    PostMacro:SetText(table.concat(editframe.Sequence.MacroVersions[version].PostMacro, "\n"))
  end
  PostMacro:SetCallback("OnTextChanged", function (sel, object, value)
    editframe.Sequence.MacroVersions[version].PostMacro = GSE.SplitMeIntolines(value)
  end)
  contentcontainer:AddChild(linegroup3)

  -- Remember the live widgets for this version so saving can read them back
  -- directly. The OnTextChanged callbacks above are the only thing that ever
  -- wrote KeyPress, PreMacro, KeyRelease, PostMacro and StepFunction into the
  -- sequence, and anything that stops them firing loses the edit with no
  -- warning - the Sequence box survived only because its handler mutates the
  -- version table in place. Reading the boxes at save time cannot miss.
  editframe.MacroWidgets = {
    version = version,
    StepFunction = stepdropdown,
    LoopLimit = looplimit,
    ChannelHold = channelhold,
    KeyPress = KeyPressbox,
    PreMacro = PreMacro,
    Sequence = spellbox,
    KeyRelease = KeyReleasebox,
    PostMacro = PostMacro,
    LengthLabel = macrolength,
  }
  refreshMacroLength()

  layoutcontainer:AddChild(scrollcontainer)

  local toolbarcontainer = AceGUI:Create("SimpleGroup") -- "InlineGroup" is also good
  toolbarcontainer:SetWidth(85)
  toolbarcontainer:SetHeight(availableHeight) -- Match the height of other containers

  local heading2 = AceGUI:Create("Label")
  heading2:SetText(L["Resets"])
  toolbarcontainer:AddChild(heading2)

  -- local targetresetcheckbox = AceGUI:Create("CheckBox")
  -- targetresetcheckbox:SetType("checkbox")
  -- targetresetcheckbox:SetWidth(78)
  -- targetresetcheckbox:SetTriState(false)
  -- targetresetcheckbox:SetLabel(L["Target"])
  -- toolbarcontainer:AddChild(targetresetcheckbox)
  -- if editframe.Sequence.MacroVersions[version].Target then
  --   targetresetcheckbox:SetValue(true)
  -- end
  -- targetresetcheckbox:SetCallback("OnValueChanged", function (sel, object, value)
  --   editframe.Sequence.MacroVersions[version].Target = value
  -- end)

  local combatresetcheckbox = AceGUI:Create("CheckBox")
  combatresetcheckbox:SetType("checkbox")
  combatresetcheckbox:SetWidth(78)
  combatresetcheckbox:SetTriState(true)
  combatresetcheckbox:SetLabel(L["Combat"])
  toolbarcontainer:AddChild(combatresetcheckbox)
  combatresetcheckbox:SetValue(editframe.Sequence.MacroVersions[version].Combat)
  combatresetcheckbox:SetCallback("OnValueChanged", function (sel, object, value)
    editframe.Sequence.MacroVersions[version].Combat = value
  end)

  local headingspace1 = AceGUI:Create("Label")
  headingspace1:SetText(" ")
  toolbarcontainer:AddChild(headingspace1)

  local heading1 = AceGUI:Create("Label")
  heading1:SetText(L["Use"])
  toolbarcontainer:AddChild(heading1)

  local headcheckbox = AceGUI:Create("CheckBox")
  headcheckbox:SetType("checkbox")
  headcheckbox:SetWidth(78)
  headcheckbox:SetTriState(true)
  headcheckbox:SetLabel(L["Head"])
  headcheckbox:SetCallback("OnValueChanged", function (sel, object, value)
    editframe.Sequence.MacroVersions[version].Head = value
    refreshMacroLength()
  end)
  headcheckbox:SetValue(editframe.Sequence.MacroVersions[version].Head)

  toolbarcontainer:AddChild(headcheckbox)

  local neckcheckbox = AceGUI:Create("CheckBox")
  neckcheckbox:SetType("checkbox")
  neckcheckbox:SetWidth(78)
  neckcheckbox:SetTriState(true)
  neckcheckbox:SetLabel(L["Neck"])
  neckcheckbox:SetCallback("OnValueChanged", function (sel, object, value)
    editframe.Sequence.MacroVersions[version].Neck = value
    refreshMacroLength()
  end)
  neckcheckbox:SetValue(editframe.Sequence.MacroVersions[version].Neck)
  toolbarcontainer:AddChild(neckcheckbox)

  local beltcheckbox = AceGUI:Create("CheckBox")
  beltcheckbox:SetType("checkbox")
  beltcheckbox:SetWidth(78)
  beltcheckbox:SetTriState(true)
  beltcheckbox:SetLabel(L["Belt"])
  beltcheckbox:SetCallback("OnValueChanged", function (sel, object, value)
    editframe.Sequence.MacroVersions[version].Belt = value
    refreshMacroLength()
  end)
  beltcheckbox:SetValue(editframe.Sequence.MacroVersions[version].Belt)
  toolbarcontainer:AddChild(beltcheckbox)

  local ring1checkbox = AceGUI:Create("CheckBox")
  ring1checkbox:SetType("checkbox")
  ring1checkbox:SetWidth(68)
  ring1checkbox:SetTriState(true)
  ring1checkbox:SetLabel(L["Ring 1"])
  ring1checkbox:SetCallback("OnValueChanged", function (sel, object, value)
    editframe.Sequence.MacroVersions[version].Ring1 = value
    refreshMacroLength()
  end)
  ring1checkbox:SetValue(editframe.Sequence.MacroVersions[version].Ring1)
  toolbarcontainer:AddChild(ring1checkbox)

  local ring2checkbox = AceGUI:Create("CheckBox")
  ring2checkbox:SetType("checkbox")
  ring2checkbox:SetWidth(68)
  ring2checkbox:SetTriState(true)
  ring2checkbox:SetLabel(L["Ring 2"])
  ring2checkbox:SetCallback("OnValueChanged", function (sel, object, value)
    editframe.Sequence.MacroVersions[version].Ring2 = value
    refreshMacroLength()
  end)
  ring2checkbox:SetValue(editframe.Sequence.MacroVersions[version].Ring2)
  toolbarcontainer:AddChild(ring2checkbox)

  local trinket1checkbox = AceGUI:Create("CheckBox")
  trinket1checkbox:SetType("checkbox")
  trinket1checkbox:SetWidth(78)
  trinket1checkbox:SetTriState(true)
  trinket1checkbox:SetLabel(L["Trinket 1"])
  trinket1checkbox:SetCallback("OnValueChanged", function (sel, object, value)
    editframe.Sequence.MacroVersions[version].Trinket1 = value
    refreshMacroLength()
  end)
  trinket1checkbox:SetValue(editframe.Sequence.MacroVersions[version].Trinket1)
  toolbarcontainer:AddChild(trinket1checkbox)

  local trinket2checkbox = AceGUI:Create("CheckBox")
  trinket2checkbox:SetType("checkbox")
  trinket2checkbox:SetWidth(83)
  trinket2checkbox:SetTriState(true)
  trinket2checkbox:SetLabel(L["Trinket 2"])
  trinket2checkbox:SetCallback("OnValueChanged", function (sel, object, value)
    editframe.Sequence.MacroVersions[version].Trinket2 = value
    refreshMacroLength()
  end)
  trinket2checkbox:SetValue(editframe.Sequence.MacroVersions[version].Trinket2)
  toolbarcontainer:AddChild(trinket2checkbox)

  layoutcontainer:AddChild(toolbarcontainer)
  container:AddChild(layoutcontainer)

  attachHelp(stepdropdown, "StepFunction")
  attachHelp(looplimit, "LoopLimit")
  attachHelp(channelhold, "ChannelHold")
  attachHelp(macrolength, "MacroLength")
  attachHelp(KeyPressbox, "KeyPress")
  attachHelp(PreMacro, "PreMacro")
  attachHelp(spellbox, "Sequence")
  attachHelp(KeyReleasebox, "KeyRelease")
  attachHelp(PostMacro, "PostMacro")
  -- On the two column headings rather than the checkboxes themselves: those are
  -- only 78 wide and an icon in the corner would sit on top of their labels.
  attachHelp(heading2, "CombatReset")
  attachHelp(heading1, "ItemSlot")
end

--- Read the macro editor's boxes back into the sequence.
-- Safe to call at any time: it does nothing unless a macro version tab is
-- currently drawn, and it only touches the version that tab belongs to.
function GSE.GUICommitMacroEditor()
  local widgets = editframe.MacroWidgets
  if not widgets then
    GSE.LogToFile("commit: MacroWidgets is nil - no macro tab drawn, boxes not read")
    return
  end
  local macroversion = editframe.Sequence
    and editframe.Sequence.MacroVersions
    and editframe.Sequence.MacroVersions[widgets.version]
  if type(macroversion) ~= "table" then
    GSE.LogToFile("commit: MacroVersions[" .. tostring(widgets.version) .. "] is "
      .. type(macroversion) .. ", nothing to write into")
    return
  end

  local report = {}
  local function lines(widget, label)
    local text = widget:GetText()
    table.insert(report, label .. "=" .. string.len(text or ""))
    if GSE.isEmpty(GSE.TrimWhiteSpace(text or "")) then
      return {}
    end
    return GSE.SplitMeIntolines(text)
  end

  macroversion.KeyPress = lines(widgets.KeyPress, "KeyPress")
  macroversion.PreMacro = lines(widgets.PreMacro, "PreMacro")
  macroversion.KeyRelease = lines(widgets.KeyRelease, "KeyRelease")
  macroversion.PostMacro = lines(widgets.PostMacro, "PostMacro")

  local step = widgets.StepFunction:GetValue()
  if not GSE.isEmpty(step) then
    macroversion.StepFunction = step
  end

  -- Not "x and nil or y": `and nil` is falsy, so that idiom always yields y and
  -- an untouched Inner Loop Limit was being stored as an empty string.
  local limit = widgets.LoopLimit:GetText()
  if GSE.isEmpty(GSE.TrimWhiteSpace(limit or "")) then
    macroversion.LoopLimit = nil
  else
    macroversion.LoopLimit = limit
  end

  macroversion.ChannelHold = widgets.ChannelHold:GetValue() and true or false

  -- Replace the numbered lines. Count first: clearing them inside an ipairs
  -- over the same table stops the iteration at the first hole.
  local body = lines(widgets.Sequence, "Sequence")
  for k = table.getn(macroversion), 1, -1 do
    macroversion[k] = nil
  end
  for k,v in ipairs(body) do
    macroversion[k] = v
  end

  GSE.LogToFile("commit v" .. tostring(widgets.version) .. " chars read: " .. table.concat(report, " "))
  GSE.LogToFile("commit v" .. tostring(widgets.version) .. " result: " .. GSE.DescribeMacroVersion(macroversion))
end

function GSE.GUISelectEditorTab(container, event, group)
  -- Leaving a version tab releases its widgets, so take their contents first.
  GSE.GUICommitMacroEditor()
  editframe.MacroWidgets = nil
  editframe.releasing = true
  container:ReleaseChildren()
  editframe.releasing = false
  editframe.SelectedTab = group
  editframe.nameeditbox:SetText(GSE.GUIEditFrame.SequenceName)
  editframe.iconpicker:SetImage(GSE.GetMacroIcon(editframe.ClassID, editframe.SequenceName))
  if group == "config" then
    GSE:GUIDrawMetadataEditor(container)
  elseif group == "new" then
	  -- A brand new sequence has to exist in the library before a second version
	  -- can be added to it. Clear the flag afterwards: it used to stay set, so
	  -- every later click of the New tab wrote the sequence out again.
	  if(GSE.isNewFirstTimeCreated) then
		GSE.GUIUpdateSequenceDefinition(editframe.ClassID, editframe.SequenceName, editframe.Sequence)
		editframe.save = true
		GSE.isNewFirstTimeCreated = false
	  end
    -- Copy the Default to a new version
    table.insert(editframe.Sequence.MacroVersions, GSE.CloneMacroVersion(editframe.Sequence.MacroVersions[editframe.Sequence.Default]))

    GSE.GUIEditorPerformLayout(editframe)
    GSE.GUISelectEditorTab(container, event, table.getn(editframe.Sequence.MacroVersions))
  else
    GSE:GUIDrawMacroEditor(container, group)
  end

end

function GSE.GUIDeleteVersion(version)
  version = tonumber(version)
  local sequence = editframe.Sequence
  if table.getn(sequence.MacroVersions) <= 1 then
    GSE.Print(L["This is the only version of this macro.  Delete the entire macro to delete this version."])
    return
  end
  if sequence.Default == version then
    GSE.Print(L["You cannot delete the Default version of this macro.  Please choose another version to be the Default on the Configuration tab."])
    return
  end
  local printtext = L["Macro Version %d deleted."]
  if sequence.PVP == version then
    sequence.PVP = sequence.Default
    printtext = printtext .. " " .. L["PVP setting changed to Default."]
  end
  if sequence.Raid == version then
    sequence.Raid = sequence.Default
    printtext = printtext .. " " .. L["Raid setting changed to Default."]
  end
  if sequence.Mythic == version then
    sequence.Mythic = sequence.Default
    printtext = printtext .. " " .. L["Mythic setting changed to Default."]
  end
  if sequence.Heroic == version then
    sequence.Heroic = sequence.Default
    printtext = printtext .. " " .. L["Heroic setting changed to Default."]
  end
  if sequence.Dungeon == version then
    sequence.Dungeon = sequence.Default
    printtext = printtext .. " " .. L["Dungeon setting changed to Default."]
  end
  if sequence.Party == version then
    sequence.Party = sequence.Default
    printtext = printtext .. " " .. L["Party setting changed to Default."]
  end

  if sequence.Default > 1 then
    sequence.Default = tonumber(sequence.Default) - 1
  else
    sequence.Default = 1
  end

  if not GSE.isEmpty(sequence.PVP) then
    sequence.PVP = tonumber(sequence.PVP) - 1
  end
  if not GSE.isEmpty(sequence.Raid) then
    sequence.Raid = tonumber(sequence.Raid) - 1
  end
  if not GSE.isEmpty(sequence.Mythic) then
    sequence.Mythic = tonumber(sequence.Mythic) - 1
  end
  table.remove(sequence.MacroVersions, version)
  printtext = printtext .. " " .. L["This change will not come into effect until you save this macro."]
  GSE.GUIEditorPerformLayout(editframe)
  GSE.GUIEditFrame.ContentContainer:SelectTab("config")
  GSE.GUIEditFrame:SetStatusText(string.format(printtext, version))
end
