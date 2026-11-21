import 'dart:async';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import 'bootstrap.dart';
import 'sample_image.dart';

/// Uploads generated images to a folder of the bucket, with progress and
/// pause, resume and cancel, lists the folder and shows each image by its
/// download URL.
class ImagesPage extends StatefulWidget {
  const ImagesPage({super.key});

  @override
  State<ImagesPage> createState() => _ImagesPageState();
}

class _ImagesPageState extends State<ImagesPage> {
  final Reference _folder = FirebaseStorage.instance.ref(AppConfig.folder);
  late Future<ListResult> _listing = _folder.listAll();
  UploadTask? _task;
  TaskSnapshot? _snapshot;
  String _status = 'Ready';

  Future<void> _upload() async {
    final data = await sampleImage();
    final Reference target = _folder.child(
      'sample-${DateTime.now().microsecondsSinceEpoch}.png',
    );
    final UploadTask task = target.putData(
      data,
      SettableMetadata(contentType: 'image/png'),
    );
    final StreamSubscription<TaskSnapshot> events = task.snapshotEvents.listen((
      TaskSnapshot snapshot,
    ) {
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
        _status = 'Upload ${snapshot.state.name}';
      });
    });
    setState(() => _task = task);
    try {
      await task;
      _status = 'Uploaded ${target.name}';
    } on FirebaseException catch (error) {
      _status = 'Upload stopped: ${error.code}';
    } finally {
      await events.cancel();
      if (mounted) {
        setState(() {
          _task = null;
          _snapshot = null;
          _listing = _folder.listAll();
        });
      }
    }
  }

  Future<void> _delete(Reference image) async {
    await image.delete();
    setState(() {
      _status = 'Deleted ${image.name}';
      _listing = _folder.listAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final UploadTask? task = _task;
    final TaskSnapshot? snapshot = _snapshot;
    final double? fraction = snapshot == null || snapshot.totalBytes == 0
        ? null
        : snapshot.bytesTransferred / snapshot.totalBytes;
    return Scaffold(
      appBar: AppBar(title: const Text('Storage on Linux')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 8,
              children: <Widget>[
                FilledButton(
                  key: const ValueKey<String>('uploadButton'),
                  onPressed: task == null ? _upload : null,
                  child: const Text('Upload a sample image'),
                ),
                OutlinedButton(
                  key: const ValueKey<String>('pauseButton'),
                  onPressed: task?.pause,
                  child: const Text('Pause'),
                ),
                OutlinedButton(
                  key: const ValueKey<String>('resumeButton'),
                  onPressed: task?.resume,
                  child: const Text('Resume'),
                ),
                OutlinedButton(
                  key: const ValueKey<String>('cancelButton'),
                  onPressed: task?.cancel,
                  child: const Text('Cancel'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (task != null) LinearProgressIndicator(value: fraction),
            Text(_status, key: const ValueKey<String>('status')),
            const Divider(),
            Expanded(
              child: FutureBuilder<ListResult>(
                future: _listing,
                builder:
                    (BuildContext context, AsyncSnapshot<ListResult> result) {
                      final ListResult? list = result.data;
                      if (result.hasError) {
                        return Text('List failed: ${result.error}');
                      }
                      if (list == null) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (list.items.isEmpty) {
                        return const Text('No images yet');
                      }
                      return ListView(
                        children: <Widget>[
                          for (final Reference item in list.items)
                            _ImageTile(
                              key: ValueKey<String>('image-${item.name}'),
                              reference: item,
                              onDelete: () => _delete(item),
                            ),
                        ],
                      );
                    },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({
    required this.reference,
    required this.onDelete,
    super.key,
  });

  final Reference reference;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: SizedBox.square(
        dimension: 64,
        child: FutureBuilder<String>(
          future: reference.getDownloadURL(),
          builder: (BuildContext context, AsyncSnapshot<String> url) {
            final String? address = url.data;
            return address == null
                ? const Icon(Icons.image_outlined)
                : Image.network(address, fit: BoxFit.cover);
          },
        ),
      ),
      title: Text(reference.name),
      subtitle: FutureBuilder<FullMetadata>(
        future: reference.getMetadata(),
        builder: (BuildContext context, AsyncSnapshot<FullMetadata> metadata) {
          final FullMetadata? data = metadata.data;
          return Text(data == null ? '...' : '${data.size} bytes');
        },
      ),
      trailing: IconButton(
        key: ValueKey<String>('delete-${reference.name}'),
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Delete',
        onPressed: onDelete,
      ),
    );
  }
}
