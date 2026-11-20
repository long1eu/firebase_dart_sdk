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
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/array_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/delete_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_transform.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/numeric_increment_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/server_timestamp_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/transform_operation.dart';
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
/// The backend applies a write as its fields (the value of a set, or the paths of a patch's mask) followed by its
/// transforms, in order. Below, two paths overlap when one is a prefix of the other or they are equal; a path of a
/// mask "covers" the paths it is a prefix of (or equal to): the patch writes or deletes that whole subtree.
///
/// The cases, where `precondition none` is a `set` or a `delete`, `exists` is an `update` and a patch without
/// precondition is a `set` with merge:
///
/// 1. [next] is a set or a delete, without precondition, whose only transforms are server timestamps: [next] alone.
///    The document after [next] does not depend on the document before it, whatever [previous] was and whether its
///    precondition held. A set with an increment or an array transform is not merged: the local view computes such
///    a transform from the value the field had before the set, so the document the app sees would change with the
///    merge. (The emulator computes it from the new value, where the merge would make no difference.)
/// 2. [next] is a patch with no precondition or `exists`, whose transforms combine with those of [previous] as in
///    rule 3:
///    a. [previous] is a set without precondition whose only transforms are server timestamps: a set of the value of
///       [previous] patched by [next], without precondition. After [previous] the document exists, so the `exists`
///       of [next] holds. Not when [next] deletes a nested field (`a.b`) at or above a server timestamp of
///       [previous]: the timestamp creates the map `a`, which the delete leaves empty, and the merged write, which
///       drops the timestamp, would not create it.
///    b. [previous] is a patch: a patch of the union of both masks (minus the paths that a shorter path of the union
///       covers), whose value is the empty document patched by [previous] and then by [next], with the precondition
///       of [previous]. Every path of the union is a whole subtree that one of the two overwrites, and that subtree
///       after both does not depend on the document before them, so setting it (or deleting it) at once is the same.
///       Not when [next] deletes a nested field (`a.b`): after a [previous] that wrote `a.b` the delete leaves an
///       empty map `a`, and a single write that deletes `a.b` does not create `a` where it was missing.
///       Only when the precondition of [previous] is none, or both are `exists`: if [previous] fails on a missing
///       document, so does [next]; if [previous] passes (or has none), the document exists for [next].
///    c. [previous] is a delete without precondition and [next] has no precondition: a set of the empty document
///       patched by [next]. A patch without precondition of a missing document creates it from the patched fields.
///    In a and c the merged write is a set, which carries server timestamps only (rule 1 says why).
/// 3. The transforms of the merged write, applied after all of its fields (where the transforms of [previous] ran
///    before the fields of [next]):
///    a. A transform of [previous] at `p` that a path of [next]'s mask covers is dropped: [next] overwrites its
///       result. So is one at or under a server timestamp of [next]: the later timestamp overwrites it.
///    b. A transform of [previous] that overlaps no path of [next] (mask or transform) stays: [next] does not read or
///       write that subtree, so applying it after the fields of [next] instead of before is the same. Its base value
///       (see [mergedBaseMutations]) is the one recorded for [previous].
///    c. An `arrayUnion` of [previous] and one of [next] at the same path, which no path of [next]'s mask overlaps:
///       one `arrayUnion` of the elements of the first followed by those of the second, without an element equal
///       (`==`) to an earlier one. The backend first makes the field an array if it is not one, then appends in order
///       each element that is not in it yet, considering only the first of equivalent elements; two unions in a row
///       append the elements of the first and then those of the second that are in neither, and so does the one
///       union of both lists. Two `arrayRemove`s at the same path: one `arrayRemove` of the elements of both; the
///       backend removes every element equivalent to any of them, once or in two steps.
///    d. A server timestamp of [next] stays: its result does not depend on the document before it.
///    e. An `increment` of [next] at `q` where the value of `q` before it is known: [previous] is a set or a delete, or
///       a path of [previous]'s mask covers `q` and no path of [next]'s mask does, and no transform of [previous]
///       overlaps `q`. Then the field is written with the result instead of the transform, when the backend's result
///       is exact: both the value and the operand are 64-bit integers within +-(2^53 - 1), as is their sum (no
///       saturation, and the same sum compiled to JavaScript), or both are doubles (one IEEE 754 addition, as on the
///       backend and in the local view). Other number types (an integer with a double, or the BSON types) are not
///       merged: the result's type and rounding would have to be shown equal.
///    f. After a patch, an `increment`, `arrayUnion` or `arrayRemove` of [next] at `q` stays when a path of [next]'s
///       mask covers `q` (its input is what [next] wrote, in both cases) or when no path of [previous] overlaps `q`
///       (its input is the document before both). An increment only when no transform of [previous] overlaps `q`, so
///       that the base value of each increment of the merged write comes from one of the two writes.
///    Any other overlap of a transform with a path of the other write refuses the merge. In particular an `increment`
///    after an `increment` of the same field: the backend adds each operand in turn, saturating integers and rounding
///    doubles at each step, so adding the two operands first can give another result (on a field that holds the
///    double 2^53, `+ 1` twice leaves 2^53 and `+ 2` once gives 2^53 + 2; on an integer field near the maximum, `+ 5`
///    then `- 5` is not `+ 0`), and the field's value is not known. Also an array transform after a value that [previous] wrote (equality of elements
///    across number types), a union after a remove (or the reverse), and an increment after an array transform.
///
/// Everything else stays queued as two writes: a patch with `exists` after a delete or after a patch without
/// precondition (which [previous] could leave failing differently), a set with transforms other than server
/// timestamps as [previous] of a patch, `updateTime` preconditions and verify mutations (transactions, which are not
/// queued), and empty field paths.
///
/// The local view of the merged write equals that of the two, except for server timestamps of [previous] that stay:
/// their estimate takes the local write time of [next].
Mutation? mergeUnsentMutations(Mutation previous, Mutation next) {
  if (previous.key != next.key ||
      !_isPlainWrite(previous) ||
      _hasEmptyTransformPath(previous) ||
      _hasEmptyTransformPath(next)) {
    return null;
  }

  if ((next is SetMutation || next is DeleteMutation) &&
      next.precondition.isNone &&
      next.fieldTransforms.every(
        (FieldTransform transform) =>
            transform.operation is ServerTimestampOperation,
      )) {
    return next;
  }

  if (next is! PatchMutation ||
      !_isNoneOrExists(next.precondition) ||
      next.mask.mask.any((FieldPath path) => path.isEmpty)) {
    return null;
  }

  switch (previous) {
    case SetMutation():
      if (!previous.precondition.isNone ||
          !previous.fieldTransforms.every(
            (FieldTransform transform) =>
                transform.operation is ServerTimestampOperation,
          ) ||
          _deletesTransformedField(next, previous)) {
        return null;
      }
      final _MergedTransforms? merged = _mergeTransforms(
        previous,
        next,
        next.patchObject(previous.value),
        previousMask: null,
      );
      if (merged == null) {
        return null;
      }
      return SetMutation(
        next.key,
        merged.value,
        Precondition.none,
        merged.transforms,
      );
    case PatchMutation():
      final Precondition before = previous.precondition;
      if (previous.mask.mask.any((FieldPath path) => path.isEmpty) ||
          _deletesNestedField(next) ||
          !(before.isNone ||
              (before.exists == true && next.precondition.exists == true))) {
        return null;
      }
      final _MergedTransforms? merged = _mergeTransforms(
        previous,
        next,
        next.patchObject(previous.patchObject(ObjectValue.empty)),
        previousMask: previous.mask.mask,
      );
      if (merged == null) {
        return null;
      }
      return PatchMutation(
        next.key,
        merged.value,
        _union(previous.mask, next.mask),
        before,
        merged.transforms,
      );
    case DeleteMutation():
      if (!previous.precondition.isNone || !next.precondition.isNone) {
        return null;
      }
      final _MergedTransforms? merged = _mergeTransforms(
        previous,
        next,
        next.patchObject(ObjectValue.empty),
        previousMask: null,
      );
      if (merged == null) {
        return null;
      }
      return SetMutation(
        next.key,
        merged.value,
        Precondition.none,
        merged.transforms,
      );
    default:
      return null;
  }
}

