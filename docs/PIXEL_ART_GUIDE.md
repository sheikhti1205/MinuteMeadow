# Pixel art

Keep the canvas size, origin, and palette consistent across frames of a clip. Export layers on an integer grid with transparent backgrounds. Draw intentional pixel edges rather than relying on a smoothing filter.

Choose pivots around the points that should stay attached during movement. Check the outline at rest and at the ends of a motion, especially where a child layer crosses its parent. Use a replacement frame when rotation alone would make an outline unstable.

Use nearest-neighbour sampling and the largest useful integer scale that fits the available physical pixels. Test with non-square assets as well as a 48 × 48 test canvas.

Until companion art is accepted for production, use geometric rigs in the development build only. Keep attribution and redistribution terms for every included asset.
