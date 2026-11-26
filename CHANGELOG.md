# Changelog

Format: [keep a changelog](https://keepachangelog.com/en/1.1.0/).
Version headings match `manifest.json`'s `version`.

## [1.6] - 2026-11-26

### Added

- EXP SHARE: OFF / ON (GEN2) / ON (GEN6), on all eleven games.
  - ON (GEN2): after the normal award, the next Pokémon in the party (not
    fainted, not an egg, didn't fight) gets half the EXP and half the EVs or
    stat exp of each Pokémon that fought.
  - ON (GEN6): every non-fainted, non-egg Pokémon in the party gets EXP when
    a foe faints or is caught. Pokémon that fought get the full amount each;
    the rest get 50%. Every one of them gets the full EVs, level 100 included.
    A held EXP. SHARE has no effect in this mode.
  - Both modes pay through each game's own EXP routine, so level-ups, moves,
    evolutions, the traded and Lucky Egg boosts and Pokérus work as normal.
    That includes mods that split Gen 1's SPECIAL stat.

## [1.53] - 2026-11-25

### Fixed

- EDIT START MENU no longer rearranges rows on its own. The layout is now a
  single stored column in your order. The editor shows it, MOVE swaps two
  neighbouring rows in it, and the START menu is its rows sorted by that
  column with hidden ones left out. The old rules that ranked placed rows,
  appended "the rest" and kept QUIT last could reshuffle rows you'd placed
  (a row put below QUIT jumped back above it, for example). They're gone,
  on every game.
- A row that appears later (POKéDEX and POKéGEAR on Gold, Silver and
  Crystal, or a mod installed since) goes just above the row that follows it
  in the game's own menu, once, and stays wherever you then put it.

### Changed

- RUNNING SHOES (B TO RUN) on Gen 3 now lets you run anywhere you can walk,
  including indoors, in long grass, in hot springs, and on Pacifidlog's logs
  and Fortree's bridges. This works with or without the real shoes. Bike,
  surfing and underwater are unchanged.

## [1.52] - 2026-11-25

### Fixed

- EDIT START MENU's list was not always the START menu's order, so moves
  landed in the wrong place. The editor listed rows in the order the mod first
  saw them. On Crystal, POKéDEX and POKéGEAR unlock after that, so they sat at
  the bottom of the editor while the menu kept them near the top. A row that
  appeared after a layout was set was also placed differently in each (above
  QUIT in the menu, after it in the editor). The editor and the START menu are
  now laid out by the same code on every game, so the list you edit is the
  menu you get.

## [1.51] - 2026-11-25

### Fixed

- EDIT START MENU changes now show as soon as you back out of the editor.
  On Gold, Silver, Crystal and the Gen 3 games, the editor is reached from
  inside the START menu (START → OPTION → QOL COMP, or START → MODS). Those
  games go back to the START menu that was already open, built before the
  edit, so the new order or hidden rows didn't appear until START was closed
  and opened again. The open menu is now rebuilt after every MOVE, HIDE, SHOW
  and RESET LAYOUT. Red, Blue and Yellow already rebuilt it.

## [1.5] - 2026-11-25

### Fixed

- EDIT START MENU could list rows twice, slightly out of order. A row
  learned once by its id and once by its label is now one row. The editor
  lists only the rows the START menu actually shows, and a layout that
  was already doubled is repaired the first time it loads.
- The QOL COMP button in the game's OPTIONS screen opened the Mod Manager's
  mod list. It now opens QoL Comp's own toggles, on every game; B returns to
  OPTIONS.

### Changed

- RENAME is now in the PC too: on the menu a Pokémon opens in a box (and,
  on Gen 3, in the party list), just above CANCEL.
- RENAME also skips the "give a nickname?" question when a Pokémon joins
  you (catches, gifts, the Bug-Catching Contest and egg hatches on every
  game). It keeps its species name, as answering NO would.
- Shorter description in the Mod Manager.

## [1.4] - 2026-11-25

First public release.
