-- Documented sample sequences.
--
-- These used to be hand-written WotLK class rotations. On Project Ascension a
-- character is classless and draws abilities from any tree, so a fixed
-- class/spec rotation referenced spells the character had never drafted. The
-- table is left empty rather than shipping rotations that cannot cast.
--
-- The loader and the /gse loadsamples command are kept so nothing that calls
-- them breaks; both report honestly that there is nothing to add.

local GSE = GSE
local L = GSE.L
local Statics = GSE.Static

Statics.DocumentedSampleMacros = {}

--- Add any documented sample macros for the current class to the library.
function GSE.LoadDocumentedSampleMacros()
    local currentClassID = GSE.GetCurrentClassID()
    local samples = Statics.DocumentedSampleMacros[currentClassID]

    if not samples or GSE.isEmpty(samples) then
        GSE.Print("No sample macros ship with the Ascension build - create your own with /gse.", "GSE")
        return
    end

    for sequenceName, sequence in pairs(samples) do
        if GSE.isEmpty(GSELibrary[currentClassID]) then
            GSELibrary[currentClassID] = {}
        end

        if GSE.isEmpty(GSELibrary[currentClassID][sequenceName]) then
            GSELibrary[currentClassID][sequenceName] = sequence
            GSE.Print("Sample macro added: " .. sequenceName, "GSE")
        end
    end
end

-- Add a slash command to load sample macros
SLASH_GSELOADSAMPLES1 = "/gse loadsamples"
SlashCmdList["GSELOADSAMPLES"] = function()
    GSE.LoadDocumentedSampleMacros()
end
