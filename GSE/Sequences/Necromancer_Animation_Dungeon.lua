-- Animation Necromancer - dungeon rotation, level 25
--
-- This file is NOT listed in GSE.toc, so the game never loads it. Paste the
-- block below into /gse -> Import.
--
-- Spell names, costs and cooldowns come from the character's own spellbook via
-- /gse dumpspells, not from the launcher's CharacterAdvancementData.json, which
-- lags the live server by months and disagrees with nearly every name here.
--
-- Everything except /startattack lives in the sequence, not in KeyPress.
-- KeyPress runs ahead of the step's line on every single press, and in practice
-- one /cast there was enough to stop the step's spell going off at all. Steps
-- do not have that problem: a step whose spell is not ready costs almost
-- nothing, because the next press is milliseconds away and carries the next
-- step. It also keeps the macro far below the 255 character cut - KeyPress is
-- 12 characters here, so the worst case is 51.
--
-- The economy this is built around:
--   Runic Power generators  Lichfrost (2.27s cast), Crypt Swarm (channel),
--                           Glacial Tap (30 RP instant, 12s cooldown)
--   Runic Power spenders    Command: Undead 30, Corpse Explosion 40,
--                           Harvest Plague 20
--
-- On their own keys, deliberately not in here:
--   /cast !Crypt Swarm          channelled, and 3.3.5 has no [channeling]
--                               conditional to stop the next step cancelling it
--   /cast Bone Ward             30 minute buff; in KeyRelease with [nocombat]
--                               it fires on every press while out of combat and
--                               jams the whole rotation
--   /cast Grave March           re-point the minions when you swap target

Sequences['NecroAnimDungeon'] = {
    Author = "Wearemany@Rexxar - Conquest of Azeroth",
    SpecID = 1251,                      -- Animation - Necromancer (files under class 25)
    Talents = "Animation",
    Default = 1,
    Icon = "Spell_Shadow_AnimateDead",
    Help = "Animation Necromancer, level 25, 5-man. Lichfrost builds Runic Power, Command: Undead spends it. Crypt Swarm, Bone Ward and Grave March go on their own keys.",
    MacroVersions = {
        [1] = {
            StepFunction = "Sequential",

            -- Left unset these inherit GSEOptions, where use13 and use14 are on,
            -- and two /use lines appear in KeyRelease that the editor never
            -- shows you.
            Head = false, Neck = false, Belt = false,
            Ring1 = false, Ring2 = false, Trinket1 = false, Trinket2 = false,

            KeyPress = {
                "/startattack",
            },

            -- Once at the start, and again after each combat drop. These fail
            -- harmlessly at full Life Force, so they only cast for minions that
            -- actually died.
            PreMacro = {
                "/cast Raise: Greater Skeletal Warrior",
                "/cast Raise: Crypt Fiend",
                "/cast Raise: Ghoul",
            },

            -- Twelve steps, Lichfrost on six of them. Everything else waits on
            -- the Runic Power it generates, so it has to dominate.
            "/cast Lichfrost",
            "/cast Animate: Skeletal Archer",
            "/cast Lichfrost",
            "/cast Command: Undead",
            "/cast Lichfrost",
            "/cast Corpse Explosion",
            "/cast Lichfrost",
            "/cast Harvest Plague",
            "/cast Lichfrost",
            "/cast Unholy Frenzy",
            "/cast Lichfrost",
            "/cast Command: Undead",

            PostMacro = {},
            KeyRelease = {},
        },
    },
}
