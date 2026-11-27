// Ported from the Android SDK, firebase-database/src/test/java/com/google/firebase/database/UtilitiesTest.java
// (firebase-android-sdk 2cfdd0389, Apache-2.0). `Utilities.tryParseInt` is `tryParseIntKey`.
import 'package:firebase_database_dart/src/core/util/numbers.dart';
import 'package:test/test.dart';

void main() {
  test('tryParseInt', () {
    expect(tryParseIntKey('$int32Max'), int32Max);
    expect(tryParseIntKey('$int32Min'), int32Min);
    expect(tryParseIntKey('0'), 0);
    expect(tryParseIntKey('-0'), 0);
    expect(tryParseIntKey('-1'), -1);
    expect(tryParseIntKey('1'), 1);
    expect(tryParseIntKey('a'), isNull);
    expect(tryParseIntKey('-0a'), isNull);
    expect(tryParseIntKey('-'), isNull);
    expect(tryParseIntKey('${int32Max + 1}'), isNull);
    expect(tryParseIntKey('${int32Min - 1}'), isNull);
  });

  test(
    'default cache size is 10 MB',
    () {},
    skip: 'DatabaseConfig is public API, above the data layer',
  );
  test(
    'setting a valid cache size succeeds',
    () {},
    skip: 'DatabaseConfig is public API, above the data layer',
  );
  test(
    'setting a cache size that is too low fails',
    () {},
    skip: 'DatabaseConfig is public API, above the data layer',
  );
  test(
    'setting a cache size that is too high fails',
    () {},
    skip: 'DatabaseConfig is public API, above the data layer',
  );
}
