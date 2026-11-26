# Animation laboratory

Open **Settings → Animation laboratory** in a debug build or a web build with [development tools enabled](TESTING_STRATEGY.md). The lab starts with a geometric rig and imports standalone rigs separately from the companion library.

Choose a clip, set playback speed, or pause to scrub and step by 50 ms. Use integer zoom to inspect pixels. Turn on layers, pivots, or hitboxes to check overlap, transforms, and touch regions. **Run route** exercises walk, run, and jump; **Throw** exercises ball play.

Use **Load rig** for the JSON manifest and **Load atlas** for its PNG or WebP sprites. Atlas dimensions must match the manifest. **Manifest** shows validation issues and the source JSON. Production builds omit the laboratory and geometric catalogue.