/// The base mutations of the batch of [merged], the write that [mergeUnsentMutations] made of the only write of
/// [replaced] and a new write whose base mutations are [nextBaseMutations] (computed on the local view after
/// [replaced]).
///
/// The local view applies an increment to its base value, recorded when it was written. Each increment of [merged]
/// is one of the two writes, unchanged (rule 3 of [mergeUnsentMutations]): one of [replaced] keeps the base value
/// recorded for it, the value before [replaced] (the value after it already includes the increment); one of the new
/// write keeps the base value it was given. The other transforms have no base value.
List<Mutation> mergedBaseMutations(
  MutationBatch replaced,
  List<Mutation> nextBaseMutations,
  Mutation merged,
) {
  final Set<FieldPath> previousPaths = <FieldPath>{
    for (FieldTransform transform in replaced.mutations.single.fieldTransforms)
      transform.fieldPath,
  };
  ObjectValue? base;
  for (FieldTransform transform in merged.fieldTransforms) {
    if (transform.operation is! NumericIncrementTransformOperation) {
      continue;
    }
    final List<Mutation> source = previousPaths.contains(transform.fieldPath)
        ? replaced.baseMutations
        : nextBaseMutations;
    for (Mutation mutation in source) {
      final FieldValue? value =
          mutation is PatchMutation && mutation.key == merged.key
          ? mutation.value.get(transform.fieldPath)
          : null;
      if (value != null) {
        base = (base ?? ObjectValue.empty).set(transform.fieldPath, value);
      }
    }
  }
  if (base == null) {
    return const <Mutation>[];
  }
  return <Mutation>[
    PatchMutation(merged.key, base, base.fieldMask, Precondition(exists: true)),
  ];
}

