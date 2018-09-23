// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'dart:async';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart' as core;
import 'package:firebase_firestore/src/firebase/firestore/model/resource_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/user_data_converter.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/util.dart';

/**
 * A DocumentReference refers to a document location in a Firestore database and can be used to
 * write, read, or listen to the location. There may or may not exist a document at the referenced
 * location. A DocumentReference can also be used to create a CollectionReference to a
 * subcollection.
 *
 * <p><b>Subclassing Note</b>: Firestore classes are not meant to be subclassed except for use in
 * test mocks. Subclassing is not supported in production code and new SDK releases may break code
 * that does so.
 */
@publicApi
class DocumentReference {

  final DocumentKey key;

  final FirebaseFirestore firestore;

  DocumentReference(this.key, this.firestore)
      :assert(key != null),
        assert(firestore != null);

  /** @hide */
  static DocumentReference forPath(ResourcePath path,
      FirebaseFirestore firestore) {
    if (path.length % 2 != 0) {
      throw new ArgumentError(
          "Invalid document reference. Document references must have an even number of segments, but ${path
              .canonicalString} has ${path.length}");
    }

    return new DocumentReference(DocumentKey.fromPath(path), firestore);
  }


  @publicApi
  String get id => key.path.getLastSegment();

  /**
   * Gets a CollectionReference to the collection that contains this document.
   *
   * @return The CollectionReference that contains this document.
   */
  @publicApi
  CollectionReference get parent {
    return new CollectionReference(key.path.popLast(), firestore);
  }

  /**
   * Gets the path of this document (relative to the root of the database) as a slash-separated
   * string.
   *
   * @return The path of this document.
   */
  @publicApi
  String get path {
    return key.path.canonicalString;
  }

  /**
   * Gets a CollectionReference instance that refers to the subcollection at the specified path
   * relative to this document.
   *
   * @param collectionPath A slash-separated relative path to a subcollection.
   * @return The CollectionReference instance.
   */
  @publicApi
  CollectionReference collection(String collectionPath) {
    Assert.checkNotNull(
        collectionPath, "Provided collection path must not be null.");
    return new CollectionReference(
        key.path.appendPath(ResourcePath.fromString(collectionPath)),
        firestore);
  }

  /**
   * Overwrites the document referred to by this DocumentReference. If the document does not yet
   * exist, it will be created. If a document already exists, it will be overwritten.
   *
   * @param data A map of the fields and values for the document.
   * @return A Future that will be resolved when the write finishes.
   */

  @publicApi
  Future<void> set(Map<String, Object> data) {
    return set(data, SetOptions.OVERWRITE);
  }

  /**
   * Writes to the document referred to by this DocumentReference. If the document does not yet
   * exist, it will be created. If you pass {@link SetOptions}, the provided data can be merged into
   * an existing document.
   *
   * @param data A map of the fields and values for the document.
   * @param options An object to configure the set behavior.
   * @return A Future that will be resolved when the write finishes.
   */

  @publicApi
  Future<void> set(Map<String, Object> data, SetOptions options) {
    Assert.checkNotNull(data, "Provided data must not be null.");
    Assert.checkNotNull(options, "Provided options must not be null.");
    ParsedDocumentData parsed =
    options.isMerge()
        ? firestore.getDataConverter().parseMergeData(
        data, options.getFieldMask())
        : firestore.getDataConverter().parseSetData(data);
    return firestore
        .getClient()
        .write(parsed.toMutationList(key, Precondition.none))
        .continueWith(Executors.DIRECT_EXECUTOR, voidErrorTransformer());
  }

  /**
   * Overwrites the document referred to by this DocumentReference. If the document does not yet
   * exist, it will be created. If a document already exists, it will be overwritten.
   *
   * @param pojo The POJO that will be used to populate the document contents
   * @return A Future that will be resolved when the write finishes.
   */

  @publicApi
  Future<void> set(Object pojo) {
    return set(
        firestore.getDataConverter().convertPOJO(pojo), SetOptions.OVERWRITE);
  }

  /**
   * Writes to the document referred to by this DocumentReference. If the document does not yet
   * exist, it will be created. If you pass {@link SetOptions}, the provided data can be merged into
   * an existing document.
   *
   * @param pojo The POJO that will be used to populate the document contents
   * @param options An object to configure the set behavior.
   * @return A Future that will be resolved when the write finishes.
   */

