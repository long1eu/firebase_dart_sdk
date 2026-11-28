import 'dart:collection';

import 'package:meta/meta.dart';

/// The type of a [Schema] value.
enum SchemaType {
  /// Text (`STRING`).
  string('STRING'),

  /// A number with a fraction (`NUMBER`).
  number('NUMBER'),

  /// A whole number (`INTEGER`).
  integer('INTEGER'),

  /// True or false (`BOOLEAN`).
  boolean('BOOLEAN'),

  /// A list (`ARRAY`).
  array('ARRAY'),

  /// An object with named properties (`OBJECT`).
  object('OBJECT'),

  /// One of several schemas; no `type` is sent.
  anyOf(null);

  const SchemaType(this._wire);

  final String? _wire;
}

/// The shape of a value: a function's parameters or a structured answer.
///
/// A subset of an OpenAPI 3.0 schema object. Properties of an object are required unless listed in
/// `optionalProperties`.
@immutable
final class Schema {
  Schema._(
    this.type, {
    this.format,
    this.description,
    this.title,
    this.nullable,
    List<String>? enumValues,
    this.items,
    this.minItems,
    this.maxItems,
    this.minimum,
    this.maximum,
    Map<String, Schema>? properties,
    List<String>? optionalProperties,
    List<String>? propertyOrdering,
    List<Schema>? anyOf,
  }) : enumValues = _listOrNull(enumValues),
       properties = properties == null
           ? null
           : UnmodifiableMapView<String, Schema>(
               Map<String, Schema>.of(properties),
             ),
       optionalProperties = _listOrNull(optionalProperties),
       propertyOrdering = _listOrNull(propertyOrdering),
       anyOf = _listOrNull(anyOf);

  /// A text value. [format] is sent as it is.
  Schema.string({
    String? description,
    String? title,
    bool? nullable,
    String? format,
  }) : this._(
         SchemaType.string,
         description: description,
         title: title,
         nullable: nullable,
         format: format,
       );

  /// A text value that is one of [enumValues]; sends format `enum`.
  Schema.enumString({
    required List<String> enumValues,
    String? description,
    String? title,
    bool? nullable,
  }) : this._(
         SchemaType.string,
         enumValues: enumValues,
         description: description,
         title: title,
         nullable: nullable,
         format: 'enum',
       );

  /// A whole number. [format] may be `int32` or `int64`.
  Schema.integer({
    String? description,
    String? title,
    bool? nullable,
    String? format,
    int? minimum,
    int? maximum,
  }) : this._(
         SchemaType.integer,
         description: description,
         title: title,
         nullable: nullable,
         format: format,
         minimum: minimum,
         maximum: maximum,
       );

  /// A number with a fraction. [format] may be `float` or `double`; [minimum] and [maximum] must be
  /// finite when the request is made.
  Schema.number({
    String? description,
    String? title,
    bool? nullable,
    String? format,
    double? minimum,
    double? maximum,
  }) : this._(
         SchemaType.number,
         description: description,
         title: title,
         nullable: nullable,
         format: format,
         minimum: minimum,
         maximum: maximum,
       );

  /// True or false.
  Schema.boolean({String? description, String? title, bool? nullable})
    : this._(
        SchemaType.boolean,
        description: description,
        title: title,
        nullable: nullable,
      );

  /// A list whose elements match [items].
  Schema.array({
    required Schema items,
    String? description,
    String? title,
    bool? nullable,
    int? minItems,
    int? maxItems,
  }) : this._(
         SchemaType.array,
         items: items,
         description: description,
         title: title,
         nullable: nullable,
         minItems: minItems,
         maxItems: maxItems,
       );

  /// An object with [properties]. Every property is required unless named in [optionalProperties].
  Schema.object({
    required Map<String, Schema> properties,
    List<String>? optionalProperties,
    List<String>? propertyOrdering,
    String? description,
    String? title,
    bool? nullable,
  }) : this._(
         SchemaType.object,
         properties: properties,
         optionalProperties: optionalProperties,
         propertyOrdering: propertyOrdering,
         description: description,
         title: title,
         nullable: nullable,
       );

  /// A value that matches at least one of [schemas].
  Schema.anyOf({required List<Schema> schemas})
    : this._(SchemaType.anyOf, anyOf: schemas);

  /// The type of the value.
  final SchemaType type;

  /// The format of a primitive value, for example `int32` or `enum`.
  final String? format;

  /// What the value means; the model reads it.
  final String? description;

  /// A short name of the value.
  final String? title;

  /// Whether the value may be null.
  final bool? nullable;

  /// The allowed values of an enum string.
  final List<String>? enumValues;

  /// The schema of the elements of an array.
  final Schema? items;

  /// The fewest elements of an array.
  final int? minItems;

  /// The most elements of an array.
  final int? maxItems;

  /// The smallest allowed number.
  final num? minimum;

  /// The largest allowed number.
  final num? maximum;

  /// The properties of an object.
  final Map<String, Schema>? properties;

  /// The properties of an object that may be absent.
  final List<String>? optionalProperties;

  /// The order the model should write the properties in.
  final List<String>? propertyOrdering;

  /// The schemas of [SchemaType.anyOf].
  final List<Schema>? anyOf;

  /// The JSON object. `required` lists every key of [properties] not in [optionalProperties].
  Map<String, Object?> toJson() {
    final Map<String, Schema>? properties = this.properties;
    final List<String> optional = optionalProperties ?? const <String>[];
    return <String, Object?>{
      'type': ?type._wire,
      'format': ?format,
      'description': ?description,
      'title': ?title,
      'nullable': ?nullable,
      'enum': ?enumValues,
      'items': ?items?.toJson(),
      'minItems': ?minItems,
      'maxItems': ?maxItems,
      'minimum': ?minimum,
      'maximum': ?maximum,
      if (properties != null) ...<String, Object?>{
        'properties': <String, Object?>{
          for (final MapEntry<String, Schema> entry in properties.entries)
            entry.key: entry.value.toJson(),
        },
        'required': <String>[
          for (final String key in properties.keys)
            if (!optional.contains(key)) key,
        ],
      },
      'propertyOrdering': ?propertyOrdering,
      if (anyOf case final List<Schema> anyOf)
        'anyOf': <Object?>[for (final Schema schema in anyOf) schema.toJson()],
    };
  }
}

/// A JSON Schema written by hand, sent as it is in `responseJsonSchema`.
@immutable
final class JsonSchema {
  /// Wraps [json]. The map is kept as given; do not change it afterwards.
  const JsonSchema(this.json);

  /// The schema as a JSON object.
  final Map<String, Object?> json;
}

List<T>? _listOrNull<T>(List<T>? list) =>
    list == null ? null : UnmodifiableListView<T>(List<T>.of(list));
