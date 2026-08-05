-- Example sequence. This file is NOT listed in GSE.toc, so the game never
-- loads it; it only documents the table shape a sequence uses.
--
-- Note: the spells below are from an earlier Ascension season and no longer
-- exist in the current client data (Titanic Mutilate, Ground Slam, Eldritch
-- Wrath, Fel Cleave, Warcry, Flameburst). Treat it as a syntax reference, not a
-- working rotation.
--
-- The multi-line entry previously used single quotes, which cannot span lines in
-- Lua, so this file did not parse at all.

Sequences['FiteStuff'] = {
    Author = "Me",
    Help = "Test",
    StepFunction = "Sequential",
    [[castsequence reset=target/8 Devastate, Titanic Mutilate, Thunder Clap, Ground Slam, Eldritch Wrath, Devastate, Fel Cleave, Titanic Mutilate
/cast Cold Blood
/cast Adrenaline Rush
/cast Warcry
/cast Shamanistic Rage
/cast Cleave]],
    '/cast [@player] Flameburst',
}
