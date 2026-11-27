import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/appearance_preferences.dart';
import '../focus/background/focus_wallpaper.dart';
import '../focus/background/focus_wallpaper_codec.dart';
import '../focus/background/focus_wallpaper_painter.dart';

/// Editor for the Focus wallpaper.
///
/// The page is a draft editor: None, a built-in live wallpaper or a selected
/// photo, plus where the wallpaper appears and how a photo is cropped. Nothing
/// is stored until Apply completes. Cancel leaves the saved wallpaper
/// untouched and Reset restores the product defaults in this draft only.
///
/// The page has no storage dependency. [onApply] receives a [WallpaperDraft]
/// whose [WallpaperDraft.photoBytes] can be persisted once by the host. The
/// optional [photoPicker] lets a host supply already-selected bytes; when it is
/// null the built-in bounded `file_selector` picker is used.
class WallpaperPage extends StatefulWidget {
  const WallpaperPage({
    required this.selection,
    this.location = WallpaperLocation.both,
    required this.onApply,
    this.photoPicker,
    this.reducedMotion = false,
    this.lowPower = false,
    super.key,
  });

  /// The saved wallpaper source when the editor was opened.
  final WallpaperSelection selection;

  /// The saved location when the editor was opened.
  final WallpaperLocation location;

  /// Called with the draft when the user applies it.
  ///
  /// It must complete only after the value has been stored. Throwing keeps the
  /// editor open and shows its error, so the page never reports a save that
  /// did not happen.
  final Future<void> Function(WallpaperDraft draft) onApply;

  /// Optional bounded picker supplied by the host.
  ///
  /// It should read the selected file once and return a candidate from
  /// [FocusWallpaperCandidate.validate]. Returning null means cancelled.
  final FocusWallpaperPhotoPicker? photoPicker;

  /// Keeps the preview still, matching the saved reduce-motion preference.
  final bool reducedMotion;

  /// Keeps the preview still, matching the saved low-power preference.
  final bool lowPower;

  static const Key previewKey = Key('wallpaper-preview');
  static const Key noneKey = Key('wallpaper-none');
  static const Key photoKey = Key('wallpaper-photo');
  static const Key resetKey = Key('wallpaper-reset');
  static const Key cancelKey = Key('wallpaper-cancel');
  static const Key applyKey = Key('wallpaper-apply');

  static Key liveKey(WallpaperType type) =>
      ValueKey<String>('wallpaper-live-${type.name}');

  static Key locationKey(WallpaperLocation location) =>
      ValueKey<String>('wallpaper-show-${location.name}');

  static Key focalKey(Alignment alignment) =>
      ValueKey<String>('wallpaper-crop-${alignment.x}-${alignment.y}');

  @override
  State<WallpaperPage> createState() => _WallpaperPageState();
}

