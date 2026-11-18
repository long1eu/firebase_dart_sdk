// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/delete_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';

/// NOT IN THE OFFICIAL SDKS: the mutation that has the same effect on the backend as [previous] followed by [next]
/// (two writes to the same document, each the only write of its batch), or null when no such mutation is known to be
/// equivalent and both stay queued. See `PersistentCacheSettings.mergeUnsentWrites` for the conditions on the
/// batches; this function decides only on the two mutations.
///
/// "Same effect" means the same document on the backend when both writes reach it in order, for every state of the
/// document before them, including the outcome of their preconditions. It does not cover a rejection by security rules
/// or by a limit of the backend: then the merged write is rejected as a whole.
///
/// The cases, where `precondition none` is a `set` or a `delete`, `exists` is an `update` and a patch without
/// precondition is a `set` with merge:
///
/// 1. [next] is a set (with or without transforms) or a delete, without precondition: [next] alone. The document
///    after [next] does not depend on the document before it, whatever [previous] was and whether its precondition
///    held. The transforms of [next] are evaluated on the value of [next] in both cases.
/// 2. [next] is a patch without transforms, with no precondition or `exists`, and [previous] has no transforms:
///    a. [previous] is a set without precondition: a set of the value of [previous] patched by [next], without
///       precondition. After [previous] the document exists, so the `exists` of [next] holds.
///    b. [previous] is a patch: a patch of the union of both masks (minus the paths that a shorter path of the union
///       covers), whose value is the empty document patched by [previous] and then by [next], with the precondition
///       of [previous]. Every path of the union is a whole subtree that one of the two overwrites, and that subtree
///       after both does not depend on the document before them, so setting it (or deleting it) at once is the same.
///       Only when the precondition of [previous] is none, or both are `exists`: if [previous] fails on a missing
///       document, so does [next]; if [previous] passes (or has none), the document exists for [next].
///    c. [previous] is a delete without precondition and [next] has no precondition: a set of the empty document
///       patched by [next]. A patch without precondition of a missing document creates it from the patched fields.
///
/// Everything else stays queued as two writes: transforms in a patch or under a later patch (their result depends on
/// the state they apply to and on base values recorded at write time), a patch with `exists` after a delete or after
/// a patch without precondition (which [previous] could leave failing differently), `updateTime` preconditions and
/// verify mutations (transactions, which are not queued), and empty field paths.
Mutation? mergeUnsentMutations(Mutation previous, Mutation next) {
  if (previous.key != next.key || !_isPlainWrite(previous)) {
    return null;
  }

  if ((next is SetMutation || next is DeleteMutation) &&
      next.precondition.isNone) {
    return next;
  }

  if (next is! PatchMutation ||
      next.fieldTransforms.isNotEmpty ||
      previous.fieldTransforms.isNotEmpty ||
      !_isNoneOrExists(next.precondition) ||
      next.mask.mask.any((FieldPath path) => path.isEmpty)) {
    return null;
  }

  switch (previous) {
    case SetMutation():
      if (!previous.precondition.isNone) {
        return null;
      }
      return SetMutation(
        next.key,
        next.patchObject(previous.value),
        Precondition.none,
      );
    case PatchMutation():
      final Precondition before = previous.precondition;
      if (previous.mask.mask.any((FieldPath path) => path.isEmpty) ||
          !(before.isNone ||
              (before.exists == true && next.precondition.exists == true))) {
        return null;
      }
      return PatchMutation(
        next.key,
        next.patchObject(previous.patchObject(ObjectValue.empty)),
        _union(previous.mask, next.mask),
        before,
      );
    case DeleteMutation():
      if (!previous.precondition.isNone || !next.precondition.isNone) {
        return null;
      }
      return SetMutation(
        next.key,
        next.patchObject(ObjectValue.empty),
        Precondition.none,
      );
    default:
      return null;
  }
}

/// A set, patch or delete with no precondition or an `exists` one (what the user API writes).
bool _isPlainWrite(Mutation mutation) =>
    (mutation is SetMutation ||
        mutation is PatchMutation ||
        mutation is DeleteMutation) &&
    _isNoneOrExists(mutation.precondition);

bool _isNoneOrExists(Precondition precondition) =>
    precondition.isNone || precondition.exists != null;

/// The union of [a] and [b] without the paths that another path of the union is a prefix of: the shorter path already
/// overwrites the whole subtree, and the backend is not sent a mask with overlapping paths (the SDK never sends one).
FieldMask _union(FieldMask a, FieldMask b) {
  final List<FieldPath> paths = <FieldPath>{...a.mask, ...b.mask}.toList()
    ..sort();
  final Set<FieldPath> result = <FieldPath>{};
  FieldPath? kept;
  for (FieldPath path in paths) {
    // Sorted segment by segment, the paths under a prefix come right after it.
    if (kept != null && kept.isPrefixOf(path)) {
      continue;
    }
    result.add(path);
    kept = path;
  }
  return FieldMask(result);
}