/// The transforms of the write merged from [previous] and [next], and [value] (the fields of the merged write) with
/// the increments of [next] that rule 3e turns into values; null when a transform cannot be merged. [previousMask] is
/// the mask of [previous] when it is a patch, and null when it is a set or a delete (whose merged write is a set:
/// the value of every field before the transforms of [next] is known).
_MergedTransforms? _mergeTransforms(
  Mutation previous,
  PatchMutation next,
  ObjectValue value, {
  required Set<FieldPath>? previousMask,
}) {
  final Set<FieldPath> nextMask = next.mask.mask;
  final bool isSet = previousMask == null;
  final List<FieldTransform> transforms = <FieldTransform>[];
  // The transforms of [next] that are combined with one of [previous] (rule 3c).
  final Set<FieldTransform> combined = <FieldTransform>{};

  for (FieldTransform transform in previous.fieldTransforms) {
    final FieldPath path = transform.fieldPath;
    if (nextMask.any((FieldPath other) => other.isPrefixOf(path))) {
      continue;
    }
    if (nextMask.any((FieldPath other) => path.isPrefixOf(other))) {
      return null;
    }
    final List<FieldTransform> overlapping = <FieldTransform>[
      for (FieldTransform other in next.fieldTransforms)
        if (_overlap(path, other.fieldPath)) other,
    ];
    if (overlapping.isEmpty) {
      transforms.add(transform);
      continue;
    }
    if (overlapping.length > 1) {
      // Several transforms of [next] under this one.
      return null;
    }
    final FieldTransform other = overlapping.single;
    if (other.operation is ServerTimestampOperation &&
        other.fieldPath.isPrefixOf(path)) {
      continue;
    }
    final FieldTransform? union = isSet || other.fieldPath != path
        ? null
        : _combineArrayTransforms(transform, other);
    if (union == null) {
      return null;
    }
    transforms.add(union);
    combined.add(other);
  }

  for (FieldTransform transform in next.fieldTransforms) {
    final FieldPath path = transform.fieldPath;
    final TransformOperation operation = transform.operation;
    if (combined.contains(transform)) {
      continue;
    }
    if (operation is ServerTimestampOperation) {
      transforms.add(transform);
      continue;
    }
    final bool overlapsPrevious = previous.fieldTransforms.any(
      (FieldTransform other) => _overlap(path, other.fieldPath),
    );
    if (operation is NumericIncrementTransformOperation && overlapsPrevious) {
      return null;
    }
    if (!isSet && nextMask.any((FieldPath other) => other.isPrefixOf(path))) {
      transforms.add(transform);
    } else if (overlapsPrevious) {
      return null;
    } else if (isSet ||
        previousMask.any((FieldPath other) => other.isPrefixOf(path))) {
      final FieldValue? result = operation is NumericIncrementTransformOperation
          ? _increment(value.get(path), operation.operand)
          : null;
      if (result == null) {
        return null;
      }
      value = value.set(path, result);
    } else if (previousMask.any((FieldPath other) => path.isPrefixOf(other))) {
      return null;
    } else {
      transforms.add(transform);
    }
  }
  return (transforms: transforms, value: value);
}

