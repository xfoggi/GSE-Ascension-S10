local GSE = GSE
local Statics = GSE.Static

-- The bundled sample macros were WotLK class rotations (Arms Warrior, Beast
-- Mastery Hunter and so on) inherited from the retail addon. Project Ascension
-- is classless: a character mixes abilities from any tree, so a rotation built
-- around a fixed class spec cast nothing a real Ascension character had learned
-- and only produced "unknown spell" noise.
--
-- The table stays defined so GSE.LoadSampleMacros and the /gse loadsamples
-- command keep working; there is simply nothing to load. Build sequences for
-- your own draft instead, and share them via the import/export tab.
Statics.SampleMacros = {}
