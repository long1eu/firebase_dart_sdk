// Recipe: read and write a Dart class instead of maps, with `withConverter`.
// The converter is attached to a reference or a query; everything read through
// it is typed.
//
// Run from cloud_firestore/cloud_firestore_dart against the emulator:
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/cookbook/typed_model.dart

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import '../common.dart';

class Product {
  const Product({
    required this.name,
    required this.price,
    this.tags = const [],
  });

  factory Product.fromMap(Map<String, Object?> data) {
    return Product(
      name: data['name']! as String,
      // Numbers written by other clients may come back as int or double.
      price: (data['price']! as num).toDouble(),
      tags: <String>[
        ...(data['tags'] as List<Object?>? ?? <Object?>[]).cast<String>(),
      ],
    );
  }

  final String name;
  final double price;
  final List<String> tags;

  Map<String, Object?> toMap() => <String, Object?>{
    'name': name,
    'price': price,
    'tags': tags,
  };
}

Future<void> main() async {
  final Firestore firestore = connect();
  final CollectionReference<Product> products = firestore
      .collection(scratch('products'))
      .withConverter<Product>(
        FirestoreDataConverter<Product>.from(
          fromFirestore:
              (
                DocumentSnapshot<Map<String, Object?>> snapshot,
                SnapshotOptions? options,
              ) => Product.fromMap(snapshot.data!),
          toFirestore: (Product product, SetOptions? options) =>
              product.toMap(),
        ),
      );

  await products.doc('pen').set(const Product(name: 'Pen', price: 1.5));
  await products.add(const Product(name: 'Desk', price: 120, tags: ['office']));

  // Reads are typed.
  final Product pen = (await products.doc('pen').get()).data!;
  print('pen costs ${pen.price}');
  final QuerySnapshot<Product> expensive = await products
      .where('price', isGreaterThan: 10)
      .get();
  print('expensive: ${<String>[for (final d in expensive) d.data.name]}');

  // update takes field maps, not the class.
  await products.doc('pen').update(<String, Object?>{'price': 2});
  print('pen now costs ${(await products.doc('pen').get()).data!.price}');

  await firestore.terminate();
}