typedef _MergedTransforms = ({
  List<FieldTransform> transforms,
  ObjectValue value,
});

/// One `arrayUnion` of the elements of [first] and then [second], or one `arrayRemove`, without the elements equal to
/// an earlier one (see rule 3c of [mergeUnsentMutations]); null for any other pair.
FieldTransform? _combineArrayTransforms(
  FieldTransform first,
  FieldTransform second,
) {
  final TransformOperation a = first.operation;
  final TransformOperation b = second.operation;
  final bool unions =
      a is ArrayTransformOperationUnion && b is ArrayTransformOperationUnion;
  final bool removes =
      a is ArrayTransformOperationRemove && b is ArrayTransformOperationRemove;
  if (!unions && !removes) {
    return null;
  }
  final List<FieldValue> elements = <FieldValue>[];
  for (FieldValue element in <FieldValue>[
    ...(a as ArrayTransformOperation).elements,
    ...(b as ArrayTransformOperation).elements,
  ]) {
    if (!elements.contains(element)) {
      elements.add(element);
    }
  }
  return FieldTransform(
    first.fieldPath,
    unions
        ? ArrayTransformOperationUnion(elements)
        : ArrayTransformOperationRemove(elements),
  );
}

/// The largest integer that a double (and so an `int` compiled to JavaScript) holds exactly, 2^53 - 1.
const int _maxSafeInteger = 9007199254740991;

bool _isSafeInteger(int value) =>
    value >= -_maxSafeInteger && value <= _maxSafeInteger;

/// The value of a field that holds [value] after `increment(operand)`, when the backend's result is known exactly
/// (rule 3e of [mergeUnsentMutations]), or null.
FieldValue? _increment(FieldValue? value, NumberValue operand) {
  if (value is IntegerValue && operand is IntegerValue) {
    final int sum = value.value + operand.value;
    if (!_isSafeInteger(value.value) ||
        !_isSafeInteger(operand.value) ||
        !_isSafeInteger(sum)) {
      return null;
    }
    return IntegerValue.valueOf(sum);
  }
  if (value is DoubleValue && operand is DoubleValue) {
    return DoubleValue.valueOf(value.value + operand.value);
  }
  return null;
}

/// Whether one of [a] and [b] is a prefix of (or equal to) the other.
bool _overlap(FieldPath a, FieldPath b) => a.isPrefixOf(b) || b.isPrefixOf(a);

bool _hasEmptyTransformPath(Mutation mutation) => mutation.fieldTransforms.any(
  (FieldTransform transform) => transform.fieldPath.isEmpty,
);

/// A set, patch or delete with no precondition or an `exists` one (what the user API writes).
bool _isPlainWrite(Mutation mutation) =>
    (mutation is SetMutation ||
        mutation is PatchMutation ||
        mutation is DeleteMutation) &&
    _isNoneOrExists(mutation.precondition);

/// Whether the mask of [patch] has a nested path without a value: a delete of a field inside a map.
bool _deletesNestedField(PatchMutation patch) => patch.mask.mask.any(
  (FieldPath path) => path.length > 1 && patch.value.get(path) == null,
);

/// Whether [next] deletes a nested field (`a.b`) at or above a field that a transform of [previous] writes: the
/// transform creates the map `a`, which stays (empty) after the delete, but the merged write drops the transform and
/// would not create `a` (rule 2a of [mergeUnsentMutations]).
bool _deletesTransformedField(PatchMutation next, Mutation previous) =>
    next.mask.mask.any(
      (FieldPath path) =>
          path.length > 1 &&
          next.value.get(path) == null &&
          previous.fieldTransforms.any(
            (FieldTransform transform) => path.isPrefixOf(transform.fieldPath),
          ),
    );

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
