# Companion packs

Companion Focus imports ZIP archives and JSON envelopes. Both formats use the same manifest and verify the same declared assets.

A ZIP contains `manifest.json`, a PNG preview, a `LICENSE` file and PNG sprite assets. Keep `manifest.json` at the archive root. A JSON envelope has `schema: "companion.bundle/1"`, a `manifest` object and an `assets` object that maps each asset path to its padded Base64 bytes. Packs contain no scripts or runtime extensions. Version 1 pack assets are PNGs.

The [`companion.pack/1` manifest](companion/manifest.schema.json) names the pack, version, author, license, preview, canvas, palette, layers, clips and assets. Use a lowercase dotted pack ID and `MAJOR.MINOR.PATCH` versions. Set `application.minVersion` if the pack requires a particular app version. `description`, `attribution` and `homepage` are available for publication details.

Give each layer a distinct draw order (`z`). A clip defines a frame rate, whether it loops, and ordered frame references. Frame rectangles are in source atlas pixels. A clip named `idle`, when present, plays by default. `focus`, `break`, `pet` and `catch` are optional contextual clips.

Each asset has a relative path, byte length and lowercase SHA-256 digest. Frame regions must fit their images, and the preview must be declared as an asset. The validator rejects unsupported schemas, corrupt archives, unsafe paths and unexpected files before changing the library.

See the [pack creation guide](PACK_CREATION_GUIDE.md) for an editable manifest and validation command.
