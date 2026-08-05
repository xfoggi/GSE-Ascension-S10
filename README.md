# GSE (Gnome Sequencer Enhanced) for WoW 3.3.5a/Project Ascension -Season 10-

A revival and restoration of Gnome Sequencer Enhanced for World of Warcraft 3.3.5a (Wrath of the Lich King).

## About

Almost all of this is the same as Cerberus's original GSE Backport update. I simply took his and Gummed's legwork and then added a few fixes and added support for use with the Project Ascension client as the original implementation didnt work properly, throwing errors in the ascension client, and had no means to load custom spells and abilities that werent properly registered in the default client.

GSE (Gnome Sequencer Enhanced) is an advanced macro sequencer for World of Warcraft that allows players to create and execute complex macro sequences, bypassing normal macro limitations. This version has been specifically restored and fixed for WoW 3.3.5a compatibility and then further iterated on with fixes and edits to allow usage with Project Ascensions custom client.

**Original Author**: TimothyLuke  
**WotLK Backport**: Gummed (Warmane) - abandoned  
**Revival & Fixes**: cerberus (January 2025)
**Adapted for Ascension**: dmjohn0x (August 2025)

## Features

- Create complex macro sequences that execute with a single button press
- Bypass the 255 character macro limit
- Support for conditional execution (PvP, Raid, Dungeon, Heroic, Party)
- Import/Export sequences for sharing
- Multi-language support
- Spell tables generated from the live Ascension client data, so custom abilities resolve
- Class/spec lists covering Ascension's hero classes and Reborn trees
- Full GUI for easy sequence management

## Installation

1. Download the latest release
2. Extract the folder to your `World of Warcraft/Interface/AddOns/` directory
3. Ensure the folder structure looks like:
   ```
   Interface/
   └── AddOns/
           ├── GSE/
           ├── GSE_GUI/
           └── GSE_LDB/
   ```
4. Enable all three GSE modules in your addon selection screen

## Usage

### Basic Commands
- `/gse` - Open the main interface
- `/gse help` - Show help information
- `/gse showspec` - Show your current specialization
- `/gse debug` - Toggle debug mode

### Creating Your First Macro
1. Type `/gse` to open the interface
2. Click "Create New Sequence"
3. Give your sequence a name
4. Add your macro commands (one per line)
5. Save and create the macro icon
6. Drag the icon to your action bar

### Choosing a Class/Specialization
Project Ascension is classless, so **"Global"** remains the right choice for most
sequences. The dropdown does now list Ascension's own classes - the hero classes
(Necromancer, Chronomancer, Tinker, Runemaster, ...) and the Reborn trees - if you
prefer to file sequences under one of them.

No sample macros ship with this build. The ones GSE used to bundle were WotLK
class rotations that referenced spells an Ascension character never drafts, so
`/gse loadsamples` had nothing useful to add and has been retired.

## Ascension Data (Season 10)

The spell name/ID tables and the class/spec lists are **generated** from the data
files the Ascension launcher ships, not hand-maintained:

| File | Contents |
|---|---|
| `GSE/Localization/enUS.lua` | spell ID → name |
| `GSE/Localization/enUSHash.lua` | name → spell ID |
| `GSE/Localization/enUSSHADOW.lua` | lower-cased name → spell ID |
| `GSE/API/AscensionData.lua` | class, spec and tree tables |

Source of truth is `CharacterAdvancementData.json` under
`<launcher>/resources/ascension-live/Data/Content`. Only `Ability` and
`TalentAbility` records are used - `Trait`/`Talent` records are passive nodes and
255 of them share a name with a real ability, so including them would let a
passive win the name→ID lookup and quietly break `/cast`.

### Regenerating after a patch or a new season

```powershell
.\tools\generate-ascension-data.ps1        # rebuild the four generated files
.\tools\validate-generated-data.ps1        # duplicate keys, hash→key consistency
python tools\check-lua-syntax.py           # every addon file still parses
python tools\smoke-test.py                 # class/spec plumbing under a mock API
```

The Python tools need `pip install lupa`. Pass `-ContentPath` to the generator if
your launcher is not at `C:\Ascension\Launcher`.

## What's Been Fixed

This revival addresses numerous issues from the abandoned original:

