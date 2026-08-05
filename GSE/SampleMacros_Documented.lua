-- Documented sample sequence.
--
-- GSE used to bundle WotLK class rotations here (Arms Warrior, BM Hunter, ...).
-- On Project Ascension a character is classless and drafts abilities freely, so
-- a fixed class/spec rotation referenced spells the character had never learned.
-- Those are gone.
--
-- What is left is ONE annotated example whose only job is to document the
-- sequence format. It is filed under class 0 (Global), which is where Ascension
-- sequences belong, and every spell in it exists in the current client data -
-- but it is NOT a rotation to use. Ability priorities depend entirely on your
-- own draft, and nothing in the client data expresses them.
--
-- Load it with /gse loadsamples, then open it in /gse to see how the pieces fit.

local GSE = GSE
local L = GSE.L
local Statics = GSE.Static

Statics.DocumentedSampleMacros = {}

-- Class 0 is "Global" - the right home for Ascension sequences, since the
-- character's class is not what decides which spells it can cast.
Statics.DocumentedSampleMacros[0] = {
    ["_GSE_Format_Example"] = {
        -- Metadata shown in the viewer.
        Author = "GSE",
        SpecID = 0,                       -- 0 = Global. See Statics.wotlkSpecIDList.
        Help = "Format reference only - NOT a usable rotation. Ascension is classless, so build your own sequence around the abilities you actually drafted.",
        Icon = "INV_MISC_QUESTIONMARK",
        Default = 1,                      -- which MacroVersions entry to use

        -- A sequence can hold several versions; GSE picks one based on context
        -- (Default, plus optional PVP / Raid / Dungeon / Heroic / Party keys).
        MacroVersions = {
            [1] = {
                -- StepFunction controls how the numbered steps advance:
                --   "Sequential" walks 1,2,3,4,...  (each click = next step)
                --   "Priority"   walks 1,1,2,1,2,3,... (early steps retried first)
                StepFunction = "Sequential",

                -- PreMacro runs once before the stepped lines on every click.
                PreMacro = {
                    "/targetenemy [noharm][dead]",
                },

                -- KeyPress fires on the button press, before the current step.
                -- Good place for things that must happen every click: starting
                -- your swing, clearing errors, off-GCD cooldowns.
                KeyPress = {
                    "/startattack",
                    "/cast [combat] Icy Veins",
                },

                -- The numbered steps. One is consumed per click, in the order
                -- StepFunction dictates. These are plain macro lines, so all the
                -- usual 3.3.5a conditionals work.
                "/cast Frostbolt",
                "/cast [mod:shift] Cone of Cold; Fireball",   -- shift picks the alternative
                "/cast [harm,nodead] Arcane Missiles",
                -- castsequence advances on its own and resets after 8 seconds
                -- without a cast, or when the target changes:
                "/castsequence reset=target/8 Frost Nova, Cone of Cold",
                "/cast [@player] Mirror Image",               -- @unit targeting
                "/cast [combat,mod:alt] Presence of Mind",

                -- KeyRelease fires when the button is released, after the step.
                KeyRelease = {
                    "/cast [nocombat] Evocation",
                },

                -- PostMacro runs once after the stepped lines.
                PostMacro = {
                    "/cast [harm] Counterspell",
                },

                -- Optional loop control, all off by default:
                --   loopstart / loopstop  restrict cycling to a range of steps
                --   looplimit             how many times that range repeats
                -- e.g. loopstart=2, loopstop=4, looplimit=3 gives
                -- 1,2,3,4,2,3,4,2,3,4,5,...
            },
        },
    },
}

--- Add the documented sample to the library.
--    Looks under the character's class ID and under Global, because on Ascension
--    the useful samples are the class-less ones.
function GSE.LoadDocumentedSampleMacros()
    local added = 0

    for _, classID in ipairs({ GSE.GetCurrentClassID(), 0 }) do
        local samples = Statics.DocumentedSampleMacros[classID]

        if not GSE.isEmpty(samples) then
            for sequenceName, sequence in pairs(samples) do
                if GSE.isEmpty(GSELibrary[classID]) then
                    GSELibrary[classID] = {}
                end

                if GSE.isEmpty(GSELibrary[classID][sequenceName]) then
                    GSELibrary[classID][sequenceName] = sequence
                    GSE.Print("Sample macro added: " .. sequenceName, "GSE")
                    added = added + 1
                end
            end
        end
    end

    if added == 0 then
        GSE.Print("Nothing to add - the sample is already in your library. Open it with /gse.", "GSE")
    else
        GSE.Print("This sample documents the sequence format; it is not a rotation. Type /gse to open it.", "GSE")
    end
end

-- Add a slash command to load sample macros
SLASH_GSELOADSAMPLES1 = "/gse loadsamples"
SlashCmdList["GSELOADSAMPLES"] = function()
    GSE.LoadDocumentedSampleMacros()
end
