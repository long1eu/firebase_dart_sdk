import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:connectivity_linux/connectivity_linux.dart';

void main() {
  const MethodChannel channel = MethodChannel('connectivity_linux');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  test('getPlatformVersion', () async {
    expect(await ConnectivityLinux.platformVersion, '42');
  });
}
