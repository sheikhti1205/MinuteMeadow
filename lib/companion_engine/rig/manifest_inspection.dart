import 'rig_codec.dart';
import 'rig_model.dart';
import 'rig_validator.dart';

/// The result of inspecting a declarative rig manifest without applying it.
///
/// Format errors keep their JSON path. Semantic errors keep every validator
/// issue, so the laboratory can show what needs correction before a rig is
/// rendered.
final class RigManifestInspection {
  const RigManifestInspection({
    required this.raw,
    required this.issues,
    this.rig,
  });

  const RigManifestInspection.valid({
    required this.raw,
    required CompanionRig parsedRig,
  }) : rig = parsedRig,
       issues = const <RigIssue>[];

  factory RigManifestInspection.inspect(String raw) {
    try {
      return RigManifestInspection.valid(
        raw: raw,
        parsedRig: RigCodec.decode(raw),
      );
    } on RigValidationException catch (error) {
      return RigManifestInspection(raw: raw, issues: error.issues);
    } on RigFormatException catch (error) {
      return RigManifestInspection(
        raw: raw,
        issues: <RigIssue>[RigIssue(error.path, error.message)],
      );
    }
  }

  final String raw;
  final CompanionRig? rig;
  final List<RigIssue> issues;

  bool get isValid => rig != null;

  int? get schemaVersion => rig?.schemaVersion;
}
