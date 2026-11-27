/// Id of a user write. JS: `core/Repo.ts` (`nextWriteId_`); Android: `core/Repo.java` (`long writeId`).
library;

/// The id Repo gives every user write (set, update, transaction put), counting up from 1 per Repo.
///
/// Persisted writes keep their id; after a restart Repo continues after the highest restored id.
typedef WriteId = int;
