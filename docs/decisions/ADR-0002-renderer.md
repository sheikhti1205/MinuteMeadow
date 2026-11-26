# 0002: Canvas rendering for companion sprites

Status: Accepted

Use a Flutter `CustomPainter` to composite ordered sprite layers. Draw cached atlas regions with nearest-neighbour sampling. Keep animation state and scene transforms outside the painter so they can be tested without a graphics context.

A game engine adds features the planned interactions do not require. The custom renderer leaves asset caching, layering, and pixel alignment to the app. The animation laboratory will expose those details for inspection.
