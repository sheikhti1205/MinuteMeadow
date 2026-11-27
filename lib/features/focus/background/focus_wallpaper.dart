import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../design/appearance_preferences.dart';
import 'focus_wallpaper_codec.dart';
import 'focus_wallpaper_painter.dart';

/// Where a saved wallpaper is shown.
enum WallpaperLocation { setup, active, both }

extension WallpaperLocationInfo on WallpaperLocation {
  String get label => switch (this) {
    WallpaperLocation.setup => 'Setup',
    WallpaperLocation.active => 'Active focus',
    WallpaperLocation.both => 'Both',
  };

  String get description => switch (this) {
    WallpaperLocation.setup => 'The timer setup screen only',
    WallpaperLocation.active => 'A running, paused or break phase only',
    WallpaperLocation.both => 'Setup and active focus',
  };

  bool appliesTo({required bool active}) => switch (this) {
    WallpaperLocation.setup => !active,
    WallpaperLocation.active => active,
    WallpaperLocation.both => true,
  };
}

/// A saved wallpaper source.
///
/// Built-in live wallpapers keep using [WallpaperType] from the appearance
/// preferences. A photo is a separate source because its bytes are large and
/// live outside the settings JSON; [appearanceType] is then `none`, so the two
/// sources can never be persisted as active at the same time.
sealed class WallpaperSelection {
  const WallpaperSelection();

  /// The built-in choice saved in [AppearancePreferences.wallpaper]. A photo
  /// loaded from the device replaces this once it has been validated.
  static WallpaperSelection fromAppearance(WallpaperType type) {
    return type == WallpaperType.none
        ? const NoWallpaperSelection()
        : LiveWallpaperSelection(type);
  }

  WallpaperType get appearanceType => switch (this) {
    LiveWallpaperSelection(:final type) => type,
    NoWallpaperSelection() || PhotoWallpaperSelection() => WallpaperType.none,
  };

  FocusWallpaperCandidate? get photo => switch (this) {
    PhotoWallpaperSelection(:final candidate) => candidate,
    NoWallpaperSelection() || LiveWallpaperSelection() => null,
  };

  Alignment get focal => switch (this) {
    PhotoWallpaperSelection(:final focal) => focal,
    NoWallpaperSelection() || LiveWallpaperSelection() => Alignment.center,
  };

  bool get isPhoto => this is PhotoWallpaperSelection;
}

final class NoWallpaperSelection extends WallpaperSelection {
  const NoWallpaperSelection();

  @override
  bool operator ==(Object other) => other is NoWallpaperSelection;

  @override
  int get hashCode => 0;
}

final class LiveWallpaperSelection extends WallpaperSelection {
  const LiveWallpaperSelection(this.type)
    : assert(type != WallpaperType.none, 'Use NoWallpaperSelection for none.');

  final WallpaperType type;

  @override
  bool operator ==(Object other) =>
      other is LiveWallpaperSelection && other.type == type;

  @override
  int get hashCode => type.hashCode;
}

final class PhotoWallpaperSelection extends WallpaperSelection {
  const PhotoWallpaperSelection(this.candidate, {this.focal = Alignment.center});

  final FocusWallpaperCandidate candidate;
  final Alignment focal;

  @override
  bool operator ==(Object other) =>
      other is PhotoWallpaperSelection &&
      identical(other.candidate, candidate) &&
      other.focal == focal;

  @override
  int get hashCode => Object.hash(identityHashCode(candidate), focal);
}

/// The editor result. Nothing is saved until the host's Apply callback
/// completes.
@immutable
class WallpaperDraft {
  const WallpaperDraft({required this.selection, required this.location});

  final WallpaperSelection selection;
  final WallpaperLocation location;

  /// What belongs in `AppearancePreferences.wallpaper`. A photo or None maps
  /// to `WallpaperType.none`; the host stores the photo through its own
  /// wallpaper store.
  WallpaperType get appearanceType => selection.appearanceType;

  FocusWallpaperCandidate? get photo => selection.photo;

  /// The read-once bytes for a selected photo. Persist them once after Apply
  /// and do not retain this reference longer than needed.
  Uint8List? get photoBytes => selection.photo?.bytes;

