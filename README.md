# QoL Comp

A quality-of-life compilation for **Gen 1, Gen 2 and Gen 3**: fifteen
toggles, a START menu editor and a few small always-on fixes, in one mod.
Every toggle starts at the normal game, so installing it changes nothing
until you turn something on.

- **Faster everyday play:** hold the d-pad to scroll menus, run with B, a
  quicker Pokémon Center, TMs that aren't used up.
- **More control:** rename and relearn moves from the party menu, use field
  moves without teaching them, pick who leads a battle, rematch beaten
  trainers.
- **Easier on the eyes:** normal-case text instead of ALL CAPS, a centred
  camera on the Game Boy games, full-screen menus on the GBA games.
- **Your START menu, your way:** move or hide any row, including rows other
  mods add.

## Install

**Easiest:** in the game's launcher, use **Import mod .zip** (or just drag
`QoL-Comp-v1.4.zip` onto the game window). Works the same on Windows, Mac and
Linux.

**Manually:** unzip `QoL-Comp-v1.4.zip` into a `qol_comp` folder inside the
game's `mods` folder:

| OS | Mods folder |
| --- | --- |
| Windows | `%APPDATA%\LOVE\pokemon-love2d\mods\qol_comp` |
| macOS | `~/Library/Application Support/LOVE/pokemon-love2d/mods/qol_comp` |
| Linux | `~/.local/share/love/pokemon-love2d/mods/qol_comp` |

