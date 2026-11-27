import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../focus/ambience/ambience.dart';

/// Editor for the optional, Android-only Focus ambience.
///
/// The page saves each choice immediately so it never depends on the timer's
/// Sound, notification or haptics settings. Off is the default. Volume is a
/// separate low-volume control; the loop itself is started and stopped by
/// [FocusAmbienceRunner] while a Focus session is on screen.
class FocusAmbiencePage extends StatefulWidget {
  const FocusAmbiencePage({
    required this.preferences,
    required this.onSave,
    this.androidOnly,
    super.key,
  });

  /// The saved choice captured when the editor opens.
  final FocusAmbiencePreferences preferences;

  /// Persists the choice. It must complete only after the value is stored;
  /// throwing keeps the last saved value selected and shows the error.
  final Future<void> Function(FocusAmbiencePreferences) onSave;

  /// Overrides platform detection for tests and alternate runners.
  final bool? androidOnly;

  static const volumeSliderKey = Key('focus-ambience-volume');

  static Key trackKey(FocusAmbienceTrack track) =>
      ValueKey<String>('focus-ambience-${track.name}');

  static Route<void> route({
    required FocusAmbiencePreferences preferences,
    required Future<void> Function(FocusAmbiencePreferences) onSave,
    bool? androidOnly,
  }) => MaterialPageRoute<void>(
    builder: (_) => FocusAmbiencePage(
      preferences: preferences,
      onSave: onSave,
      androidOnly: androidOnly,
    ),
  );

  @override
  State<FocusAmbiencePage> createState() => _FocusAmbiencePageState();
}

class _FocusAmbiencePageState extends State<FocusAmbiencePage> {
  late FocusAmbiencePreferences _value = widget.preferences;
  late FocusAmbiencePreferences _saved = widget.preferences;
  FocusAmbiencePreferences? _queued;
  bool _saving = false;
  String? _error;

  bool get _supported =>
      widget.androidOnly ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  void _select(FocusAmbienceTrack track) {
    if (_value.track == track) return;
    _commit(_value.copyWith(track: track));
  }

  void _previewVolume(double volume) {
    setState(() => _value = _value.copyWith(volume: volume));
  }

  void _endVolume(double volume) {
    _commit(_value.copyWith(volume: volume));
  }

  void _commit(FocusAmbiencePreferences next) {
    setState(() {
      _value = next;
      _error = null;
    });
    if (_queued == null && !_saving && next == _saved) return;
    _queued = next;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      while (_queued != null) {
        final next = _queued!;
        _queued = null;
        try {
          await widget.onSave(next);
          _saved = next;
        } catch (_) {
          _queued = null;
          if (mounted) {
            setState(() {
              _value = _saved;
              _error = 'Could not save Focus ambience. Try again.';
            });
          }
          break;
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Focus ambience')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (!_supported)
              const _Note('Focus ambience is available on Android.')
            else ...[
              if (_error case final String message)
                _ErrorNotice(message: message),
              const _SectionHeader('Sound', Icons.graphic_eq),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final track in FocusAmbienceTrack.values)
                    ChoiceChip(
                      key: FocusAmbiencePage.trackKey(track),
                      label: Text(track.label),
                      selected: _value.track == track,
                      onSelected: (_) => _select(track),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const _Note(
                'Off by default. Ambience plays quietly during a focus '
                'session and never replaces timer alerts, notifications or '
                'other audio.',
              ),
              const _SectionHeader('Volume', Icons.volume_down_outlined),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      key: FocusAmbiencePage.volumeSliderKey,
                      value: _value.volume.clamp(0.0, 1.0).toDouble(),
                      divisions: 20,
                      label: '${(_value.volume * 100).round()}%',
                      semanticFormatterCallback: (value) =>
                          'Focus ambience volume ${(value * 100).round()}%',
                      onChanged: _previewVolume,
                      onChangeEnd: _endVolume,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      '${(_value.volume * 100).round()}%',
                      maxLines: 1,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (_saving)
                Semantics(
                  liveRegion: true,
                  child: const _Note('Saving…'),
                ),
              const SizedBox(height: 8),
              const _Note(
                'Keeps playing only while Focus is on screen and running. It '
                'stops when the app is hidden or paused, when you leave Focus, '
                'or when headphones disconnect.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label, this.icon);

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
      child: Semantics(
        header: true,
        child: Row(
          children: [
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

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.4,
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
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
        children: [
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