class _WallpaperPageState extends State<WallpaperPage> {
  late final WallpaperSelection _initialSelection;
  late final WallpaperLocation _initialLocation;
  late WallpaperSelection _selection;
  late WallpaperLocation _location;
  FocusWallpaperCandidate? _lastPhoto;
  Alignment _lastFocal = Alignment.center;
  WallpaperSelection? _previousSelection;
  FocusWallpaperCandidate? _awaitingPhoto;
  bool _picking = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialSelection = widget.selection;
    _initialLocation = widget.location;
    _selection = widget.selection;
    _location = widget.location;
    _lastPhoto = widget.selection.photo;
    _lastFocal = widget.selection.focal;
  }

  bool get _dirty =>
      _selection != _initialSelection || _location != _initialLocation;

  bool get _photoSelected => _selection.isPhoto;

  void _selectNone() {
    if (_saving) return;
    setState(() {
      _selection = const NoWallpaperSelection();
      _error = null;
      _previousSelection = null;
      _awaitingPhoto = null;
    });
  }

  void _selectLive(WallpaperType type) {
    if (_saving || type == WallpaperType.none) return;
    setState(() {
      _selection = LiveWallpaperSelection(type);
      _error = null;
      _previousSelection = null;
      _awaitingPhoto = null;
    });
  }

  void _selectPhoto() {
    if (_saving || _picking) return;
    if (_selection.isPhoto) {
      unawaited(_choosePhoto());
      return;
    }
    final photo = _lastPhoto;
    if (photo == null) {
      unawaited(_choosePhoto());
      return;
    }
    setState(() {
      _selection = PhotoWallpaperSelection(photo, focal: _lastFocal);
      _error = null;
      _previousSelection = null;
      _awaitingPhoto = null;
    });
  }

  Future<void> _choosePhoto() async {
    if (_picking || _saving) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final picker = widget.photoPicker ?? pickFocusWallpaperFile;
      final candidate = await picker();
      if (!mounted || candidate == null) return;
      setState(() {
        _previousSelection = _selection;
        _awaitingPhoto = candidate;
        _lastPhoto = candidate;
        _lastFocal = Alignment.center;
        _selection = PhotoWallpaperSelection(candidate);
      });
    } on FocusWallpaperCodecException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error =
            'Could not read that photo. Choose a still JPEG, PNG or WebP '
            'image.',
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _handlePhotoError(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      final awaiting = _awaitingPhoto;
      if (awaiting != null && identical(_selection.photo, awaiting)) {
        _selection = _previousSelection ?? const NoWallpaperSelection();
        if (identical(_lastPhoto, awaiting)) {
          _lastPhoto = _selection.photo;
          _lastFocal = _selection.focal;
        }
        _previousSelection = null;
        _awaitingPhoto = null;
      }
    });
  }

  void _handlePhotoReady(FocusWallpaperCandidate candidate) {
    if (!identical(_selection.photo, candidate)) return;
    _previousSelection = null;
    _awaitingPhoto = null;
  }

  void _selectLocation(WallpaperLocation location) {
    if (_saving || _location == location) return;
    setState(() {
      _location = location;
      _error = null;
    });
  }

  void _selectFocal(Alignment focal) {
    final current = _selection;
    if (_saving || current is! PhotoWallpaperSelection) return;
    if (current.focal == focal) return;
    setState(() {
      _lastFocal = focal;
      _selection = PhotoWallpaperSelection(current.candidate, focal: focal);
      _error = null;
    });
  }

  void _reset() {
    if (_saving) return;
    setState(() {
      _selection = const NoWallpaperSelection();
      _location = WallpaperLocation.both;
      _error = null;
      _previousSelection = null;
      _awaitingPhoto = null;
    });
  }

  Future<void> _apply() async {
    if (_saving || _picking || !_dirty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onApply(
        WallpaperDraft(selection: _selection, location: _location),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save Wallpaper. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Wallpaper')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (_saving || _picking)
                          _BusyNotice(
                            label: _picking
                                ? 'Reading photo…'
                                : 'Saving Wallpaper…',
                          ),
                        if (_error != null) _ErrorNotice(message: _error!),
                        _preview(theme, scheme),
                        const _SectionHeader(
                          'Wallpaper',
                          Icons.wallpaper_outlined,
                        ),
                        _sourceRow(scheme),
                        if (_lastPhoto != null) _photoStatus(scheme),
                        const _SectionHeader(
                          'Live wallpapers',
                          Icons.auto_awesome_outlined,
                        ),
                        _liveGrid(scheme),
                        if (_photoSelected) ...<Widget>[
                          const _SectionHeader(
                            'Crop focus',
                            Icons.crop_free_outlined,
                          ),
                          Text(
                            'Choose the part of the photo that stays visible '
                            'when it fills the screen.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _cropGrid(scheme),
                        ],
                        const _SectionHeader(
                          'Show on',
                          Icons.visibility_outlined,
                        ),
                        _locationRow(scheme),
                        const SizedBox(height: 10),
                        Text(
                          'Still JPEG, PNG or WebP photos up to '
                          '${FocusWallpaperLimits.encodedSizeLabel} are decoded '
                          'on this device. Animated photos are not supported. '
                          'A soft overlay keeps timer text readable.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Nothing changes until you tap Apply. Reset restores '
                          'the product defaults in this draft only.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _footer(scheme),
          ],
        ),
      ),
    );
  }

  Widget _preview(ThemeData theme, ColorScheme scheme) {
    final selection = _selection;
    final reduceMotion =
        widget.reducedMotion ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    return Semantics(
      key: WallpaperPage.previewKey,
      container: true,
      label: 'Wallpaper preview: ${_describe(selection)}',
      excludeSemantics: true,
      child: Container(
        height: 190,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(color: scheme.surface),
            FocusWallpaperBackdrop(
              liveType: selection.appearanceType,
              photo: selection.photo,
              focal: selection.focal,
              location: WallpaperLocation.both,
              active: true,
              reducedMotion: reduceMotion,
              lowPower: widget.lowPower,
              overlay: true,
              photoDecodeExtent: 1280,
              onPhotoError: _handlePhotoError,
              onPhotoReady: _handlePhotoReady,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: scheme.onSurface,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Focusing',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '25 min',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    '25:00',
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1,
                      letterSpacing: -0.5,
                      color: scheme.onSurface,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'A running, paused or break phase, drawn over your '
                    'wallpaper.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceRow(ColorScheme scheme) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _sourceTile(
            key: WallpaperPage.noneKey,
            scheme: scheme,
            label: 'None',
            icon: Icons.block_outlined,
            selected: _selection is NoWallpaperSelection,
            onTap: _selectNone,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _sourceTile(
            key: WallpaperPage.photoKey,
            scheme: scheme,
            label: 'Choose photo',
            icon: Icons.add_photo_alternate_outlined,
            selected: _photoSelected,
            busy: _picking,
            onTap: _selectPhoto,
          ),
        ),
      ],
    );
  }

  Widget _sourceTile({
    required Key key,
    required ColorScheme scheme,
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    bool busy = false,
  }) {
    final enabled = !_saving && !busy;
    return Material(
      key: key,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        container: true,
        button: true,
        selected: selected,
        enabled: enabled,
        label: 'Wallpaper: $label',
        excludeSemantics: true,
        onTap: enabled ? onTap : null,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: <Widget>[
                  Icon(
                    selected ? Icons.check_circle_outline : icon,
                    size: 20,
                    color: selected
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (busy)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _photoStatus(ColorScheme scheme) {
    final photo = _lastPhoto!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.image_outlined,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  photo.name ?? 'Selected photo',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
                Text(
                  '${photo.format.label} · ${photo.sizeLabel}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _saving || _picking
                ? null
                : () => unawaited(_choosePhoto()),
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 44),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  Widget _liveGrid(ColorScheme scheme) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final columns = constraints.maxWidth >= 420 ? 3 : 2;
        final width =
            (constraints.maxWidth - 10 * (columns - 1)) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            for (final WallpaperType type in WallpaperType.values)
              if (type != WallpaperType.none)
                SizedBox(
                  width: width,
                  child: _liveTile(type, scheme, dark),
                ),
          ],
        );
      },
    );
  }

  Widget _liveTile(WallpaperType type, ColorScheme scheme, bool dark) {
    final selected =
        _selection is LiveWallpaperSelection &&
        (_selection as LiveWallpaperSelection).type == type;
    return Material(
      key: WallpaperPage.liveKey(type),
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        container: true,
        button: true,
        selected: selected,
        enabled: !_saving,
        label: 'Live wallpaper: ${type.label}',
        excludeSemantics: true,
        onTap: _saving ? null : () => _selectLive(type),
        child: InkWell(
          onTap: _saving ? null : () => _selectLive(type),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  height: 64,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CustomPaint(
                      painter: FocusWallpaperPainter(
                        type: type,
                        time: 9,
                        base: scheme.surfaceContainerHighest,
                        ink: dark ? Colors.white : scheme.onSurface,
                        shade: dark
                            ? scheme.surfaceContainerHigh
                            : scheme.outline,
                        active: true,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        type.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (selected)
                      Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: scheme.primary,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _locationRow(ColorScheme scheme) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final WallpaperLocation location
                in WallpaperLocation.values)
              ChoiceChip(
                key: WallpaperPage.locationKey(location),
                label: Text(location.label),
                selected: _location == location,
                onSelected: _saving
                    ? null
                    : (selected) {
                        if (selected) _selectLocation(location);
                      },
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _location.description,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _cropGrid(ColorScheme scheme) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final width = (constraints.maxWidth - 16) / 3;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final Alignment alignment in _focalPoints)
              SizedBox(
                width: width,
                child: _focalTile(alignment, scheme),
              ),
          ],
        );
      },
    );
  }

  Widget _focalTile(Alignment alignment, ColorScheme scheme) {
    final selected = _selection.focal == alignment;
    return Material(
      key: WallpaperPage.focalKey(alignment),
      color: selected ? scheme.primary : scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? Colors.transparent : scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        container: true,
        button: true,
        selected: selected,
        enabled: !_saving,
        label: 'Crop focus: ${_focalLabel(alignment)}',
        excludeSemantics: true,
        onTap: _saving ? null : () => _selectFocal(alignment),
        child: InkWell(
          onTap: _saving ? null : () => _selectFocal(alignment),
          child: SizedBox(
            height: 44,
            child: Center(
              child: Icon(
                _focalIcon(alignment),
                size: 18,
                color: selected
                    ? scheme.onPrimary
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer(ColorScheme scheme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              TextButton.icon(
                key: WallpaperPage.resetKey,
                onPressed: _saving ? null : _reset,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('Reset'),
              ),
              TextButton(
                key: WallpaperPage.cancelKey,
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: WallpaperPage.applyKey,
                onPressed: _saving || _picking || !_dirty ? null : _apply,
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _describe(WallpaperSelection selection) {
    if (selection is PhotoWallpaperSelection) {
      final name = selection.candidate.name;
      final label = name == null || name.isEmpty ? 'Photo' : name;
      return '$label, ${_focalLabel(selection.focal).toLowerCase()} crop';
    }
    if (selection is LiveWallpaperSelection) {
      return 'Live, ${selection.type.label}';
    }
    return 'None';
  }
}

const List<Alignment> _focalPoints = <Alignment>[
  Alignment.topLeft,
  Alignment.topCenter,
  Alignment.topRight,
  Alignment.centerLeft,
  Alignment.center,
  Alignment.centerRight,
  Alignment.bottomLeft,
  Alignment.bottomCenter,
  Alignment.bottomRight,
];

String _focalLabel(Alignment alignment) {
  if (alignment == Alignment.topLeft) return 'Top left';
  if (alignment == Alignment.topCenter) return 'Top';
  if (alignment == Alignment.topRight) return 'Top right';
  if (alignment == Alignment.centerLeft) return 'Left';
  if (alignment == Alignment.center) return 'Centre';
  if (alignment == Alignment.centerRight) return 'Right';
  if (alignment == Alignment.bottomLeft) return 'Bottom left';
  if (alignment == Alignment.bottomCenter) return 'Bottom';
  return 'Bottom right';
}

IconData _focalIcon(Alignment alignment) {
  if (alignment == Alignment.topLeft) return Icons.north_west_rounded;
  if (alignment == Alignment.topCenter) return Icons.north_rounded;
  if (alignment == Alignment.topRight) return Icons.north_east_rounded;
  if (alignment == Alignment.centerLeft) return Icons.west_rounded;
  if (alignment == Alignment.center) return Icons.center_focus_strong;
  if (alignment == Alignment.centerRight) return Icons.east_rounded;
  if (alignment == Alignment.bottomLeft) return Icons.south_west_rounded;
  if (alignment == Alignment.bottomCenter) return Icons.south_rounded;
  return Icons.south_east_rounded;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label, this.icon);

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Semantics(
        header: true,
        child: Row(
          children: <Widget>[
            Icon(icon, size: 18, color: colors.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BusyNotice extends StatelessWidget {
  const _BusyNotice({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: <Widget>[
            Icon(Icons.sync, size: 16, color: colors.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, size: 18, color: colors.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onErrorContainer,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
