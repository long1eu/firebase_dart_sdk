// A fixed list of pipeline expressions and a fixed document for them. The
// Enterprise edition emulator's results for them are recorded in
// test/unit/firebase/firestore/pipeline/evaluation/emulator_results.golden.jsonl
// (test/integration_enterprise/pipeline_evaluation_property_test.dart checks
// and rewrites that file); the unit suite replays them against the local
// evaluator, so that it is pinned to the emulator without one.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/pipelines.dart';

import 'property_pipeline.dart';

/// The project the results were recorded with: references in the results
/// name it.
const String evaluationCasesProject = 'demo-test';

/// The file with the recorded results, relative to the package.
const String evaluationCasesGolden =
    'test/unit/firebase/firestore/pipeline/evaluation/emulator_results.golden.jsonl';

/// The path of [evaluationCaseDocument].
const String evaluationCaseDocumentPath = 'pipeline-golden/d';

final Map<String, Object?> evaluationCaseDocument = <String, Object?>{
  'i': 7,
  'neg': -3,
  'z': 0,
  'd': 2.5,
  'nan': double.nan,
  'inf': double.infinity,
  'nzero': -0.0,
  's': 'héllo wörld',
  'e': '',
  't': true,
  'fa': false,
  'n': null,
  'arr': <Object?>[3, 1, 'a', null, 2.0],
  'nums': <Object?>[3, 1, 2],
  'ea': <Object?>[],
  'm': <String, Object?>{'k': 1, 'j': 'x', 'n': null},
  'ts': const Timestamp(1700000000, 123456000),
  'b': Blob(Uint8List.fromList(<int>[1, 2, 65, 255])),
  'g': const GeoPoint(1.5, 2.5),
  'v': FieldValue.vector(<double>[1, 2, 3]),
  'i32': Int32Value(5),
  'd128': Decimal128Value('1.5'),
  'big': 9223372036854775807,
  'min': -9223372036854775807 - 1,
};

FunctionExpression _f(String name, [List<Object?> args = const <Object?>[]]) =>
    FunctionExpression(name, args);

