import 'dart:convert';

import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// The routes of the file API on one shared [FirebaseStorage]:
///
///     PUT    /files/<path>   store the request body; 201 with the metadata
///     GET    /files/<path>   the object; `Range: bytes=a-b` gives 206
///     DELETE /files/<path>   delete; 204
///     GET    /healthz        "ok"
///
/// Neither body is held in memory. The upload hands the request stream to a
/// resumable upload, which reads it chunk by chunk, so the request needs a
/// `Content-Length` (the size of the object is declared when the upload
/// starts). The download hands `Reference.openRead` to the response.
class FileApi {
  FileApi(this._storage);

  final FirebaseStorage _storage;

  Handler get handler {
    final Router router = Router()
      ..get('/healthz', (Request request) => Response.ok('ok'))
      ..put('/files/<path|.+>', _upload)
      ..get('/files/<path|.+>', _download)
      ..delete('/files/<path|.+>', _delete);
    return const Pipeline()
        .addMiddleware(_storageErrors)
        .addHandler(router.call);
  }

  Future<Response> _upload(Request request, String path) async {
    final int? length = request.contentLength;
    if (length == null) {
      return _json(411, <String, Object?>{
        'error': 'Content-Length is required',
      });
    }
    final UploadTask task = _storage
        .ref(path)
        .startStreamUpload(
          request.read(),
          length: length,
          metadata: SettableMetadata(
            contentType: request.headers['content-type'],
          ),
        );
    final FullMetadata metadata = await task.result;
    return _json(201, <String, Object?>{
      'path': metadata.fullPath,
      'size': metadata.size,
      'contentType': metadata.contentType,
    });
  }

  Future<Response> _download(Request request, String path) async {
    final Reference ref = _storage.ref(path);
    final FullMetadata metadata = await ref.metadata();
    final int size = metadata.size ?? 0;
    final Map<String, Object> headers = <String, Object>{
      'content-type': metadata.contentType ?? 'application/octet-stream',
      'accept-ranges': 'bytes',
    };
    final (int, int)? range = _parseRange(request.headers['range'], size);
    if (range == null) {
      return Response.ok(
        ref.openRead(),
        headers: <String, Object>{...headers, 'content-length': '$size'},
      );
    }
    final (int start, int end) = range;
    return Response(
      206,
      body: ref.openRead(start, end + 1),
      headers: <String, Object>{
        ...headers,
        'content-length': '${end - start + 1}',
        'content-range': 'bytes $start-$end/$size',
      },
    );
  }

  Future<Response> _delete(Request request, String path) async {
    await _storage.ref(path).delete();
    return Response(204);
  }

  static Handler _storageErrors(Handler inner) {
    return (Request request) async {
      try {
        return await inner(request);
      } on FirebaseStorageException catch (error) {
        return _json(_statusOf(error), <String, Object?>{
          'error': error.code,
          'message': error.message,
        });
      }
    };
  }

  static int _statusOf(FirebaseStorageException error) => switch (error.code) {
    'object-not-found' => 404,
    'unauthenticated' => 401,
    'unauthorized' => 403,
    'quota-exceeded' => 507,
    'canceled' => 499,
    'invalid-argument' || 'invalid-format' => 400,
    _ => 502,
  };

  static Response _json(int status, Object body) => Response(
    status,
    body: jsonEncode(body),
    headers: <String, Object>{'content-type': 'application/json'},
  );
}

/// The first range of `bytes=a-b`, `bytes=a-` or `bytes=-n` as inclusive
/// offsets, or null for no header, another unit or a range that does not fit.
(int, int)? _parseRange(String? header, int size) {
  final Match? match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header ?? '');
  if (match == null || size == 0) {
    return null;
  }
  final String first = match.group(1)!;
  final String last = match.group(2)!;
  if (first.isEmpty && last.isEmpty) {
    return null;
  }
  final int start = first.isEmpty ? size - int.parse(last) : int.parse(first);
  final int end = first.isEmpty || last.isEmpty
      ? size - 1
      : int.parse(last).clamp(0, size - 1);
  if (start < 0 || start > end || start >= size) {
    return null;
  }
  return (start, end);
}
