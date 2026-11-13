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

import 'dart:collection';

import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto;

/// Decides which requests of a Write stream may be sent before the responses
/// to the earlier ones arrived (pipelining), over WebChannel.
///
/// The client keeps up to ten writes in flight and, when one of them fails,
/// closes the stream and sends the ones behind it again on a new stream. That
/// is only correct if the backend did not apply those: over gRPC it ends the
/// call on the failed write. Over WebChannel a failed write is reported as a
/// message, and the Firestore emulator (v1.22.0) keeps the session alive and
/// goes on applying and acknowledging what was sent ahead (measured: a write
/// posted a second after the error was applied). A write that was sent ahead
/// can therefore be applied twice. Whether the production backend does the
/// same is not known; the JS SDK pipelines without this precaution.
///
/// So a request is only sent ahead when applying it twice gives the same
/// result as applying it once, also together with the other requests in
/// flight:
///
///  * a request with an `increment` transform is never in flight together
///    with an earlier request: it waits until every earlier response arrived;
///  * a request does not share a document with a request in flight when
///    either of them has a precondition on that document (an `update` that is
///    replayed after a `delete` of its document, which was also sent ahead,
///    would fail with NOT_FOUND although it had succeeded).
///
/// Everything else (sets, merges, deletes, updates of distinct documents, the
/// other transforms, which are idempotent) is sent ahead. Requests always go
/// out in order: when the first waiting request has to wait, so do the ones
/// behind it.
class WriteSendAheadGate {
  final Queue<_WriteInfo> _inFlight = Queue<_WriteInfo>();

  /// The number of requests whose response has not arrived.
  int get inFlight => _inFlight.length;

  /// Whether [request] may be sent now, given the requests in flight.
  bool canSend(proto.WriteRequest request) {
    if (_inFlight.isEmpty) {
      return true;
    }
    final _WriteInfo info = _WriteInfo.of(request);
    if (info.hasIncrement) {
      return false;
    }
    for (final _WriteInfo other in _inFlight) {
      if (info.documents.any(other.preconditioned.contains) ||
          info.preconditioned.any(other.documents.contains)) {
        return false;
      }
    }
    return true;
  }

  /// Records that [request] was sent.
  void sent(proto.WriteRequest request) =>
      _inFlight.add(_WriteInfo.of(request));

  /// Records the response to the oldest request in flight (the Write RPC
  /// answers every request with one response, in order).
  void responseReceived() {
    if (_inFlight.isNotEmpty) {
      _inFlight.removeFirst();
    }
  }
}

class _WriteInfo {
  _WriteInfo(this.documents, this.preconditioned, this.hasIncrement);

  factory _WriteInfo.of(proto.WriteRequest request) {
    final Set<String> documents = <String>{};
    final Set<String> preconditioned = <String>{};
    bool hasIncrement = false;
    for (final proto.Write write in request.writes) {
      final String name;
      if (write.hasUpdate()) {
        name = write.update.name;
      } else if (write.hasDelete()) {
        name = write.delete;
      } else if (write.hasVerify()) {
        name = write.verify;
      } else if (write.hasTransform()) {
        // The legacy transform write: not sent by this client. Treated as
        // not repeatable.
        name = write.transform.document;
        hasIncrement = true;
      } else {
        // Unknown to this code: never send it ahead.
        name = '';
        hasIncrement = true;
      }
      documents.add(name);
      if (write.hasCurrentDocument()) {
        preconditioned.add(name);
      }
      for (final proto.DocumentTransform_FieldTransform transform
          in write.updateTransforms) {
        if (transform.hasIncrement()) {
          hasIncrement = true;
        }
      }
    }
    return _WriteInfo(documents, preconditioned, hasIncrement);
  }

  /// The names of the documents the request writes.
  final Set<String> documents;

  /// The documents the request writes with a precondition.
  final Set<String> preconditioned;

  /// Whether a write of the request is not idempotent.
  final bool hasIncrement;
}