  @publicApi
  Future<void> set(Object pojo, SetOptions options) {
    return set(firestore.getDataConverter().convertPOJO(pojo), options);
  }

  /**
   * Updates fields in the document referred to by this DocumentReference. If no document exists
   * yet, the update will fail.
   *
   * @param data A map of field / value pairs to update. Fields can contain dots to reference nested
   *     fields within the document.
   * @return A Future that will be resolved when the write finishes.
   */

  @publicApi
  Future<void> update(Map<String, Object> data) {
    ParsedUpdateData parsedData = firestore.getDataConverter().parseUpdateData(
        data);
    return update(parsedData);
  }

  /**
   * Updates fields in the document referred to by this DocumentReference. If no document exists
   * yet, the update will fail.
   *
   * @param field The first field to update. Fields can contain dots to reference a nested field
   *     within the document.
   * @param value The first value
   * @param moreFieldsAndValues Additional field/value pairs.
   * @return A Future that will be resolved when the write finishes.
   */

  @publicApi
  Future<void> update(String field, Object value,
      List<Object> moreFieldsAndValues) {
    ParsedUpdateData parsedData =
    firestore
        .getDataConverter()
        .parseUpdateData(
        Util.collectUpdateArguments(
          /* fieldPathOffset= */
          1, field, value, moreFieldsAndValues,));
    return update(parsedData);
  }

  /**
   * Updates fields in the document referred to by this DocumentReference. If no document exists
   * yet, the update will fail.
   *
   * @param fieldPath The first field to update.
   * @param value The first value
   * @param moreFieldsAndValues Additional field/value pairs.
   * @return A Future that will be resolved when the write finishes.
   */

  @publicApi
  Future<void> update(FieldPath fieldPath, Object value,
      List<Object> moreFieldsAndValues) {
    ParsedUpdateData parsedData =
    firestore
        .getDataConverter()
        .parseUpdateData(
        Util.collectUpdateArguments(
          /* fieldPathOffset= */
            1, fieldPath, value, moreFieldsAndValues));
    return update(parsedData);
  }

  //p
  Future<void> update(ParsedUpdateData parsedData) {
    return firestore
        .getClient()
        .write(parsedData.toMutationList(key, Precondition.exists(true)))
        .continueWith(Executors.DIRECT_EXECUTOR, voidErrorTransformer());
  }

  /**
   * Deletes the document referred to by this DocumentReference.
   *
   * @return A Future that will be resolved when the delete completes.
   */

  @publicApi
  Future<void> delete() {
    return firestore
        .getClient()
        .write([new DeleteMutation(key, Precondition.none)])
        .continueWith(Executors.DIRECT_EXECUTOR, voidErrorTransformer());
  }

  /**
   * Reads the document referenced by this DocumentReference.
   *
   * @return A Future that will be resolved with the contents of the Document at this
   *     DocumentReference.
   */

  @publicApi
  Future<DocumentSnapshot> get() {
    return get(Source.DEFAULT);
  }

  /**
   * Reads the document referenced by this DocumentReference.
   *
   * <p>By default, {@code get()} attempts to provide up-to-date data when possible by waiting for
   * data from the server, but it may return cached data or fail if you are offline and the server
   * cannot be reached. This behavior can be altered via the {@link Source} parameter.
   *
   * @param source A value to configure the get behavior.
   * @return A Future that will be resolved with the contents of the Document at this
   *     DocumentReference.
   */

  @publicApi
  Future<DocumentSnapshot> get(Source source) {
    if (source == Source.CACHE) {
      return firestore
          .getClient()
          .getDocumentFromLocalCache(key)
          .continueWith(
          Executors.DIRECT_EXECUTOR,
              (Future<Document> doc) =>
              DocumentSnapshot(
                  firestore, key, doc.getResult(), /*isFromCache=*/ true));
    } else {
      return getViaSnapshotListener(source);
    }
  }