  Alignment get focal => selection.focal;

  bool get usesPhoto => selection.isPhoto;
}

/// The two monochrome tones a wallpaper is drawn in, resolved from the theme.
@immutable
class FocusWallpaperPalette {
  const FocusWallpaperPalette({
    required this.base,
    required this.ink,
    required this.shade,
    required this.brightness,
  });

  factory FocusWallpaperPalette.of(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool dark = theme.brightness == Brightness.dark;
    return FocusWallpaperPalette(
      base: scheme.surface,
      ink: dark ? Colors.white : scheme.onSurface,
      shade: dark ? scheme.surfaceContainerHighest : scheme.outline,
      brightness: theme.brightness,
    );
  }

  final Color base;
  final Color ink;
  final Color shade;
  final Brightness brightness;
}

/// Draws the saved wallpaper behind Focus content.
///
/// A photo takes precedence over [liveType]. When the wallpaper should not be
/// shown for the current [location] or [visible] is false, the widget paints
/// nothing and stops its ticker. Motion is also suppressed under reduced motion,
/// low-power mode, an inactive route and a paused app, leaving a still frame.
///
/// The widget owns its decoded image and disposes it. A failed decode keeps the
/// previous image on screen and reports the message through [onPhotoError], so
/// a corrupt or unsupported file never replaces a working wallpaper.
class FocusWallpaperBackdrop extends StatefulWidget {
  const FocusWallpaperBackdrop({
    required this.liveType,
    this.photo,
    this.focal = Alignment.center,
    this.location = WallpaperLocation.both,
    this.active = false,
    this.reducedMotion = false,
    this.lowPower = false,
    this.visible = true,
    this.overlay = true,
    this.photoDecodeExtent = 2048,
    this.onPhotoError,
    this.onPhotoReady,
    super.key,
  });

  /// The saved built-in wallpaper. `none` draws nothing unless [photo] is set.
  final WallpaperType liveType;

  /// The validated photo selected by the user, if any.
  final FocusWallpaperCandidate? photo;

  /// Which part of a cover-cropped photo stays in view.
  final Alignment focal;

  final WallpaperLocation location;

  /// Whether the Focus session is active. Used only for [location].
  final bool active;

  /// The saved product preference. Platform reduce-motion also applies.
  final bool reducedMotion;

  /// The saved low-power preference. Stops the ticker.
  final bool lowPower;

  /// False while the surface is offscreen. Stops the ticker.
  final bool visible;

  /// Draws the legibility scrim that keeps timer text readable.
  final bool overlay;

  /// Long edge used for the bounded decode. Clamped by the codec.
  final int photoDecodeExtent;

  /// Reports a photo decode failure without replacing the previous image.
  final ValueChanged<String>? onPhotoError;

  /// Reports the candidate that decoded successfully, so the editor can drop
  /// its rollback state.
  final ValueChanged<FocusWallpaperCandidate>? onPhotoReady;

  @override
  State<FocusWallpaperBackdrop> createState() =>
      _FocusWallpaperBackdropState();
}

