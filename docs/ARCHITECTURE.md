# Architecture

Companion Focus targets Android phones. A web build supports browser checks of shared screens. Android-specific behavior such as notifications and device restart recovery requires separate verification.

Feature code lives under `lib/features/`. Application startup and navigation belong in `lib/app/`, shared visual tokens in `lib/design/`, and platform adapters in `lib/core/`.

The focus and clock engines calculate elapsed time independently of the UI. The UI reads timer snapshots and sends user actions. Session history reads stored outcomes; animation may respond to session events but cannot advance or complete a timer.

Companion packs contain declarative metadata and assets. The catalogue describes available packs; the local library owns installed versions. The renderer reads validated local assets. The app must still open and run its timers when the catalogue and library are empty.

See the [roadmap](../ROADMAP.md) for implementation status.
