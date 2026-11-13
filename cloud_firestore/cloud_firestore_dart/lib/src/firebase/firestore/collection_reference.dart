// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

// [CollectionReference] lives next to [Query], whose private constructor it
// calls. This library keeps the old import path working.
export 'package:cloud_firestore_dart/src/firebase/firestore/query.dart'
    show CollectionReference, CollectionReferenceInternal, QueryInternal;
