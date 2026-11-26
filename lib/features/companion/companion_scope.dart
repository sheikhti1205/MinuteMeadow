import 'package:flutter/widgets.dart';

import 'companion_session.dart';

/// Shares one [CompanionSession] between the library and marketplace routes.
///
/// Both pages create their own session when no scope is present. Wrapping the
/// routes in this scope keeps an install made in the marketplace visible in the
/// library without reloading the snapshot.
class CompanionSessionScope extends InheritedNotifier<CompanionSession> {
  const CompanionSessionScope({
    required CompanionSession session,
    required super.child,
    super.key,
  }) : super(notifier: session);

  static CompanionSession? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CompanionSessionScope>()?.notifier;
}