  //p
  Future<DocumentSnapshot> getViaSnapshotListener(Source source) {
    final Completer<DocumentSnapshot> res = Completer<DocumentSnapshot>();
    final Completer<ListenerRegistration> registration = Completer<ListenerRegistration>();

    ListenOptions options = new ListenOptions();
    options.includeDocumentMetadataChanges = true;
    options.includeQueryMetadataChanges = true;
    options.waitForSyncWhenOnline = true;
    /*ListenerRegistration listenerRegistration =
        addSnapshotListenerInternal(
            // No need to schedule, we just set the task result directly
            Executors.DIRECT_EXECUTOR,
            options,
            null,
            (snapshot, error) -> {
              if (error != null) {
                res.setException(error);
                return;
              }

              try {
                ListenerRegistration actualRegistration = Futures.await(registration.getFuture());

                // Remove query first before passing event to user to avoid user actions affecting
                // the now stale query.
                actualRegistration.remove();

                if (!snapshot.exists() && snapshot.getMetadata().isFromCache()) {
                  // TODO: Reconsider how to raise missing documents when offline.
                  // If we're online and the document doesn't exist then we set the result
                  // of the Future with a document with document.exists set to false. If we're
                  // offline however, we set the Exception on the Future. Two options:
                  //
                  // 1)  Cache the negative response from the server so we can deliver that
                  //     even when you're offline.
                  // 2)  Actually set the Exception of the Future if the document doesn't
                  //     exist when you are offline.
                  res.setException(
                      new FirebaseFirestoreException(
                          "Failed to get document because the client is offline.",
                          Code.UNAVAILABLE));
                } else if (snapshot.exists()
                    && snapshot.getMetadata().isFromCache()
                    && source == Source.SERVER) {
                  res.setException(
                      new FirebaseFirestoreException(
                          "Failed to get document from server. (However, this document does exist "
                              + "in the local cache. Run again without setting source to SERVER to "
                              + "retrieve the cached document.)",
                          Code.UNAVAILABLE));
                } else {
                  res.setResult(snapshot);
                }
              } catch (ExecutionException e) {
                throw fail(e, "Failed to register a listener for a single document");
              } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw fail(e, "Failed to register a listener for a single document");
              }
            });

    registration.setResult(listenerRegistration);

    return res.getFuture();*/
  }

  /**
   * Starts listening to the document referenced by this DocumentReference.
   *
   * @param listener The event listener that will be called with the snapshots.
   * @return A registration object that can be used to remove the listener.
   */

  @publicApi
  ListenerRegistration addSnapshotListener(
      EventListener<DocumentSnapshot> listener) {
    return addSnapshotListener(MetadataChanges.EXCLUDE, listener);
  }

  /**
   * Starts listening to the document referenced by this DocumentReference.
   *
   * @param executor The executor to use to call the listener.
   * @param listener The event listener that will be called with the snapshots.
   * @return A registration object that can be used to remove the listener.
   */

  @publicApi
  ListenerRegistration addSnapshotListener(Executor executor,
      EventListener<DocumentSnapshot> listener) {
    return addSnapshotListener(executor, MetadataChanges.EXCLUDE, listener);
  }

  /**
   * Starts listening to the document referenced by this DocumentReference using an Activity-scoped
   * listener.
   *
   * <p>The listener will be automatically removed during {@link Activity#onStop}.
   *
   * @param activity The activity to scope the listener to.
   * @param listener The event listener that will be called with the snapshots.
   * @return A registration object that can be used to remove the listener.
   */

  @publicApi
  ListenerRegistration addSnapshotListener(Activity activity,
      EventListener<DocumentSnapshot> listener) {
    return addSnapshotListener(activity, MetadataChanges.EXCLUDE, listener);
  }

  /**
   * Starts listening to the document referenced by this DocumentReference with the given options.
   *
   * @param metadataChanges Indicates whether metadata-only changes (i.e. only {@code
   *     DocumentSnapshot.getMetadata()} changed) should trigger snapshot events.
   * @param listener The event listener that will be called with the snapshots.
   * @return A registration object that can be used to remove the listener.
   */

  @publicApi
  ListenerRegistration addSnapshotListener(MetadataChanges metadataChanges,
      EventListener<DocumentSnapshot> listener) {
    return addSnapshotListener(
        Executors.DEFAULT_CALLBACK_EXECUTOR, metadataChanges, listener);
  }

  /**
   * Starts listening to the document referenced by this DocumentReference with the given options.
   *
   * @param executor The executor to use to call the listener.
   * @param metadataChanges Indicates whether metadata-only changes (i.e. only {@code
   *     DocumentSnapshot.getMetadata()} changed) should trigger snapshot events.
   * @param listener The event listener that will be called with the snapshots.
   * @return A registration object that can be used to remove the listener.
   */

