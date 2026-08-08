-- Animation Necromancer - dungeon rotation, level 25+
--
-- This file is NOT listed in GSE.toc, so the game never loads it. Paste the
-- block below into /gse -> Import.
--
-- Spell names, costs and cooldowns come from the character's own spellbook via
-- /gse dumpspells, not from the launcher's CharacterAdvancementData.json, which
-- lags the live server by months and disagrees with nearly every name here.
--
-- Why it is shaped like this, in the order the lessons were learned:
--
-- PreMacro and PostMacro are empty ON PURPOSE. GSE.IsLoopSequence flips the
-- step function to its looping variant as soon as either holds a line, or when
-- Inner Loop Limit is set, and the looping variant of Priority collapses into
-- plain sequential walking after roughly twenty presses. Leave all three empty
-- and Priority keeps its weighting permanently:
--
--   Command: Undead           28.6% of presses
--   Harvest Plague            23.8%
--   Corpse Explosion          19.0%
--   Crypt Swarm               14.3%
--   Animate: Skeletal Archer   9.5%
--   Unholy Frenzy              4.8%
--
-- Nothing that costs Runic Power may go in KeyPress. A spell on cooldown
-- reports itself unusable and the macro moves to the next line, but a spell you
-- merely cannot afford still counts as usable: it claims the single cast that
-- press allowed, errors, and everything below it - the step included - never
-- runs. Since the step is where Crypt Swarm lives, and Crypt Swarm is the only
-- source of Runic Power, that is not a stall but a deadlock. Every spender
-- therefore sits in the sequence, where each has its own press and can block
-- nothing.
--
-- KeyPress holds only what is free: /startattack, and Grave March, which costs
-- nothing, has a 2 second cooldown and is flagged usable while casting or
-- channelling, so it can neither block nor clip.
--
-- Hold while channelling is on, so a Crypt Swarm channel runs to the end
-- instead of being cancelled by the next press.
--
-- Worst case macro: 91 of the 255 characters WoW allows.
--
-- On their own keys, deliberately not in here:
--   /cast Undead: Assault   minion stance, set once before the pull
--   /cast Bone Ward         30 minute buff
--   /cast Raise: ...        summons, cast when a minion actually dies

Sequences['NecroPrio1'] = {
    Author = "Wearemany@Rexxar - Conquest of Azeroth",
    SpecID = 1251,                      -- Animation - Necromancer (files under class 25)
    Talents = "Animation",
    Default = 1,
    Icon = "Spell_Shadow_AnimateDead",
    Help = "Animation Necromancer, level 25+. Priority weighted: spenders first, Crypt Swarm tops the Runic Power back up. PreMacro and PostMacro must stay empty or Priority degrades to Sequential.",
    MacroVersions = {
        [1] = {
            StepFunction = "Priority",
            ChannelHold = true,

            -- Left unset these inherit GSEOptions, where use13 and use14 are on,
            -- and two /use lines appear in KeyRelease that the editor never
            -- shows you but the 255 character limit still counts.
            Head = false, Neck = false, Belt = false,
            Ring1 = false, Ring2 = false, Trinket1 = false, Trinket2 = false,

            KeyPress = {
                "/startattack",
                "/cast Grave March",
            },

            -- Must stay empty: one line here and Priority stops weighting.
            PreMacro = {},

            "/cast Command: Undead",
            "/cast Harvest Plague",
            "/cast Corpse Explosion",
            "/cast Crypt Swarm",
            "/cast Animate: Skeletal Archer",
            "/cast Unholy Frenzy",

            PostMacro = {},
            KeyRelease = {},
        },
    },
}
