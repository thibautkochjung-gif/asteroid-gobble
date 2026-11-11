# Station art generator

Draws Union Ring Four (the hub map) as pixel art, procedurally, then hand-placed details on top.
Output goes to `godot_art/` next to these scripts: copy those PNGs to `Hub/Art/`.

    python build.py

Needs Python 3 with numpy and Pillow. `build.py` also renders a second, rejected direction (close
on the rim) and preview images for the design mockups: only the `godot_art/` files are used by the game.

- `station.py`: the drawing kit (ring segments, spokes, drydock, guild tower, containers, radiators...).
- `build.py`: the layout. Angles are in degrees, clockwise from the right. Hand-placed details are
  after the `ring(...)` call (lettering, patches, gantry, dishes).

If you move a part, also move its callout anchor in `Hub/hub.gd` (AREAS) and the lights (NAV_LIGHTS).