/// Expressions chosen by hand: one or more for every function, with the
/// arguments that matter (types, limits, special numbers).
List<Expression> curatedCases() {
  final Expression i = field('i');
  final Expression d = field('d');
  final Expression s = field('s');
  final Expression b = field('b');
  final Expression n = field('n');
  final Expression x = field('missing');
  final Expression arr = field('arr');
  final Expression nums = field('nums');
  final Expression m = field('m');
  final Expression ts = field('ts');
  final Expression v = field('v');
  final Expression i32 = field('i32');
  final Expression d128 = field('d128');
  final Expression nan = field('nan');
  final Expression inf = field('inf');
  final Expression big = field('big');
  final Expression min = field('min');
  final Expression err = i.add(s);

  final List<Expression> cases = <Expression>[
    // Fields.
    field('m.k'), field('m.zz'), field('i.zz'), field('arr.0'), x, n,
    field('__name__'), field('__name__').documentId(),
    field('__name__').collectionId(), field('__name__').parent(),
    field('__name__').parent().parent(), constant('a/b').documentId(),

    // Number types.
    i32.add(1), i32.add(i32), i32.add(2.5), d128.add(1), d128.add(d128),
    d128.multiply(2.0), d128.add(0.1), d128.subtract(i32), d128.divide(3),
    d128.divide(0), d128.mod(1), i32.divide(2), i32.abs(), d128.abs(),
    i32.divide(constant(Int32Value(0))),
    i32.multiply(constant(Int32Value(2147483647))),
    i32.subtract(constant(Int32Value(-2147483648))),
    i32.equal(5), d128.equal(1.5), i32.lessThan(d128), i32.type(), d128.type(),
    d128.sqrt(), i32.sqrt(), d128.exp(), d128.ln(), d128.pow(2), i.pow(2),
    i32.pow(2), d128.round(), d128.ceil(), d128.floor(), i32.floor(),
    d128.round(1), d128.trunc(), d128.trunc(1),
    constant(Decimal128Value('2.5')).round(),
    constant(Decimal128Value('-2.5')).round(),
    constant(Decimal128Value('1.25')).round(1),
    constant(Decimal128Value('NaN')).add(1),
    constant(Decimal128Value('2')).sqrt(),
    constant(Decimal128Value('-1')).sqrt(),

    // Integer limits.
    big.add(1), big.multiply(2), min.subtract(1), big.multiply(2.0),
    min.divide(-1), min.abs(), min.mod(-1), i.divide(2), i.divide(field('z')),
    d.divide(field('z')), i.mod(field('z')), d.mod(0.0), field('neg').mod(2),
    constant(-7).mod(3), constant(7).mod(-3), constant(7.5).mod(2),
    constant(-7.5).mod(2), inf.mod(2), inf.subtract(inf),

    // Rounding.
    for (final Object value in <Object>[
      2.5, -2.5, 0.5, -0.4, 1234.5678, 1250, 1249, -1250, 5, 15, 99, 0, //
      2.675, 1.005, -0.0,
    ]) ...<Expression>[
      constant(value).round(),
      constant(value).trunc(),
      constant(value).ceil(),
      constant(value).floor(),
      for (final int places in <int>[2, 1, 0, -1, -2, -3]) ...<Expression>[
        constant(value).round(places),
        constant(value).trunc(places),
      ],
    ],
    i.round(2.0), i.round(s), nan.round(), inf.round(), nan.round(1),
    constant(Int32Value(-2147483648)).round(-5),
    constant(Int32Value(2147483647)).round(-1),
    constant(Int32Value(-2147483648)).trunc(-1),
    big.round(-1), big.round(-18), big.round(-19), min.round(-1),
    constant(1.5).round(9223372036854775807),
    constant(1.5).round(-9223372036854775807),

    // Powers, roots and logarithms.
    for (final double value in <double>[
      double.nan, double.infinity, double.negativeInfinity, -0.0, 0, -1, 2, //
      double.maxFinite, double.minPositive,
    ]) ...<Expression>[
      constant(value).ln(),
      _f('log10', <Object?>[value]),
      constant(value).exp(),
      constant(value).sqrt(),
      constant(value).log(2),
      constant(2).log(value),
      constant(value).pow(2),
      constant(2).pow(value),
      constant(value).pow(0.5),
      constant(-2).pow(value),
      constant(value).abs(),
    ],
    constant(8).log(2), constant(8).log(1), constant(100).log(10),
    constant(0).pow(-1), constant(2.0).pow(10000), constant(1).pow(nan),
    nan.pow(0), constant(1000).exp(), constant(16).sqrt(),

    // Comparisons.
    for (final (Object? left, Object? right) in <(Object?, Object?)>[
      (nan, 1), (nan, nan), (n, 1), (n, null), (n, x), (x, x), (x, 1), //
      (s, 1), (i, 7.0), (field('nzero'), 0), (nums, <Object?>[3, 1, 2]),
      (nums, <Object?>[3.0, 1, 2]), (nums, <Object?>[3, 2]),
      (m, <String, Object?>{'k': 1.0, 'j': 'x', 'n': null}),
      (m, <String, Object?>{'z': 1}), (field('t'), false),
      (ts, const Timestamp(1, 0)),
      (v, constant(VectorValue(<double>[1, 2, 3]))),
      (field('g'), constant(const GeoPoint(2, 0))), (i32, d128), (s, 'héllo'),
      (b, constant(Blob(Uint8List.fromList(<int>[1, 3])))),
      (constant(<Object?>[double.nan]), <Object?>[double.nan]),
      (constant(<Object?>[null]), <Object?>[null]),
    ])
      for (final String name in <String>[
        'equal', 'not_equal', 'less_than', 'less_than_or_equal', //
        'greater_than', 'greater_than_or_equal',
      ])
        _f(name, <Object?>[left, right]),
    i.equalAny(<Object?>[7.0, 8]), i.equalAny(<Object?>[null]),
    n.equalAny(<Object?>[null]), x.equalAny(<Object?>[1]), i.equalAny(n),
    i.equalAny(s), i.notEqualAny(<Object?>[1]), i.notEqualAny(<Object?>[null]),
    n.notEqualAny(<Object?>[1]), nan.equalAny(<Object?>[double.nan]),

    // Logic.
    for (final String name in <String>['and', 'or', 'nor', 'xor'])
      for (final List<Object?> args in <List<Object?>>[
        <Object?>[true, n], <Object?>[false, n], <Object?>[false, err], //
        <Object?>[err, false], <Object?>[true, err], <Object?>[err, true],
        <Object?>[true, i], <Object?>[false, i], <Object?>[i, false],
        <Object?>[true, x], <Object?>[false, x], <Object?>[true, true, true],
        <Object?>[false, false], <Object?>[n, n], <Object?>[true, false, n],
      ])
        _f(name, args),
    _f('not', <Object?>[n]), _f('not', <Object?>[i]), _f('not', <Object?>[x]),
    _f('not', <Object?>[true]),
    _f('conditional', <Object?>[n, 1, 2]),
    _f('conditional', <Object?>[i, 1, 2]),
    _f('conditional', <Object?>[true, 1, err]),
    _f('conditional', <Object?>[x, 1, 2]),
    _f('conditional', <Object?>[err, 1, 2]),
    _f('switch_on', <Object?>[false, 1, true, 2, 3]),
    _f('switch_on', <Object?>[false, 1, false, 2]),
    _f('switch_on', <Object?>[n, 1, 2]), _f('switch_on', <Object?>[i, 1, 2]),
    _f('switch_on', <Object?>[err, 1, 2]),

    // Absence, errors and types.
    err.isError(), x.isError(), x.add(s).isError(), n.isAbsent(), x.isAbsent(),
    x.exists(), n.exists(), err.ifError(1), err.ifError(x), err.ifError(err),
    i.divide(0).ifError(x), x.ifAbsent(1), n.ifAbsent(1), err.ifAbsent(1),
    n.ifNull(1), x.ifNull(1), err.ifNull(1), i.ifNull(err),
    _f('coalesce', <Object?>[n, x, 5]), _f('coalesce', <Object?>[err, 1]),
    _f('coalesce', <Object?>[n, x]), _f('coalesce', <Object?>[1, err]),
    for (final Expression value in <Expression>[
      i, d, s, b, n, x, arr, m, ts, v, i32, d128, field('t'), field('g'), //
      field('__name__'), nan,
      constant(BsonObjectId('507f191e810c19729de860ea')),
      constant(BsonTimestamp(1, 2)), constant(RegexValue('a', 'i')),
      constant(MinKey.instance), constant(MaxKey.instance),
    ]) ...<Expression>[
      value.type(),
      value.isType('number'),
      value.isType('null'),
      value.isType('int64'),
      value.length(),
    ],
    array(<Object?>[1, x]), array(<Object?>[1, err]),
    map(<String, Object?>{'a': x, 'b': 1}), map(<String, Object?>{'a': null}),
    _f('map', <Object?>['a', 1, 'a', 2]),

    // Maximum and minimum.
    i.logicalMaximum(<Object?>[d, s]), n.logicalMaximum(<Object?>[x]),
    i.logicalMaximum(<Object?>[nan]), i.logicalMinimum(<Object?>[nan]),
    i.logicalMinimum(<Object?>[n]), i.logicalMaximum(<Object?>[7.0]),
    constant(7.0).logicalMaximum(<Object?>[i]), arr.arrayMaximum(),
    arr.arrayMinimum(), field('ea').arrayMaximum(), i.arrayMaximum(),
    n.arrayMaximum(), arr.arrayMaximumN(2), arr.arrayMinimumN(2),
    arr.arrayMinimumN(99), nums.arrayMaximumN(2), n.arrayMaximumN(1),
    s.arrayMinimumN(1), arr.arrayMinimumN(-1), arr.arrayMinimumN(0),

    // Strings and bytes.
    s.charLength(), b.charLength(), s.byteLength(), b.byteLength(),
    s.toUpper(), s.toLower(), b.toUpper(), i.toLower(),
    constant('straße ǆ ﬁ').toUpper(), constant('İSTANBUL Σ ΌΣΟΣ').toLower(),
    constant('  \t a b \n ').trim(), constant('xxaxbxx').trim('x'),
    constant('xyaxybyx').trim('xy'), constant('  a  ').ltrim(),
    constant('  a  ').rtrim(), constant('xxaxx').ltrim('x'),
    constant('xxaxx').rtrim('x'), constant(' a ').trim(''), b.trim(),
    constant(Blob(Uint8List.fromList(<int>[32, 9, 65, 32, 10]))).trim(),
    i.trim(), s.trim(1),
    s.reverse(), arr.reverse(), b.reverse(), i.reverse(), arr.stringReverse(),
    constant('a😀b').stringReverse(), b.stringReverse(),
    for (final List<Object?> args in <List<Object?>>[
      <Object?>[1, 3], <Object?>[-3], <Object?>[100], <Object?>[1, -1], //
      <Object?>[1, 0], <Object?>[-100, 3], <Object?>[0], <Object?>[n],
      <Object?>[1.0], <Object?>[1, n], <Object?>[5, 100], <Object?>[-1, 5],
    ]) ...<Expression>[
      _f('substring', <Object?>[s, ...args]),
      _f('substring', <Object?>[b, ...args]),
      _f('array_slice', <Object?>[arr, ...args]),
    ],
    n.substring(1), i.substring(1), s.arraySlice(1),
    s.concat(<Object?>['!', '?']), s.concat(<Object?>[1]),
    arr.concat(<Object?>[
      <Object?>[9],
    ]),
    arr.concat(<Object?>['x']),
    s.concat(<Object?>[null]), b.concat(<Object?>[b]), s.concat(<Object?>[b]),
    s.stringConcat(<Object?>['!']), s.stringConcat(<Object?>[1]),
    s.stringConcat(<Object?>[null]),
    s.startsWith('hé'), s.startsWith(1), s.startsWith(n), s.startsWith(''),
    s.endsWith('ld'), s.endsWith(''), s.stringContains('lo w'),
    s.stringContains(''), s.stringContains('zz'), b.startsWith(b),
    s.like('h%w_rld'), constant('50%').like(r'50\%'), constant('a').like('a\\'),
    s.like('H%'), constant('a\nb').like('a%b'), constant('a\nb').like('a_b'),
    constant('a.c').like('a.c'), constant('abc').like('a.c'), s.like('%'),
    constant('').like(''), constant('a_c').like(r'a\_c'),
    constant('abc').like(r'a\_c'),
    for (final (String value, String pattern) in <(String, String)>[
      ('héllo wörld', 'l+o'),
      ('héllo wörld', 'h.*d'),
      ('héllo wörld', 'llo'), //
      ('héllo wörld', '('), ('héllo wörld', 'h(.)l'), ('héllo wörld', '(h)(.)'),
      ('héllo wörld', 'z'),
      ('héllo wörld', ''),
      ('yummy Good food', '(?i)good'),
      ('yummy Good food', 'yummy (?i)good'), ('a\nb', 'a.b'),
      ('a\nb', '(?s)a.b'), ('a\nb', '(?m)^b'), ('a\nb', '^b'),
      ('abcabc', r'(abc)\1'), ('abc', 'a(?=b)'), ('abc', '(?P<x>b)'),
      ('abc', '(?:a)(b)'), ('aé1', r'\pL'), ('aé1', r'\p{L}+'),
      ('a1', '[[:digit:]]'),
      ('a.b', r'\Qa.b\E'),
      ('ab', r'b\z'),
      ('aaa', 'a++'),
      ('aaa', 'a+?'), ('aaa', 'a{2}'), ('aaa', 'a{2,}'), ('é', r'\w'),
      ('٣', r'\d'), ('a b', r'a\sb'), ('a-b', r'a\-b'), ('a_b', r'a\_b'),
      ('a]b', '[]]'), ('a^b', r'[\^]'), ('ab', 'a|b'), ('ab', '[^a]'),
      ('A', '(?i)a'), ('tab\there', r'\t'), ('x', r'\x78'), ('ab', r'\bab\b'),
      // The choices of the linear-time matcher (re2.dart).
      ('a]b', ']'), ('aaa', 'a{1001}'), ('aaa', 'a{1000}'),
      ('a\vb', r'a\sb'), ('a\u00a0b', r'a\sb'), ('a\u2028b', r'a\sb'),
      ('a\rb', '(?m)^b'), ('a\u2028b', '(?m)^b'), ('a\rb', r'(?m)a$'),
      ('\u212a', '(?i)k'), ('K', '(?i)\u212a'), ('ſ', '(?i)s'),
      ('abab', '(a|b)+'), ('b', '(a*)*'), ('aaaa', 'a{2,3}?'),
      ('ab', 'a|ab'), ('aab', 'a*?b'), ('ÀBc', '(?i)[a-z]+'),
      ('a😀😀', '😀+'), ('a😃', r'[\x{1F600}-\x{1F64F}]'),
      ('aÉé', r'\p{Lu}\p{Ll}'), ('aaa', '(a+)+'), ('a{b', 'a{b'),
      ('ab', '^*a'), ('a\u0085b', 'a.b'),
    ]) ...<Expression>[
      constant(value).regexContains(pattern),
      constant(value).regexMatch(pattern),
      constant(value).regexFind(pattern),
      constant(value).regexFindAll(pattern),
    ],
    constant('a,b,,c').split(','), constant('abc').split(''),
    constant('abc').split('x'), constant('').split(','), b.split(b),
    s.split(n), s.split(1), constant('aXbXc').split('X'),
    constant(<Object?>['a', 'b', null, 'c']).join('-'), nums.join(','),
    arr.join(n), field('ea').join(','), n.join(','), x.join(','),
    constant(<Object?>[null]).join(','), s.join(','),
    s.stringReplaceAll('l', 'L'), s.stringReplaceAll('', '-'),
    s.stringReplaceOne('l', 'L'), s.stringReplaceAll('l', n),
    s.stringReplaceAll('zz', 'y'), constant('aaa').stringReplaceAll('aa', 'b'),
    s.stringReplaceAll('l', 1), b.stringReplaceAll(b, b),
    constant('ab').stringRepeat(3), constant('ab').stringRepeat(0),
    constant('ab').stringRepeat(-1), b.stringRepeat(2),
    constant('ab').stringRepeat(2.0), constant('ab').stringRepeat(n),
    s.stringIndexOf('lo'), s.stringIndexOf('zz'), s.stringIndexOf(''),
    s.stringIndexOf('w'), b.stringIndexOf(b), s.stringIndexOf(1),

    // Arrays.
    arr.arrayLength(), s.arrayLength(), n.arrayLength(),
    arr.arrayContains(1.0), arr.arrayContains(null), arr.arrayContains(x),
    s.arrayContains(1), n.arrayContains(1), arr.arrayContains(nan),
    arr.arrayContainsAny(<Object?>[9, 'a']),
    arr.arrayContainsAny(<Object?>[null]), arr.arrayContainsAny(<Object?>[]),
    arr.arrayContainsAll(<Object?>[1, 3]),
    arr.arrayContainsAll(<Object?>[1, null]),
    arr.arrayContainsAll(<Object?>[]), arr.arrayContainsAll(<Object?>[1, 9]),
    arr.arrayContainsAny(n), n.arrayContainsAll(<Object?>[1]),
    for (final Object? index in <Object?>[0, -1, 4, 5, -5, -6, 99, 'a', 1.0, n])
      arr.arrayGet(index as Object),
    s.arrayGet(0), n.arrayGet(0), m.arrayGet(0),
    arr.arrayFirst(), field('ea').arrayFirst(), arr.arrayLast(),
    field('ea').arrayLast(), s.arrayFirst(), x.arrayFirst(), n.arrayLast(),
    arr.arrayFirstN(2), arr.arrayFirstN(99), arr.arrayFirstN(-1),
    arr.arrayFirstN(0), arr.arrayLastN(2), n.arrayFirstN(1), arr.arrayFirstN(n),
    arr.arrayLastN(99), arr.arrayIndexOf(1), arr.arrayIndexOf(null),
    arr.arrayIndexOf(99), arr.arrayIndexOf(x), arr.arrayIndexOf(2),
    constant(<Object?>[1, 2, 1]).arrayLastIndexOf(1),
    constant(<Object?>[1, 2, 1.0]).arrayIndexOfAll(1), n.arrayIndexOf(1),
    s.arrayIndexOf(1), arr.arrayIndexOfAll(99), arr.arrayIndexOfAll(x),
    arr.arrayConcat(<Object?>[
      <Object?>[1],
    ]),
    arr.arrayConcat(<Object?>[n]),
    arr.arrayConcat(<Object?>['s']), arr.arrayReverse(), s.arrayReverse(),
    nums.arrayFilter((Expression e) => e.greaterThan(1)),
    arr.arrayFilter((Expression e) => e.greaterThan(1)),
    arr.arrayFilter((Expression e) => e.add(1).greaterThan(1)),
    arr.arrayFilter((Expression e) => e.isType('number')),
    n.arrayFilter((Expression e) => e.greaterThan(1)),
    s.arrayFilter((Expression e) => e.greaterThan(1)),
    nums.arrayFilter((Expression e) => e.greaterThan(i)),
    nums.arrayTransform((Expression e) => e.multiply(2)),
    nums.arrayTransformWithIndex(
      (Expression e, Expression index) => e.add(index),
    ),
    arr.arrayTransform((Expression e) => e.add(1)),
    arr.arrayTransform((Expression e) => e.type()),
    arr.arrayTransform((Expression e) => x),
    n.arrayTransform((Expression e) => e),

    // Maps.
    m.mapGet('k'), m.mapGet('zz'), s.mapGet('k'), n.mapGet('k'), m.mapGet('n'),
    v.mapGet('value'), x.mapGet('k'), _f('map_get', <Object?>[m, null]),
    _f('map_get', <Object?>[m, x]), _f('map_get', <Object?>[m, 7]),
    _f('map_get', <Object?>[m, field('e')]),
    m.getField('k'), s.getField('k'), n.getField('k'), x.getField('k'),
    m.getField('zz'), m.mapKeys(), m.mapValues(), m.mapEntries(), s.mapKeys(),
    n.mapKeys(), constant(<String, Object?>{}).mapKeys(),
    m.mapMerge(<String, Object?>{'k': 2, 'z': 3}).mapGet('k'),
    m.mapMerge(<String, Object?>{'k': 2, 'z': 3}).length(), m.mapMerge(n),
    m.mapMerge(s), m.mapRemove('k').length(), m.mapRemove('zz').length(),
    s.mapRemove('k'), n.mapRemove('k'), m.mapSet('k', 9).mapGet('k'),
    m.mapSet('q', 9).length(), m.mapSet('k', x).length(),
    m.mapSet('q', null).mapGet('q'), n.mapSet('k', 1), s.mapSet('k', 1),
    // Several pairs: later pairs see the earlier ones.
    m.mapSet('a', 1, <Object?>['b', 2]), m.mapSet('a', 1, <Object?>['a', 2]),
    m.mapSet('k', x, <Object?>['q', 1]), m.mapSet('q', 1, <Object?>['q', x]),
    m.mapSet('a', 1, <Object?>[null, 2]),
    m.mapSet(constant(null), 1, <Object?>['b', 2]),
    m.mapSet('a', 1, <Object?>[7, 2]), m.mapSet('a', 1, <Object?>['b', err]),
    m.mapSet('a', err, <Object?>[null, 2]), n.mapSet('a', 1, <Object?>['b', 2]),
    m.mapSet('a', 1, <Object?>['b', 2, 'c', 3]),
    _f('map_set', <Object?>[m, 'a', 1, 'b']), _f('map_set', <Object?>[m, 'a']),
    _f('map_set', <Object?>[m]),

    // Sum of an array.
    nums.arraySum(), arr.arraySum(), field('ea').arraySum(), n.arraySum(),
    x.arraySum(), i.arraySum(), s.arraySum(), m.arraySum(), v.arraySum(),
    constant(<Object?>[1, 2.5]).arraySum(),
    constant(<Object?>[1.5, 2.5]).arraySum(),
    constant(<Object?>[1, null, 2]).arraySum(),
    constant(<Object?>[1, 'a']).arraySum(),
    constant(<Object?>[true]).arraySum(),
    constant(<Object?>[
      <Object?>[1, 2],
    ]).arraySum(),
    constant(<Object?>[null]).arraySum(),
    constant(<Object?>[null, null]).arraySum(),
    constant(<Object?>[1, double.nan]).arraySum(),
    constant(<Object?>[double.infinity, double.negativeInfinity]).arraySum(),
    constant(<Object?>[9223372036854775807, 1]).arraySum(),
    constant(<Object?>[-9223372036854775807 - 1, -1]).arraySum(),
    constant(<Object?>[9223372036854775807, 1.0]).arraySum(),
    constant(<Object?>[9223372036854775807, 1, -2]).arraySum(),
    constant(<Object?>[Int32Value(2147483647), Int32Value(1)]).arraySum(),
    constant(<Object?>[Int32Value(2), 3]).arraySum(),
    constant(<Object?>[Int32Value(2), Int32Value(3)]).arraySum(),
    constant(<Object?>[Decimal128Value('1.5'), 1]).arraySum(),
    constant(<Object?>[Decimal128Value('1.5'), 2.5]).arraySum(),
    constant(<Object?>[-0.0]).arraySum(),
    constant(<Object?>[-0.0, -0.0]).arraySum(),
    constant(<Object?>[0.1, 0.2, 0.3]).arraySum(),
    array(<Object?>[i, err]).arraySum(), _f('sum', <Object?>[nums, nums]),
    _f('sum', <Object?>[]),

    // Search functions (the emulator has none).
    documentMatches('waffles'), score(),

    // Timestamps.
    for (final String unit in <String>[
      'microsecond', 'millisecond', 'second', 'minute', 'hour', 'day', //
    ]) ...<Expression>[
      ts.timestampAdd(unit, 1),
      ts.timestampAdd(unit, -1500),
      ts.timestampSubtract(unit, 90),
      ts.timestampAdd(unit, 100000).timestampDiff(ts, unit),
      ts.timestampDiff(ts.timestampAdd('second', 90061), unit),
    ],
    ts.timestampAdd('second', 1.5), ts.timestampAdd('second', n),
    s.timestampAdd('second', 1), n.timestampAdd('second', 1),
    ts.timestampAdd('second', i32), ts.timestampAdd('second', big),
    ts.timestampSubtract('day', 800000),
    for (final String unit in <String>[
      'microsecond', 'millisecond', 'second', 'minute', 'hour', 'day', //
      'week', 'isoweek', 'month', 'quarter', 'year', 'isoyear',
    ])
      for (final Timestamp value in const <Timestamp>[
        Timestamp(1700000000, 123456000), Timestamp(-1, 999999000), //
        Timestamp(1704067199, 999999000), Timestamp(1609459200, 0),
        Timestamp(-62135596800, 0), Timestamp(951782400, 0),
      ])
        constant(value).timestampTruncate(unit),
    for (final String part in <String>[
      'microsecond', 'millisecond', 'second', 'minute', 'hour', 'day', //
      'dayofweek', 'dayofyear', 'week', 'isoweek', 'month', 'quarter', 'year',
      'isoyear',
    ])
      for (final Timestamp value in const <Timestamp>[
        Timestamp(1700000000, 123456000), Timestamp(-1, 999999000), //
        Timestamp(1704067199, 999999000), Timestamp(1609459200, 0),
        Timestamp(-62135596800, 0), Timestamp(951782400, 0),
        Timestamp(1483228800, 0), Timestamp(253402300799, 0),
      ])
        constant(value).timestampExtract(part),
    ts.timestampTruncate('day', 'UTC'), ts.timestampExtract('hour', 'UTC'),
    n.timestampTruncate('day'), s.timestampExtract('day'),
    ts.timestampToUnixMicros(), ts.timestampToUnixMillis(),
    ts.timestampToUnixSeconds(), s.timestampToUnixSeconds(),
    constant(const Timestamp(-2, 999999000)).timestampToUnixMillis(),
    constant(const Timestamp(-2, 999999000)).timestampToUnixMicros(),
    constant(const Timestamp(-2, 999999000)).timestampToUnixSeconds(),
    constant(-1).unixMicrosToTimestamp(),
    constant(1500).unixMillisToTimestamp(),
    constant(-1500).unixMillisToTimestamp(),
    constant(1).unixSecondsToTimestamp(),
    big.unixSecondsToTimestamp(), constant(1.5).unixSecondsToTimestamp(),
    i32.unixSecondsToTimestamp(),
    constant(253402300799).unixSecondsToTimestamp(),
    constant(253402300800).unixSecondsToTimestamp(),
    constant(-62135596800).unixSecondsToTimestamp(),
    constant(-62135596801).unixSecondsToTimestamp(),

    // Vectors.
    v.cosineDistance(<double>[1, 2, 3]), v.cosineDistance(<double>[0, 0, 0]),
    v.cosineDistance(<double>[1, 2]), v.cosineDistance(<double>[-1, -2, -3]),
    v.cosineDistance(<double>[3, -2, 1]), v.dotProduct(<double>[1, 0, 2]),
    v.dotProduct(<double>[1, 2]), v.euclideanDistance(<double>[1, 2, 5]),
    v.euclideanDistance(<double>[1, 2]), nums.cosineDistance(<double>[1, 2, 3]),
    n.cosineDistance(<double>[1, 2, 3]), v.vectorLength(), arr.vectorLength(),
    n.vectorLength(),
  ];
  return cases;
}

/// All the recorded cases: [curatedCases] and the [edgeMatrix] of every
/// function.
List<Expression> evaluationCases() => <Expression>[
  ...curatedCases(),
  ...edgeMatrix(),
];
