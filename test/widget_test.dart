import 'package:companion_focus/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the app name on launch', (tester) async {
    app.main();
    await tester.pump();
    expect(find.text('Companion Focus'), findsOneWidget);
  });
}
