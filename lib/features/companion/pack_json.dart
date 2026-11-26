/// Strict readers for pack JSON documents.
///
/// Pack content is untrusted input. Every object is checked against an exact
/// key set so a pack cannot carry a field the application does not understand.
library;

Map<String, Object?> packObject(
  Object? value,
  String field, {
  required Set<String> required,
  Set<String> optional = const {},
}) {
  if (value is! Map<Object?, Object?>) {
    throw FormatException('$field must be an object.');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw FormatException('$field has an invalid key.');
    }
    result[key] = entry.value;
  }
  for (final key in result.keys) {
    if (!required.contains(key) && !optional.contains(key)) {
      throw FormatException('$field has an unsupported field "$key".');
    }
  }
  for (final key in required) {
    if (!result.containsKey(key)) {
      throw FormatException('$field is missing "$key".');
    }
  }
  return result;
}

String packText(
  Object? value,
  String field, {
  int min = 1,
  int max = 256,
  RegExp? pattern,
  String? complaint,
}) {
  if (value is! String) {
    throw FormatException('$field must be text.');
  }
  if (value.length < min || value.length > max) {
    throw FormatException('$field has an invalid length.');
  }
  for (final unit in value.codeUnits) {
    if (unit < 0x20 || unit == 0x7F) {
      throw FormatException('$field has an invalid character.');
    }
  }
  if (pattern != null && !pattern.hasMatch(value)) {
    throw FormatException(complaint ?? '$field is not valid.');
  }
  return value;
}

int packInteger(
  Object? value,
  String field, {
  required int min,
  required int max,
}) {
  if (value is! int) {
    throw FormatException('$field must be a whole number.');
  }
  if (value < min || value > max) {
    throw FormatException('$field is out of range.');
  }
  return value;
}

bool packFlag(Object? value, String field) {
  if (value is! bool) {
    throw FormatException('$field must be true or false.');
  }
  return value;
}
