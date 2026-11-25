// Declarations of the fixture library ../fixture.dart, which exports Exposed only.
import 'package:meta/meta.dart';

/// Not exported by the fixture library.
class Hidden {}

/// Exported, with one member of each kind the checker must tell apart.
class Exposed {
  /// Names Hidden and is public: the one finding.
  Hidden leaks() => Hidden();

  /// Names Hidden but is `@internal`: skipped.
  @internal
  Hidden get guarded => Hidden();

  /// Names only dart:core types: fine.
  int fine(String text) => text.length;
}