(Portable installs keep `mods` in the game's own folder instead.)

Either way, finish by enabling **QoL Comp** in the Mod Manager (`F10`) or a
profile.

Supports Red/Blue/Yellow, Gold/Silver/Crystal, and
Ruby/Sapphire/Emerald/FireRed/LeafGreen.

## Options

The options are in two places, and both show the same settings:

- **Mod Manager** (`F10`) → **QoL Comp** → **OPTIONS**
- the game's own **OPTIONS** screen → **QOL COMP**, at the bottom of the list

**EDIT START MENU** is at the top, followed by the toggles in alphabetical
order. **RESET DEFAULTS** at the bottom puts every toggle back to the normal
game (your START menu layout is kept).

| Option | Values | What it does |
| --- | --- | --- |
| `EDIT START MENU` | press A | Opens the START menu editor (see below). |
| `CENTER CAMERA` | OFF / ON | *Gen 1/2 only.* Puts the player on the true centre of the screen. The Game Boy screen is an even 10 tiles wide, so the original sits the player half a tile left of centre. |
| `CHOOSE PKMN` | OFF / TRAINER / T+WILD | The opponent comes out first, then you choose which Pokémon to send out. TRAINER asks in trainer battles; T+WILD in wild battles too. B keeps your normal lead. |
| `DECAPITALIZATION` | OFF / ON | Changes ALL-CAPS text to normal case in dialogue, battles and menus. |
| `FAST POKECENTER` | OFF / FAST / NOW | FAST: the nurse's first line, then straight to healing. NOW: heals with no text at all. Either way you're turned away from the counter afterwards. |
| `FIELD MOVES` | OFF / ON | A Pokémon can use a field move it doesn't know, if you have the TM/HM, it could learn the move, and the move would work right where you are. |
| `FULL SCREEN MENUS` | OFF / ON | *Gen 3 only.* Full-screen menus (bag, party, summary, Pokédex, PC) are scaled up to the window's height. |
| `GAMBLE ODDS` | NORMAL / LUCKY | LUCKY makes the Game Corner pay out about twice as often. |
| `HIDDEN ITEM SHINE` | OFF / ON | A small twinkle shows where a hidden item is. |
| `KEEP TMS` | OFF / ON | TMs aren't used up when you teach them. |
| `LOW HP BEEP` | ON (BEEPS) / OFF (MUTED) | OFF (MUTED) silences the low-HP alarm. ON (BEEPS) is the normal game. |
| `RELEARN MOVES` | OFF / ON | Adds a RELEARN row to the party menu. |
| `REMATCH` | OFF / ON (NORMAL) / ON (TRAINING) | Rematch any trainer you've beaten. TRAINING scales their team to your progress. |
| `RENAME` | OFF / ON | Adds a RENAME row to the party menu. |
| `RUNNING SHOES` | OFF / B TO RUN | Hold B to run. |
| `SCROLLING` | OFF / NORMAL / FAST | Hold the d-pad in a menu and the cursor keeps moving. |

### Edit Start Menu

Press A on an entry to get **MOVE** and **HIDE** (or **SHOW** for a hidden
one). MOVE picks the entry up; UP/DOWN carries it and A or B puts it down.

- Each generation keeps its own layout.
- Rows added by other mods (like GAMESHARK) can be moved and hidden too. A
  row from a mod you install later goes to the end of the menu.
- **MODS** can be moved but never hidden, so the Mod Manager is always
  reachable. QUIT stays last.
- **RESET LAYOUT**, the last row, restores the game's own order and shows
  everything again.
- The editor lists what the START menu showed the last time it was opened, so
  open the START menu once before your first edit, and again after installing
  a mod that adds a row.

### More on each option

**Choose Pkmn.** The battle opens as normal; when the opponent is out, the
party list opens and the Pokémon you pick is sent out exactly as your first one
would have been. Your party order doesn't change, and it doesn't count as a
switch. Fainted Pokémon and eggs can't be picked, and if only one Pokémon can
battle you aren't asked. Link, Safari, Bug-Catching Contest and tutorial
battles are left alone.

**Decapitalization.** Names and menu words become Title Case (PALLET TOWN →
Pallet Town, QUICK ATTACK → Quick Attack, ITEM / RUN → Item / Run, HALL OF FAME
→ Hall of Fame). A sentence written in capitals gets sentence case ("WHAT IS
IT?" → "What is it?"). Abbreviations keep their capitals (TM, HM, PKMN, HP, PP,
PC, ID, OK), and so does any word with a digit in it (TM01, B1F). No word
changes length, so nothing moves or re-wraps. Braille is left alone.

**Field Moves.** The move appears in the Pokémon's party menu only when it
would work right now, decided by the game's own check: SURF facing water,
WATERFALL / WHIRLPOOL facing one, DIVE on a dive spot, CUT facing a cuttable
tree, HEADBUTT facing a Headbutt tree, ROCK SMASH facing a breakable rock,
STRENGTH facing a boulder, FLASH in an unlit cave, FLY / TELEPORT outdoors, DIG
in a cave, SWEET SCENT where wild Pokémon live, SECRET POWER facing a base
spot, SOFTBOILED / MILK DRINK with HP to spare.

- You need the HM's badge, as normal.
- No TM/HM in the bag, no row. A move no TM/HM teaches (TELEPORT, SOFTBOILED,
  MILK DRINK) works only for a Pokémon that knows it.
- The menu still holds eight rows; extra moves don't appear.

**Rename.** Opens the naming screen with an empty keyboard, like the Name
Rater. Confirming with nothing typed (or the same name) keeps the old name, and
the game tells you which happened. Not shown in battle or for eggs.

**Relearn Moves.** Lists every level-up move the Pokémon could know at its
level but doesn't right now, read from the game's current data (so learnset
mods are respected). Pick one and the game's normal "forget a move?" screen
takes over. On Gen 3 it opens the game's own Move Relearner.

**Rematch.** Talk to a beaten trainer and they ask *"Would you like a
rematch?"*. NO gives their usual line; YES starts the battle.

- **ON (NORMAL):** the same team as the first time.
- **ON (TRAINING):** the team is scaled to you. Their strongest Pokémon matches
  your level, and the rest keep the same gaps below it. Your level is
  whichever is higher: the usual level for your badge count, or your team's
  average.
- Gen 1/2: rematches don't give badges or TMs again. Gen 3: the trainer's own
  script runs the battle, and they're marked as beaten again afterwards.

**Running Shoes.**

- Gen 1/2: hold B while walking to move about 1.78× faster, with a quicker
  walk animation to match. Not on a bike, while surfing, or on slopes.
- Gen 3: the game's own Running Shoes, unlocked from the start, with the
  game's own speed and animation, everywhere running is normally allowed.
  Once you get the real shoes, nothing changes.

**Scrolling.** FAST waits 14 frames, then moves every 8. NORMAL is gentler: 19
frames, then every 11.

**Gamble Odds.** Covers the slot machines on every game and Gold/Silver/
Crystal's Card Flip. Emerald's roulette isn't changed.

**Fast Pokecenter.** The healing animation still plays in both modes.

**Full Screen Menus.** Menus that sit over the field (START, yes/no boxes)
and the field itself are drawn as normal. If you also use
*Gen3-Full-Height-Menus*, turn this off.

## Always on

| Change | Games |
| --- | --- |
| **Shop bag count:** the highlighted item in a shop shows how many you already have, as "×6 in bag". | all |
| **SELECT quick switch:** in the party menu, SELECT on a Pokémon, then A or SELECT on another, swaps them. B cancels. | all |
| **Bigger bag:** up to 999 of an item in one stack. On Gen 1/2 the item pocket also holds 255 different items. | all |
| **EXP bar:** in battle under your HP bar, and in the party menu. | Red/Blue/Yellow |
| **Caught icon:** a ball marker next to wild Pokémon you already own. | Red/Blue/Yellow |
| **Gen 2 bag:** with Gold, Silver or Crystal imported, the bag uses Gen 2's four pockets. LEFT/RIGHT switches pockets. | Red/Blue/Yellow |

## Things to know

- **Gen 3 bigger bag:** stacks go to 999, but each pocket keeps its usual
  number of slots. Adding slots would break Gen 3 saves.
- **Gen 1/2 running** is 1.78×, not a round number: the game moves in whole
  frames per step, and a 9-frame step is the closest it gets to 1.7×.
- **Translation mods:** DECAPITALIZATION's word lists are English, so in a
  translated game it only fixes names that are still in capitals.
- Each feature switches itself off and logs a warning if the part of the game
  it relies on is missing, rather than crashing.
- If anything looks wrong, turn that option off. The normal game returns
  straight away.
- The QoL toggles can be overridden by other UI mods without issue, like bag count in a shop being on but another    mod might change how the shop works entirely.  

## Credits

**Contributors**

- **Theeohn**: author.
- **Claude** (Anthropic): co-developer.

**With thanks to the modders whose work this builds on**

- **piftee**: [gen1recomp-modern-ui-suite](https://github.com/piftee/gen1recomp-modern-ui-suite), **Nexhas28**: [qol_toggles](https://github.com/Nexhas28/qol_toggles), and **Waifu4Life**: [Project-Highlander-Gen3](https://github.com/Waifu4Life/Project-Highlander-Gen3). Used as references for where quality-of-life features hook into the game.
- **WizzStar**: [PKMN-G123R-HoldToScroll-Mod](https://github.com/WizzStar/PKMN-G123R-HoldToScroll-Mod) (MIT). SCROLLING is adapted from it.
- **Panduino**: [Gen3-Full-Height-Menus](https://github.com/Panduino/Gen3-Full-Height-Menus/). FULL SCREEN MENUS is adapted from it.
- **ZyranCZ**: [Trainers-Let-You-Choose-Lead-Pokemon](https://github.com/ZyranCZ/Trainers-Let-You-Choose-Lead-Pokemon). CHOOSE PKMN follows its approach of placing the choice inside the battle's own opening.
- **Nezara**: [gen1recomp-centered-camera](https://github.com/Nezara/gen1recomp-centered-camera). CENTER CAMERA is built on its explanation of the 8-pixel offset.
- Built for the Pokémon Gen 1 Recompilation Project by BOIS CLUB GAMES, LLC
  (https://github.com/bryanthaboi/gen1recomp).

## License

GPL-3.0 (see `LICENSE`), matching the project it builds on. The adapted
HoldToScroll code is MIT; its licence notice is at the top of `lib/scroll.lua`.
