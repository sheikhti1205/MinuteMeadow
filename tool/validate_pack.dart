import 'dart:io';

import 'package:companion_focus/core/storage/pack_archive.dart';
import 'package:companion_focus/features/companion/pack_bundle.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1 || arguments.single == '--help') {
    stdout.writeln('Usage: dart run tool/validate_pack.dart <pack.zip|pack.json>');
    if (arguments.length != 1) exitCode = 64;
    return;
  }
  final file = File(arguments.single);
  try {
    final size = await file.length();
    if (size == 0 || size > PackArchive.maximumBytes) {
      throw const FormatException('The pack file is empty or too large.');
    }
    final pack = PackBundle.fromUpload(await file.readAsBytes());
    stdout.writeln(
      '${pack.manifest.id} ${pack.manifest.version}: '
      '${pack.assets.length} verified assets, ${pack.manifest.byteSize} bytes',
    );
  } on FileSystemException {
    stderr.writeln('Could not open the pack file.');
    exitCode = 66;
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 65;
  }
}
