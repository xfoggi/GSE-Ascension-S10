# GSE2: Gnome Sequencer Enhanced

## 2207-wotlk-s10 (Ascension)

- Every field in the sequence editor carries a help icon. The text describes how
  the addon behaves rather than how it was documented, so the traps are stated
  outright: PostMacro is unreachable in a looping sequence; a line in PreMacro
  or a value in Inner Loop Limit costs Priority its weighting; unticked item
  slots follow the global option rather than being off.
- KeyPress must never hold a spell you can run out of resource for. A spell on
  cooldown reports itself unusable and the macro moves to the next line, but a
  spell you merely cannot afford still counts as usable: it claims the single
  cast the press allowed, errors, and nothing below it runs. With the resource
  generator in the sequence, a spender in KeyPress is a deadlock, not a stall.
- A live "Macro: n / 255" readout, counted through PrepareKeyPress and
  PrepareKeyRelease so it includes the lines GSE adds that appear in none of the
  boxes. Its help lists what each option costs: Prevent Sound Errors 226
  characters, Require Target 74, Prevent UI Errors 30, Clear UI Errors 27, and
  17 per ticked item slot.
- Holding for a channel no longer blanks the macro. It uses KeyPress with the
  casting lines stripped, so /startattack keeps working while nothing can cancel
  the channel.
- /gse dumpbutton reports UnitChannelInfo and the size of that stripped
  KeyPress, so a client that believes you are permanently channelling is visible
  rather than mysterious.
- Saving falls back to the name the editor was opened with when the name box has
  been blanked, rather than failing on an empty name.
- tools/check-lua-syntax.py compiles against Lua 5.1, the version the game runs.
  lupa's default runtime is far newer and accepts syntax 3.3.5a rejects.

## 2206-wotlk-s10 (Ascension)

- Sequences stand down while a channel is running instead of cancelling it. Any
  /cast issued during a channel clips it, so a spammed sequence containing a
  channelled spell never completed a tick. PlayerIsChanneling is one of the few
  pieces of player state FrameXML/RestrictedEnvironment.lua exposes to a secure
  snippet, so the snippet can now see it. On by default per macro version, as
  "Hold while channelling". There is no equivalent for ordinary casts: the
  restricted environment has no PlayerIsCasting and no GetTime, so a time based
  throttle is not possible.
- The macro overflow warning no longer repeats on every button rebuild, states
  the real character total, and names Prevent Sound Errors.
- Reset modifiers use the correct sided calls again. Only IsAnyModKeyDown does
  not exist, so AnyMod maps to IsModifierKeyDown.

## 2205-wotlk-s10 (Ascension)

- Saving a sequence from the editor was unreliable and said so nowhere. AceGUI
  fires a widget's OnTextChanged while releasing it, handing over the text it
  has just blanked, and an EditBox does not gate that on user input; the
  sequence name, Author, Talents, Help and Helplink were all wiped that way, so
  every save after the first hit the empty-name guard and quietly did nothing.
- Saving now reads the widgets directly instead of relying on those callbacks
  having fired, and snapshots the sequence when queueing rather than handing
  over the editor's live table.
- Import mangled what it was given. GSE.TrimWhiteSpace deleted every space in
  the string instead of trimming the ends, so "/cast Grave March" arrived as
  "/castGraveMarch" - the Lua still parsed, which is why it went unnoticed.
  StripControlandExtendedCodes used the byte value of the tenth character as a
  substring end index and corrupted anything pasted with CRLF endings.
- PrintKeyModifiers concatenated GetMouseButtonClicked(), which returns nil
  outside a mouse click. The snippet died before setting macrotext, so the
  button clicked with an empty macro and cast nothing at all.
- OOCAddSequenceToCollection skipped its merge once a sequence had been edited,
  and otherwise appended one duplicate version per stored version. Errors from
  the out of combat queue went to a debug module that could never be enabled.
- New diagnostics, since none of the above was visible from inside the game:
  /gse dumpspells writes the character's spellbook with cast times, costs and
  tooltips to GSEOptions.SpellDump; /gse dumpbutton <name> reports a sequence's
  live button; /gse clearlog empties GSEOptions.DebugLog. These live in
  GSEOptions because names added to ## SavedVariables are not picked up by this
  client.


## [2.6.55](https://github.com/TimothyLuke/GnomeSequencer-Enhanced/tree/2.6.55) (2021-06-09)
[Full Changelog](https://github.com/TimothyLuke/GnomeSequencer-Enhanced/compare/2.6.54...2.6.55) [Previous Releases](https://github.com/TimothyLuke/GnomeSequencer-Enhanced/releases)

- #846 Update ranks to internal API  
- #846 Dont print pcall passed  
- #846 Use GetSpellSubtext to obtain rank information.  
- #841  
    Build on Tag  
- #841 Update CI.yml  
- Migrate from Travis to Google Actions  