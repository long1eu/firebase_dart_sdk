@TestOn('browser')
@Tags(<String>['browser'])
library;

import 'package:test/test.dart';

/// A resumable upload of the client in the browser (start, chunks, query, finalize, pause and
/// resume over fetch). The resumable upload lives on branch storage/upload (agent a4-upload); when
/// it is merged, replace this body with an upload of a few MiB through the client and check the
/// stored bytes with getBytes.
void main() {
  test(
    'a resumable upload completes in the browser',
    () {},
    skip: 'resumable upload is not merged yet (branch storage/upload)',
  );
}
