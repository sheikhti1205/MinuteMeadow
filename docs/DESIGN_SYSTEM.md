# Design system

The app uses neutral grayscale app chrome in light and dark themes. Light mode is white and near-white with near-black text and primary actions. Dark mode inverts the same roles: near-black surfaces, off-white text and light solid primary actions. Supporting controls use pale gray fills, and the bottom navigation stays quiet with a light gray bar, a soft neutral selection pill and neutral icons.

Within app chrome, only the error role carries hue. It stays a readable red in both themes because destructive and failed states need to remain distinguishable without relying on position alone.

`CompanionTheme` in `lib/design/companion_theme.dart` defines the shared light and dark schemes. Its roles are the source of truth for app chrome. Companion artwork and pack swatches keep their own data-defined colors.

## Contrast

The main text and control pairs meet WCAG 2.2 AA in both themes:

| Pair | Light | Dark | Requirement |
| --- | --- | --- | --- |
| Body text (`onSurface` on `surface`) | 18.1:1 | 16.9:1 | 4.5:1 |
| Secondary text (`onSurfaceVariant` on `surface`) | 6.4:1 | 8.7:1 | 4.5:1 |
| Primary action label (`onPrimary` on `primary`) | 17.4:1 | 16.9:1 | 4.5:1 |
| Selected control label (`onSecondaryContainer` on `secondaryContainer`) | 14.7:1 | 12.5:1 | 4.5:1 |
| Outline on surface (`outline` on `surface`) | 5.1:1 | 7.9:1 | 3:1 |
| Navigation pill outline (`outline` on `surfaceContainer`) | 4.9:1 | 6.9:1 | 3:1 |
| Error text (`error` on `surface`) | 6.3:1 | 11.1:1 | 4.5:1 |

`outlineVariant` draws decorative hairline borders and separators. State-bearing indicators in the shared theme use the higher-contrast `outline` token; progress marks that repeat a text value remain understandable when a hairline is faint.

## Controls and targets

Interactive controls keep a minimum 48 by 48 logical pixel target. The theme uses standard visual density and padded tap targets, and sets 48 pixel minimums for filled, text and icon buttons. Chips, list rows and navigation destinations keep at least that target through their standard Material sizing.

Primary actions are solid, high-contrast capsules: near-black in light mode and off-white in dark mode. Navigation selection uses a soft gray pill with a contrasting outline and a darker icon and label, so state does not rely on fill alone.

Use the platform typeface for labels and paragraphs. Timer figures use tabular widths so the display does not shift as digits change. Keep the timer and its current action together and give completion or pause a text label.

The 16 logical pixel page inset gives the main content a consistent edge. Sprite pixels use a separate scale, chosen at render time from the asset size and available physical pixels.

Keep pixel edges on companion artwork. Shared primary actions use a capsule shape, while supporting surfaces stay flat and quiet. Preserve visible focus, readable text scaling and accessible touch targets. Leave companion space empty when no pack is installed.
