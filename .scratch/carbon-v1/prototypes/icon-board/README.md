# Icon board (PROTOTYPE, throwaway)

Answers the ticket "Icon board" (`../../issues/11-icon-board.md`).

Run: `open index.html` (no build). `?variant=all` is the overview; `A`–`E`, `C2`–`C4` are full boards. `←` / `→` cycle.

Each board shows the app icon from 256 to 16 px (carbon black and inverted) on light and dark wallpapers, the menu bar template icon at real size (18 pt) and at 5×, idle and recording, and the start notification.

## Round 2 (`index.html`): flat, minimal, carbon

| Key | Direction | Recording state |
| --- | --- | --- |
| A | Ring + voice: hexagon with three voice bars (round 1's B, flattened) | Bars become the red dot |
| B | Benzene: hexagon with a circle inside | Inner circle fills red |
| C | Graphene: three cells of the lattice, a dot at their junction cut free by a gap | The dot turns red |
| C2 | Graphene, soft: C with rounded hexagon corners | The dot turns red |
| C3 | Graphene, rounded ends: edges stop short of the dot on round caps, no masked cut | The dot turns red |
| C4 | Graphene, ultra soft: C3 with deeply rounded corners | The dot turns red |
| D | Element C: periodic-table tile, 6 and C | Red dot in the atomic number's corner |
| E | Diamond: flat gem outline | Lower facets give way to a red dot |

## Round 1 (`round-1.html`): rejected

Four glossy directions around "carbon copy" (Carbon sheet, Graphene ring, Voice to words, Double C). The author liked none; only the Graphene ring's flat menu bar glyph survived, as round 2's A.

The recording glyph is a non-template image (template images cannot carry red).

## Verdict

C4 (Graphene, ultra soft) won, black mark on white for now. Exported SVGs in `final/`; see the ticket's Answer.
