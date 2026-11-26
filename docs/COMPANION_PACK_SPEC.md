# Companion packs

The pack format is under development. Until a schema and validator ship together, there is no supported import format.

A pack contains `manifest.json`, a PNG preview, a `LICENSE` file, sprite images and animation data. Sound assets are optional. Packs contain no scripts, binaries or runtime extensions.

The manifest identifies the pack, its release version, author, attribution, license, supported application and schema versions, canvas size, palette, layers, clips and referenced files. Every referenced asset has a content hash. Relative asset paths must point inside the pack, and declared frame regions must fit their source images.

The importer will reject unsupported schemas, missing or invalid references, corrupt or excessive assets, malformed archives and unsafe paths before an installed version changes. See [marketplace architecture](MARKETPLACE_ARCHITECTURE.md) for the install boundary.
