import 'package:cloud_firestore_dart/src/firebase/firestore/core/document_view_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/document_view_change_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

const DocumentViewChangeType _added = DocumentViewChangeType.added;
const DocumentViewChangeType _removed = DocumentViewChangeType.removed;
const DocumentViewChangeType _modified = DocumentViewChangeType.modified;
const DocumentViewChangeType _metadata = DocumentViewChangeType.metadata;

/// Merges [first] then [second] for one document and returns the single
/// resulting change, or null when the two cancel out.
DocumentViewChange? _merge(
  DocumentViewChangeType first,
  DocumentViewChangeType second, {
  Document? firstDoc,
  Document? secondDoc,
}) {
  final DocumentViewChangeSet set = DocumentViewChangeSet()
    ..addChange(DocumentViewChange(first, firstDoc ?? doc('c/a', 1, emptyMap)))
    ..addChange(
      DocumentViewChange(second, secondDoc ?? doc('c/a', 2, emptyMap)),
    );
  final List<DocumentViewChange> changes = set.getChanges();
  expect(changes.length, lessThanOrEqualTo(1));
  return changes.isEmpty ? null : changes.single;
}

void main() {
  group('a metadata change followed by', () {
    for (final DocumentViewChangeType next in <DocumentViewChangeType>[
      _modified,
      _removed,
      _metadata,
    ]) {
      test('$next is replaced by the later change', () {
        final Document later = doc('c/a', 2, map(<Object>['v', 2]));
        final DocumentViewChange? merged = _merge(
          _metadata,
          next,
          secondDoc: later,
        );
        expect(merged!.type, next);
        expect(merged.document, later);
      });
    }

    test('added is rejected', () {
      expect(() => _merge(_metadata, _added), throwsStateError);
    });
  });

  group(
    'a later metadata change keeps the earlier type with the new document',
    () {
      for (final DocumentViewChangeType earlier in <DocumentViewChangeType>[
        _added,
        _modified,
      ]) {
        test('after $earlier', () {
          final Document later = doc('c/a', 2, map(<Object>['v', 2]));
          final DocumentViewChange? merged = _merge(
            earlier,
            _metadata,
            secondDoc: later,
          );
          expect(merged!.type, earlier);
          expect(merged.document, later);
        });
      }

      test('but not after a removal', () {
        expect(() => _merge(_removed, _metadata), throwsStateError);
      });
    },
  );

  test(
    'removed after modified reports the removal of the earlier document',
    () {
      final Document earlier = doc('c/a', 1, map(<Object>['v', 1]));
      final DocumentViewChange? merged = _merge(
        _modified,
        _removed,
        firstDoc: earlier,
      );
      expect(merged!.type, _removed);
      expect(merged.document, earlier);
    },
  );

  test('removed after added cancels out', () {
    expect(_merge(_added, _removed), isNull);
  });

  test('added after removed becomes a modification', () {
    final DocumentViewChange? merged = _merge(_removed, _added);
    expect(merged!.type, _modified);
  });

  group('nonsensical sequences are rejected', () {
    final List<List<DocumentViewChangeType>> invalid =
        <List<DocumentViewChangeType>>[
          <DocumentViewChangeType>[_added, _added],
          <DocumentViewChangeType>[_removed, _removed],
          <DocumentViewChangeType>[_modified, _added],
          <DocumentViewChangeType>[_removed, _modified],
        ];
    for (final List<DocumentViewChangeType> pair in invalid) {
      test('${pair[1]} after ${pair[0]}', () {
        expect(
          () => _merge(pair[0], pair[1]),
          throwsA(
            isA<StateError>().having(
              (StateError e) => e.message,
              'message',
              contains('Unsupported combination'),
            ),
          ),
        );
      });
    }
  });

  test('changes to different documents are tracked independently', () {
    final DocumentViewChangeSet set = DocumentViewChangeSet()
      ..addChange(DocumentViewChange(_metadata, doc('c/a', 1, emptyMap)))
      ..addChange(DocumentViewChange(_metadata, doc('c/b', 1, emptyMap)));
    expect(
      set.getChanges().map((DocumentViewChange c) => c.document.key),
      <Object>[key('c/a'), key('c/b')],
    );
    expect(set.toString(), contains('changes'));
  });
}
