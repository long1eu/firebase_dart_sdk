import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

/// One note, as the app sees it.
class Note {
  const Note({required this.title, this.body = '', this.updatedAt});

  final String title;
  final String body;

  /// When the note was last written, by the server's clock. Null only for a
  /// document written without the field.
  final DateTime? updatedAt;
}

/// Reads and writes [Note]s as documents of the form
/// `{title: string, body: string, updatedAt: timestamp}`.
class NoteConverter extends FirestoreDataConverter<Note> {
  const NoteConverter();

  @override
  Note fromFirestore(
    DocumentSnapshot<Map<String, Object?>> snapshot,
    SnapshotOptions? options,
  ) {
    // A note written on this device and not yet acknowledged has no server
    // timestamp yet: `estimate` gives the local time instead of null.
    final Map<String, Object?> data = snapshot.data(
      serverTimestamps: ServerTimestampBehavior.estimate,
    )!;
    return Note(
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  @override
  Map<String, Object?> toFirestore(Note note, SetOptions? options) =>
      <String, Object?>{
        'title': note.title,
        'body': note.body,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
