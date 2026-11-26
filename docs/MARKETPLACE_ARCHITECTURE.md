# Marketplace architecture

The marketplace starts with a bundled curated catalogue. Builds compiled with `COMPANION_FOCUS_DEVELOPMENT_TOOLS` enabled expose a separate geometric catalogue in Settings under Development packs. An empty production catalogue is valid; browsing and the library remain available.

The catalogue lists pack releases and availability. The library tracks what is installed on this device. An installed pack remains usable offline when catalogue loading fails. The app can compare a catalogue version with its installed counterpart to offer an update.

Downloads and local imports enter the same install path. Stage the candidate in app-owned storage, validate the manifest and all assets, verify integrity, then switch the library to the new version. Keep the previous version available until the switch completes; clean up incomplete candidates separately.

A future remote registry can use the catalogue interface without changing the library or installer. The initial marketplace requires neither accounts nor payments.
