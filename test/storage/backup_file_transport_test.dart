import 'dart:typed_data';

import 'package:companion_focus/core/storage/backup_file_transport.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(AndroidBackupFileBackend.channelName);
  late List<MethodCall> calls;
  late Object? Function(MethodCall call) respond;

  setUp(() {
    calls = <MethodCall>[];
    respond = (_) => throw StateError('No bridge response configured.');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return respond(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  BackupFileTransport androidTransport() =>
      BackupFileTransport(backend: const AndroidBackupFileBackend());

  Matcher failsWith(BackupFileError error) => throwsA(
    isA<BackupFileException>().having(
      (BackupFileException failure) => failure.error,
      'error',
      error,
    ),
  );

  test('save sends the public file name and exact bytes to the bridge', () async {
    respond = (_) => true;
    final bytes = Uint8List.fromList(<int>[0x7b, 0x7d]);

    expect(await androidTransport().save(bytes), isTrue);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'save');
    final arguments = calls.single.arguments as Map<Object?, Object?>;
    expect(arguments['fileName'], 'minutemeadow-backup.json');
    expect(arguments['fileName'], isNot(contains('/')));
    expect(arguments['fileName'], isNot(contains('\\')));
    expect(arguments['bytes'], isA<Uint8List>());
    expect(arguments['bytes'], orderedEquals(bytes));
  });

  test('a cancelled save is reported as false, not as a write failure', () async {
    respond = (_) => false;

    expect(await androidTransport().save(Uint8List.fromList(<int>[1])), isFalse);
  });

  test('a cancelled pick is reported as null, not as a read failure', () async {
    respond = (_) => null;

    expect(await androidTransport().load(), isNull);
  });

  test('pick returns the bridge bytes unchanged', () async {
    final bytes = Uint8List.fromList(<int>[0x7b, 0x7d]);
    respond = (_) => bytes;

    final picked = await androidTransport().load();

    expect(picked, orderedEquals(bytes));
    expect(calls.single.method, 'pick');
  });

  test('a pick above the fixed cap is rejected', () async {
    respond = (_) => Uint8List(BackupFileTransport.maxBytes + 1);

    await expectLater(
      androidTransport().load(),
      failsWith(BackupFileError.tooLarge),
    );
  });

  test('save refuses an oversized payload without touching the bridge', () async {
    final bytes = Uint8List(BackupFileTransport.maxBytes + 1);

    await expectLater(
      androidTransport().save(bytes),
      failsWith(BackupFileError.tooLarge),
    );
    expect(calls, isEmpty);
  });

  test('a non-byte pick payload is a read failure', () async {
    respond = (_) => 'not bytes';

    await expectLater(
      androidTransport().load(),
      failsWith(BackupFileError.readFailed),
    );
  });

  test('native read and type errors stay distinct from cancellation', () async {
    respond = (_) => throw PlatformException(code: 'read_failed');
    await expectLater(
      androidTransport().load(),
      failsWith(BackupFileError.readFailed),
    );

    respond = (_) => throw PlatformException(code: 'unsupported_type');
    await expectLater(
      androidTransport().load(),
      failsWith(BackupFileError.unsupportedType),
    );
  });

  test('an engine teardown during a save is a cancellation', () async {
    respond = (_) => throw PlatformException(code: 'cancelled');

    expect(await androidTransport().save(Uint8List.fromList(<int>[1])), isFalse);
  });

  test('an engine teardown during a pick is a cancellation', () async {
    respond = (_) => throw PlatformException(code: 'cancelled');

    expect(await androidTransport().load(), isNull);
  });

  test('an overlapping native request is reported as busy', () async {
    respond = (_) => throw PlatformException(code: 'busy');

    await expectLater(
      androidTransport().load(),
      failsWith(BackupFileError.busy),
    );
  });

  test('a missing bridge is reported as unavailable', () async {
    final transport = BackupFileTransport(
      backend: const UnavailableBackupFileBackend(),
    );

    await expectLater(transport.load(), failsWith(BackupFileError.unavailable));
    await expectLater(
      transport.save(Uint8List.fromList(<int>[1])),
      failsWith(BackupFileError.unavailable),
    );
  });
}
