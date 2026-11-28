@TestOn('browser')
@Tags(<String>['browser'])
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'server_port.dart';

void main() {
  setUpAll(loadServerPort);

  test('8 (risk: BrowserClient buffers) /chunks delivers one chunk per second, '
      'each before the next is sent', () async {
    final http.Client client = http.Client(); // BrowserClient: fetch
    addTearDown(client.close);
    final http.StreamedResponse response = await client.send(
      http.Request('GET', serverOrigin.resolve('/chunks')),
    );
    expect(response.statusCode, 200);

    final Stopwatch clock = Stopwatch()..start();
    final List<int> numbers = <int>[];
    final List<int> arrivalsMs = <int>[];
    await for (final String text in response.stream.transform(utf8.decoder)) {
      // One chunk is one {"n": i} object; two objects in one chunk mean the browser buffered.
      final Object? json = jsonDecode(text);
      expect(json, isA<Map<String, Object?>>(), reason: 'chunk "$text"');
      numbers.add((json! as Map<String, Object?>)['n']! as int);
      arrivalsMs.add(clock.elapsedMilliseconds);
    }

    expect(numbers, <int>[0, 1, 2, 3, 4]);
    expect(
      arrivalsMs.first,
      lessThan(2500),
      reason: 'the first chunk must not wait for the end of the body',
    );
    for (int i = 1; i < arrivalsMs.length; i++) {
      expect(
        arrivalsMs[i] - arrivalsMs[i - 1],
        greaterThan(600),
        reason: 'chunk $i arrived with chunk ${i - 1}: arrivals $arrivalsMs',
      );
    }
    expect(arrivalsMs.last - arrivalsMs.first, greaterThan(3000));
  }, timeout: const Timeout(Duration(seconds: 30)));
}