### Critical Fixes
- ✅ Fixed 20+ typos and naming errors that caused crashes
- ✅ Added comprehensive nil checking to prevent errors
- ✅ Full WoW 3.3.5a API compatibility (removed modern API calls)
- ✅ Fixed global variable pollution
- ✅ Removed 17,548 lines of duplicate code (5MB+ reduction)
- ✅ Fixed performance issues with caching and string operations

### Compatibility Updates
- Removed unsupported events (GROUP_ROSTER_UPDATE, PLAYER_SPECIALIZATION_CHANGED)
- Fixed difficulty checks for 3.3.5a
- Updated talent system detection for pre-MoP design
- Removed BackdropTemplateMixin usage

### New Features
- Improved error handling and user messages
- Better defensive programming throughout

### Season 10 Conversion
- Spell tables rebuilt from live Ascension data: **3,889 spell IDs / 3,558 names**,
  up from 1,907 - of which 1,710 were retail spells that do not exist on Ascension
- Corrected 30 spell IDs that carried retail names, which the translator had been
  actively mistranslating (ID 99 is *Demoralizing Roar* on Ascension, not retail's
  *Incapacitating Roar*; 1719 is *Recklessness*, not *Battle Cry*)
- Class/spec tables regenerated: **42 classes, 145 trees**, replacing the 9 hardcoded
  WotLK classes. The twelve base class IDs are unchanged so existing saved macros
  still resolve
- Fixed spec detection: Ascension's `GetTalentTabInfo` returns `id` first and adds
  `isUnlocked`, so reading it with the stock signature fed a description string into
  a numeric comparison and errored out
- `GSE.GetCurrentClassID()` now always returns a number; it used to return `""` when
  no class matched, filing macros under an unreachable `GSELibrary[""]` key
- Fixed the translator's case-insensitive fallback, which checked the shadow table
  with a spell ID (a name-keyed table) and therefore never matched

## Technical Details

Built using:
- Ace3 Framework
- LibStub for library management
- LibDataBroker for minimap integration
- Lua 5.1 (WoW 3.3.5a embedded)

## Known Limitations

- Some operations fail during combat due to Blizzard's combat lockdown
- Spec detection uses talent tree analysis (pre-specialization era)
- Maximum of 120 character macros + 18 account macros
- Conflicts with TSM cause taint, breaking GSE. Dont use TSM with GSE.

## Contributing

This revival was done by cerberus after Gummed's WotLK backport was abandoned. TimothyLuke continues to maintain GSE for retail WoW. Contributions welcome!

### Development Guidelines
1. Maintain WoW 3.3.5a compatibility
2. Always use local variables (avoid globals)
3. Add nil checks for all WoW API calls
4. Test thoroughly before submitting

## Version History

- **2.2.04-wotlk-s10** - Season 10 data conversion
  - Spell and class/spec tables generated from live Ascension client data
  - Spec/class detection fixed for Ascension's `GetTalentTabInfo` signature
  - WotLK sample macros removed
  - Added `tools/` for regeneration and verification

- **2.2.04-wotlk** (January 2025) - Complete revival for 3.3.5a by cerberus
  - Fixed all critical bugs and crashes
  - Added sample macros for all classes
  - Full compatibility restoration
  - Based on Gummed's backport of GSE 2.x
  
- **2.2.03** - Last known version backported to 3.3.5a by Gummed (abandoned)

Note: Current retail GSE is version 3.2.x and is a complete rewrite by TimothyLuke

## License

Original GSE by TimothyLuke is released under the MIT License.  
This WotLK backport and revival maintains the same open-source spirit.  
See https://github.com/TimothyLuke/GSE-Advanced-Macro-Compiler for the original project.

## Support

There is no support. Cerberus doesnt play Ascension and I'm only going to maintain this as I play new seasons. The official Modding discord for Ascension mods "SzylerAddons" actually despises GSE and doesn't want the addon discussed there. (They see it as harmful to the game rather than an accessibilty mod) So be respectful of their wishes and do not ask for support there.

## Acknowledgments

- **TimothyLuke** - Original author of GSE (still maintains retail version)
- **Gummed** - Created the WotLK 3.3.5a backport
- **semlar** - Original GnomeSequencer creator
- **cerberus** - for Updating Gummed's backport.
- WoW addon community for keeping Classic servers and World of Warcraft as a whole, alive.

---

*This addon is not affiliated with or endorsed by Blizzard Entertainment.*
