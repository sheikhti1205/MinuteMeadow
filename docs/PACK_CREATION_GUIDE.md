# Create a companion pack

1. Copy [`manifest.template.json`](companion/manifest.template.json) to `manifest.json`. Give the pack a unique ID and fill in the creator, license and attribution.
2. Add the PNG preview and sprite atlas. Use transparent PNGs, the same pixel grid for all frames, and source rectangles that fit inside the atlas.
3. Put each file's byte length and lowercase SHA-256 digest in `assets`. Replace the template's placeholder digests.
4. Put the license text at the archive root as `LICENSE`. Zip the files with `manifest.json` at the root, without a surrounding folder.
5. Validate the pack with `dart run tool/validate_pack.dart <file.zip>`. Import it in the Companion library and check the preview before submitting.

The [manifest schema](companion/manifest.schema.json) covers fields and shapes. The validator also checks cross-references, integrity and image bounds.

## Review

- The same pack ID is used for updates, with an increased version.
- The pack declares exactly the files it needs.
- The preview shows the actual pack.
- The pack passes validation and opens offline once installed.
- Every asset has redistribution permission and required attribution. See [asset licensing](ASSET_LICENSING.md).
