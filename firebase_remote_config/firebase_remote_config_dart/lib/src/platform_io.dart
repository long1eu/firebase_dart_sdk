import 'dart:io';

import 'package:firebase_remote_config_dart/src/platform.dart';

/// The language of the process: `Platform.localeName`, reduced to a BCP 47 tag.
String defaultLanguage() => normalizeLanguageTag(Platform.localeName);

/// A [Visibility] that is never hidden: the VM has no page.
Visibility createVisibility() => const _VmVisibility();

final class _VmVisibility implements Visibility {
  const _VmVisibility();

  @override
  bool get isHidden => false;

  @override
  Stream<bool> get changes => const Stream<bool>.empty();
}