class _FocusWallpaperBackdropState extends State<FocusWallpaperBackdrop>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  Ticker? _ticker;
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  Duration _last = Duration.zero;
  bool _ticking = false;
  bool _tickerEnabled = true;
  bool _mediaReducedMotion = false;
  bool _appActive = true;

  ui.Image? _photoImage;
  FocusWallpaperCandidate? _loadedCandidate;
  FocusWallpaperCandidate? _pendingCandidate;
  int? _loadedExtent;
  int _decodeToken = 0;

  bool get _still =>
      widget.lowPower || widget.reducedMotion || _mediaReducedMotion;

  bool get _shows =>
      widget.visible &&
      widget.location.appliesTo(active: widget.active) &&
      (widget.photo != null || widget.liveType != WallpaperType.none);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPhoto();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mediaReducedMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _tickerEnabled = TickerMode.of(context);
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant FocusWallpaperBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.photo, widget.photo) ||
        oldWidget.photoDecodeExtent != widget.photoDecodeExtent) {
      _loadPhoto();
    }
    _syncTicker();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _syncTicker();
  }

  @override
  void dispose() {
    _decodeToken++;
    _ticker?.stop();
    _time.dispose();
    _photoImage?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _syncTicker() {
    final bool run =
        _shows &&
        widget.photo == null &&
        !_still &&
        _tickerEnabled &&
        _appActive;
    if (run && !_ticking) {
      final Ticker ticker = _ticker ??= createTicker(_onTick);
      _last = Duration.zero;
      ticker.start();
      _ticking = true;
    } else if (!run && _ticking) {
      _ticker?.stop();
      _ticking = false;
    }
  }

  void _onTick(Duration elapsed) {
    final Duration delta = elapsed - _last;
    if (delta <= Duration.zero) return;
    _last = elapsed;
    _time.value += delta.inMicroseconds / Duration.microsecondsPerSecond;
  }

  void _loadPhoto() {
    final FocusWallpaperCandidate? candidate = widget.photo;
    if (candidate == null) {
      _decodeToken++;
      _pendingCandidate = null;
      _loadedCandidate = null;
      _loadedExtent = null;
      _photoImage?.dispose();
      _photoImage = null;
      return;
    }
    if (identical(candidate, _pendingCandidate)) return;
    if (identical(candidate, _loadedCandidate) &&
        _loadedExtent == widget.photoDecodeExtent) {
      return;
    }
    _decodeToken++;
    _pendingCandidate = candidate;
    unawaited(_decodePhoto(candidate, _decodeToken));
  }

  Future<void> _decodePhoto(
    FocusWallpaperCandidate candidate,
    int token,
  ) async {
    try {
      final ui.Image image = await candidate.decode(
        maxExtent: widget.photoDecodeExtent,
      );
      if (!mounted || token != _decodeToken) {
        image.dispose();
        return;
      }
      setState(() {
        _photoImage?.dispose();
        _photoImage = image;
        _loadedCandidate = candidate;
        _loadedExtent = widget.photoDecodeExtent;
        _pendingCandidate = null;
      });
      widget.onPhotoReady?.call(candidate);
    } on FocusWallpaperCodecException catch (error) {
      _photoFailed(error.message, token);
    } catch (_) {
      _photoFailed('This photo could not be shown. Try choosing it again.', token);
    }
  }

  void _photoFailed(String message, int token) {
    if (!mounted || token != _decodeToken) return;
    setState(() => _pendingCandidate = null);
    widget.onPhotoError?.call(message);
  }

  @override
  Widget build(BuildContext context) {
    if (!_shows) return const SizedBox.shrink();
    final palette = FocusWallpaperPalette.of(context);
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(color: palette.base),
            if (widget.photo != null)
              _photoLayer()
            else
              _liveLayer(palette),
            if (widget.overlay) _overlayLayer(palette),
          ],
        ),
      ),
    );
  }

  Widget _photoLayer() {
    final ui.Image? image = _photoImage;
    if (image == null) return const SizedBox.expand();
    return RawImage(
      image: image,
      fit: BoxFit.cover,
      alignment: widget.focal,
      filterQuality: FilterQuality.medium,
    );
  }

  Widget _liveLayer(FocusWallpaperPalette palette) {
    return RepaintBoundary(
      child: ValueListenableBuilder<double>(
        valueListenable: _time,
        builder: (BuildContext context, double time, Widget? child) =>
            CustomPaint(
              painter: FocusWallpaperPainter(
                type: widget.liveType,
                time: time,
                base: palette.base,
                ink: palette.ink,
                shade: palette.shade,
                active: !_still,
              ),
              isComplex: true,
              willChange: !_still,
              child: child,
            ),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _overlayLayer(FocusWallpaperPalette palette) {
    final bool dark = palette.brightness == Brightness.dark;
    final Color veil = dark ? Colors.black : Colors.white;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ColoredBox(color: veil.withValues(alpha: dark ? 0.30 : 0.26)),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                veil.withValues(alpha: 0.12),
                veil.withValues(alpha: 0.02),
                veil.withValues(alpha: 0.20),
                veil.withValues(alpha: 0.52),
              ],
              stops: const <double>[0, 0.32, 0.68, 1],
            ),
          ),
        ),
      ],
    );
  }
}
