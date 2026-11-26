# Companion packs

Companion Focus imports ZIP archives and JSON envelopes. Both formats use the same manifest and verify the same declared assets.

A ZIP contains `manifest.json`, a PNG preview, a `LICENSE` file and PNG sprite assets. Short PCM WAV sounds can be included under `sounds/`. Keep `manifest.json` at the archive root. A JSON envelope has `schema: "companion.bundle/1"`, a `manifest` object and an `assets` object that maps each asset path to its padded Base64 bytes. Packs contain no scripts or runtime extensions.

The [`companion.pack/1` manifest](companion/manifest.schema.json) names the pack, version, author, license, preview, canvas, palette, layers, clips and assets. Use a lowercase dotted pack ID and `MAJOR.MINOR.PATCH` versions. Set `application.minVersion` if the pack requires a particular app version. `description`, `attribution` and `homepage` are available for publication details.

Give each layer a distinct draw order (`z`). A clip defines a frame rate, whether it loops, and ordered frame references. Frame rectangles are in source atlas pixels. A clip named `idle`, when present, plays by default. `focus`, `break`, `pet` and `catch` are optional contextual clips.

Layers can declare a `parent`, `offset`, `pivot`, `rotationDegrees`, `scale`, `opacity` and `visible` rest state. A clip can declare `durationMs`, transform `tracks`, timed `events` and a `state` policy for priority, interruption and transition. Keyframes use milliseconds, absolute property values and `linear` or `step` easing.

The optional `sounds` list maps event names to declared WAV assets and a volume between 0 and 1. Android can play sounds for `pet`, `ball_thrown`, `catch`, `ball_returned`, `ball_missed` and timed markers in contextual clips when Sound is enabled. Use 16-bit PCM, one or two channels, 8 to 48 kHz, and at most three seconds per sound. Web previews do not play pack sounds.

Each asset has a relative path, byte length and lowercase SHA-256 digest. Frame regions must fit their images, and the preview must be declared as an asset. The validator rejects unsupported schemas, corrupt archives, unsafe paths and unexpected files before changing the library.

See the [pack creation guide](PACK_CREATION_GUIDE.md) for an editable manifest and validation command.
