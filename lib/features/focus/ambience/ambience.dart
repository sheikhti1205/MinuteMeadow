/// Quiet, Android-only Focus ambience.
///
/// [FocusAmbiencePreferences] is the persisted choice. [FocusAmbienceController]
/// owns the play/stop decision, [FocusAmbiencePlayer] talks to the native
/// AudioTrack bridge, and [FocusAmbienceRunner] wires the controller to the
/// Focus surface and the app lifecycle. The settings editor lives in
/// `features/settings/focus_ambience_page.dart` so the settings feature keeps
/// its own presentation.
library;

export 'focus_ambience_controller.dart';
export 'focus_ambience_engine.dart';
export 'focus_ambience_player.dart';
export 'focus_ambience_preferences.dart';
export 'focus_ambience_runner.dart';