  @publicApi
  ListenerRegistration addSnapshotListener(Executor executor,
      MetadataChanges metadataChanges,
      EventListener<DocumentSnapshot> listener) {
    checkNotNull(executor, "Provided executor must not be null.");
    checkNotNull(
        metadataChanges, "Provided MetadataChanges value must not be null.");
    checkNotNull(listener, "Provided EventListener must not be null.");
    return addSnapshotListenerInternal(
        executor, internalOptions(metadataChanges), null, listener);
  }

  /**
   * Starts listening to the document referenced by this DocumentReference with the given options
   * using an Activity-scoped listener.
   *
   * <p>The listener will be automatically removed during {@link Activity#onStop}.
   *
   * @param activity The activity to scope the listener to.
   * @param metadataChanges Indicates whether metadata-only changes (i.e. only {@code
   *     DocumentSnapshot.getMetadata()} changed) should trigger snapshot events.
   * @param listener The event listener that will be called with the snapshots.
   * @return A registration object that can be used to remove the listener.
   */

  @publicApi
  ListenerRegistration addSnapshotListener(Activity activity,
      MetadataChanges metadataChanges,
      EventListener<DocumentSnapshot> listener) {
    checkNotNull(activity, "Provided activity must not be null.");
    checkNotNull(
        metadataChanges, "Provided MetadataChanges value must not be null.");
    checkNotNull(listener, "Provided EventListener must not be null.");
    return addSnapshotListenerInternal(
        Executors.DEFAULT_CALLBACK_EXECUTOR, internalOptions(metadataChanges),
        activity, listener);
  }

  /**
   * Internal helper method to create add a snapshot listener.
   *
   * <p>Will be Activity scoped if the activity parameter is non-null.
   *
   * @param executor The executor to use to call the listener.
   * @param options The options to use for this listen.
   * @param activity Optional activity this listener is scoped to.
   * @param listener The event listener that will be called with the snapshots.
   * @return A registration object that can be used to remove the listener.
   */
  //p
  ListenerRegistration addSnapshotListenerInternal(Executor executor,
      ListenOptions options,
      Activity activity,
      EventListener<DocumentSnapshot> listener) {
    ExecutorEventListener<ViewSnapshot> wrappedListener =
    new ExecutorEventListener<>(
        executor,
            (snapshot, error) {
          if (snapshot != null) {
            Assert.hardAssert(
                snapshot.getDocuments().size() <= 1,
                "Too many documents returned on a document query");
            Document document = snapshot.getDocuments().getDocument(key);
            DocumentSnapshot documentSnapshot;
            if (document != null) {
              documentSnapshot =
                  DocumentSnapshot.fromDocument(
                      firestore, document, snapshot.isFromCache());
            } else {
              documentSnapshot =
                  DocumentSnapshot.fromNoDocument(
                      firestore, key, snapshot.isFromCache());
            }
            listener.onEvent(documentSnapshot, null);
          } else {
            Assert.hardAssert(
                error != null, "Got event without value or error set");
            listener.onEvent(null, error);
          }
        });
    core.Query query = asQuery();
    QueryListener queryListener = firestore.getClient().listen(
        query, options, wrappedListener);
    return new ListenerRegistrationImpl(
        firestore.getClient(), queryListener, activity, wrappedListener);
  }

  /*
  @override
  public bool equals(Object o) {
    if (this == o) {
      return true;
    }
    if (o == null || getClass() != o.getClass()) {
      return false;
    }

    DocumentReference that = (DocumentReference) o;

    return key.equals(that.key) && firestore.equals(that.firestore);
  }

  @override
   int hashCode() {
    int result = key.hashCode();
    result = 31 * result + firestore.hashCode();
    return result;
  }
  */

  core.Query asQuery() {
    return core.Query.atPath(key.path);
  }

  /** Converts the public API MetadataChanges object to the internal options object. */
  //p
  static ListenOptions internalOptions(MetadataChanges metadataChanges) {
    ListenOptions internalOptions = new ListenOptions();
    internalOptions.includeDocumentMetadataChanges =
    (metadataChanges == MetadataChanges.INCLUDE);
    internalOptions.includeQueryMetadataChanges =
    (metadataChanges == MetadataChanges.INCLUDE);
    internalOptions.waitForSyncWhenOnline = false;
    return internalOptions;
  }
}
