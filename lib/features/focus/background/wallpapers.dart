/// Wallpaper presentation for Focus.
///
/// Focus host integration:
/// - Put a [FocusWallpaperBackdrop] under the Focus page content and remove the
///   page's opaque background so the wallpaper is visible.
/// - Pass `AppearancePreferences.wallpaper` for built-in live wallpapers.
/// - For a saved photo, validate the stored bytes once with
///   [FocusWallpaperCandidate.validate], then pass the candidate and the saved
///   focal `Alignment` as `photo` and `focal`.
/// - Set `active` for the current focus phase and `location` for the saved
///   setup/active/both choice. Set `visible` false while the surface is
///   offscreen; reduced motion and low power already stop the ticker.
///
/// [FocusWallpaperPainter] draws the procedural live effects;
/// [FocusWallpaperCandidate] validates selected photo bytes.
library;

export 'focus_wallpaper.dart';
export 'focus_wallpaper_codec.dart';
export 'focus_wallpaper_painter.dart';
