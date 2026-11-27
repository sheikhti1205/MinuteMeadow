# Third-party notices

This product includes adapted third-party code. The full license text is kept
with the source in `third_party/sessions/` and is also registered in the app's
license page, so distributed builds carry it.

## Sessions card effects

- Upstream project: [Sessions](https://github.com/MohammadAliUstad/Sessions)
- Revision: tag `v6.0.0`, commit `8e0b7c211dbc31014e46ae231e0ae2d7f55bed1f`
- Copyright 2026 YugenTech
- License: Apache License, Version 2.0
  (`third_party/sessions/LICENSE-APACHE-2.0`)

Files adapted from that revision:

- `app/src/main/java/com/yugentech/sessions/ui/dash/homeScreen/components/hero/HeroCardBackground.kt`
  (blob `574817a86273adf8e586624dce8f19f691ccb418`)
- `app/src/main/java/com/yugentech/sessions/ui/config/appearanceScreen/components/CardAnimationSelector.kt`
  (blob `e331cd9cea30f90aa307580e3e6ff39cf87f1379`)

Adapted files in this product:

- `lib/features/focus/cards/card_effect_painter.dart`
- `lib/features/focus/cards/card_surface.dart`
- `lib/features/settings/home_cards_page.dart`

Changes made:

- The Kotlin/Compose draw routines were translated to Dart and ported to a
  Flutter `CustomPainter`.
- The upstream themed and warm palettes were replaced with this product's
  monochrome surface roles; no upstream palette, artwork, font or branding is
  included.
- Effect names were shortened: Sand to Dunes, Candle to Embers, None to Off.
- The effect clock was reimplemented on a Flutter `Ticker`, and still frames
  were added for reduced motion and low power.
- The effect selector was reimplemented as draft appearance settings with a
  shared preview and independent layout, style and animation choices.
