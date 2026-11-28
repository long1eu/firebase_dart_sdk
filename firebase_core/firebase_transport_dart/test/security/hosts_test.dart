// Shared specification v3, 5.8, with the lead's readings 7 to 10, 16 and 19: rule L (loopback),
// rule E (emulator host), rule T (tokens), rule O (origin), the token origin and the host label.
import 'package:firebase_transport_dart/firebase_transport_dart.dart';
import 'package:test/test.dart';

const String _expectedHostAndPort = 'emulator host: expected host:port';
const String _portOutOfRange = 'emulator host: the port must be 1 to 65535';
const String _notIpv6 = 'emulator host: not an IPv6 address';
const String _productionHost =
    'emulator host: a production host is not an emulator';

const List<String> _refusedSuffixes = <String>[
  'googleapis.com',
  'google.com',
  'cloudfunctions.net',
  'run.app',
  'firebaseio.com',
  'firebasedatabase.app',
  'firebaseapp.com',
  'web.app',
  'appspot.com',
  'firebasestorage.app',
];

/// Matches the [ArgumentError] of rule E whose message is exactly [message].
Matcher _refusedWith(String message) => throwsA(
  isA<ArgumentError>().having(
    (ArgumentError e) => e.message,
    'message',
    message,
  ),
);

/// The text of the [ArgumentError] that [call] throws.
String _errorTextOf(void Function() call) {
  try {
    call();
  } on ArgumentError catch (error) {
    return '$error | ${error.message} | ${error.invalidValue} | ${error.name}';
  }
  fail('expected an ArgumentError');
}

void main() {
  _loopbackTests();
  _emulatorHostTests();
  _emulatorHostValueTests();
  _mayCarryTokensTests();
  _originTests();
  _hostLabelTests();
}

void _loopbackTests() {
  test('loopback table', () {
    const List<String> loopback = <String>[
      'localhost',
      'LOCALHOST',
      '127.0.0.1',
      '127.255.255.255',
      '[::1]',
      '::1',
      '0:0:0:0:0:0:0:1',
    ];
    for (final String host in loopback) {
      expect(isLoopbackHost(host), isTrue, reason: host);
    }
    const List<String> other = <String>[
      '127.999.1.1',
      '127.1',
      'a.localhost',
      'localhost.',
      '0.0.0.0',
      '::ffff:127.0.0.1',
      '::1%eth0',
      '',
      '128.0.0.1',
    ];
    for (final String host in other) {
      expect(isLoopbackHost(host), isFalse, reason: '"$host"');
    }
  });

  test('other spellings of the loopback addresses', () {
    const List<String> loopback = <String>[
      'LocalHost',
      '127.0.0.0',
      '127.1.2.3',
      '[0:0:0:0:0:0:0:1]',
      '0000:0000:0000:0000:0000:0000:0000:0001',
      '::0001',
      '[::1]',
    ];
    for (final String host in loopback) {
      expect(isLoopbackHost(host), isTrue, reason: host);
    }
    const List<String> other = <String>[
      '127.0.0.256',
      '127.0.0',
      '127.0.0.1.',
      '127.0.0.1.1',
      '1127.0.0.1',
      '127.0.0.-1',
      '127.0.0.1e0',
      '0x7f.0.0.1',
      '2130706433',
      'localhost.localdomain',
      'notlocalhost',
      '::',
      '::2',
      '1::1',
      '::127.0.0.1',
      '::ffff:7f00:1',
      '[::1',
      '::1]',
      '[[::1]]',
      'localhost:8080',
      '127.0.0.1:8080',
      ' localhost',
      'localhost ',
      'localhost\n',
    ];
    for (final String host in other) {
      expect(isLoopbackHost(host), isFalse, reason: '"$host"');
    }
  });

  test(
    'reading 9: a zone is refused before parsing; [localhost] is loopback',
    () {
      expect(isLoopbackHost('::1%eth0'), isFalse);
      expect(isLoopbackHost('[::1%eth0]'), isFalse);
      expect(isLoopbackHost('::1%25eth0'), isFalse);
      expect(isLoopbackHost('::1%'), isFalse);
      expect(isLoopbackHost('[localhost]'), isTrue);
      expect(isLoopbackHost('[LOCALHOST]'), isTrue);
    },
  );

  test('reading 19: an IPv4 part with a leading zero is not loopback', () {
    for (final String host in <String>[
      '127.0.0.09',
      '127.00.0.1',
      '127.0.0.01',
      '0127.0.0.1',
      '127.0.0.001',
      '127.000.000.001',
    ]) {
      expect(isLoopbackHost(host), isFalse, reason: host);
    }
    expect(isLoopbackHost('127.0.0.0'), isTrue);
    expect(isLoopbackHost('127.10.100.255'), isTrue);
  });

  test('isLoopbackHost never throws', () {
    final List<String> odd = <String>[
      '[',
      ']',
      '[]',
      '][',
      ':',
      ':::',
      '%',
      '...',
      '127.',
      '.127.0.0.1',
      '\u0000',
      'é',
      '[::1]:80',
      '1:2:3:4:5:6:7:8:9',
      'g::1',
      '9' * 400,
      '${'1:' * 400}1',
      '${'127.' * 400}1',
    ];
    for (final String host in odd) {
      expect(isLoopbackHost(host), isFalse, reason: '"$host"');
    }
  });
}

void _emulatorHostTests() {
  test('emulator host table', () {
    final EmulatorHost local = EmulatorHost.parse('localhost:8080');
    expect(local.host, 'localhost');
    expect(local.port, 8080);
    expect(local.isLoopback, isTrue);
    final EmulatorHost android = EmulatorHost.parse('10.0.2.2:9099');
    expect(android.host, '10.0.2.2');
    expect(android.port, 9099);
    expect(android.isLoopback, isFalse);
    final EmulatorHost ipv6 = EmulatorHost.parse('[::1]:9000');
    expect(ipv6.host, '::1');
    expect(ipv6.port, 9000);
    expect(ipv6.isLoopback, isTrue);
    expect(EmulatorHost.parse('host.internal:1').port, 1);
    expect(EmulatorHost.parse('host.internal:65535').port, 65535);
    expect(EmulatorHost.parse('host.internal:00080').port, 80);

    const Map<String, String> refused = <String, String>{
      'localhost': _expectedHostAndPort,
      'localhost:': _expectedHostAndPort,
      ':8080': _expectedHostAndPort,
      '': _expectedHostAndPort,
      '[::1]': _expectedHostAndPort,
      '::1:9000': _expectedHostAndPort,
      'localhost:0': _portOutOfRange,
      'localhost:65536': _portOutOfRange,
      'localhost:99999': _portOutOfRange,
      'localhost:123456': _expectedHostAndPort,
      'localhost:+80': _expectedHostAndPort,
      'localhost:-80': _expectedHostAndPort,
      'localhost:0x50': _expectedHostAndPort,
      'localhost:8e1': _expectedHostAndPort,
      'localhost:80.0': _expectedHostAndPort,
      'http://localhost:8080': _expectedHostAndPort,
      '//localhost:8080': _expectedHostAndPort,
      'localhost:8080/': _expectedHostAndPort,
      'localhost:8080/path': _expectedHostAndPort,
      'localhost/path:8080': _expectedHostAndPort,
      'user@localhost:8080': _expectedHostAndPort,
      'user:secret@10.0.0.5:9099': _expectedHostAndPort,
      'local%68ost:8080': _expectedHostAndPort,
      '[::1%eth0]:9000': _expectedHostAndPort,
      ' localhost:8080': _expectedHostAndPort,
      'localhost:8080 ': _expectedHostAndPort,
      'local host:8080': _expectedHostAndPort,
      'localhost :8080': _expectedHostAndPort,
      'localhost: 8080': _expectedHostAndPort,
      'localhost:8080\n': _expectedHostAndPort,
      '\tlocalhost:8080': _expectedHostAndPort,
      'localhost:8080?x=1': _expectedHostAndPort,
      'localhost:8080#f': _expectedHostAndPort,
      'local_host:8080': _expectedHostAndPort,
    };
    refused.forEach((String input, String message) {
      expect(
        () => EmulatorHost.parse(input),
        _refusedWith(message),
        reason: '"$input"',
      );
    });
  });

  test('each refused suffix and a subdomain of each', () {
    for (final String suffix in _refusedSuffixes) {
      final List<String> hosts = <String>[
        suffix,
        'sub.$suffix',
        'a.b.$suffix',
        suffix.toUpperCase(),
        'Sub.${suffix.toUpperCase()}',
        '$suffix.',
        'sub.$suffix..',
      ];
      for (final String host in hosts) {
        expect(
          () => EmulatorHost.parse('$host:443'),
          _refusedWith(_productionHost),
          reason: host,
        );
        expect(
          () => EmulatorHost(host, 443),
          _refusedWith(_productionHost),
          reason: host,
        );
      }
      // Only the name itself and its subdomains: a longer name is another host.
      expect(EmulatorHost.parse('not$suffix:443').host, 'not$suffix');
      expect(EmulatorHost.parse('$suffix.test:443').host, '$suffix.test');
    }
  });

  test('error text never repeats the input', () {
    const String input = 'user:secret@10.0.0.5:9099';
    final String text = _errorTextOf(() => EmulatorHost.parse(input));
    for (final String part in <String>['user', 'secret', '10.0.0.5', '9099']) {
      expect(text, isNot(contains(part)), reason: part);
    }
    expect(text, contains(_expectedHostAndPort));

    const Map<String, List<String>> inputs = <String, List<String>>{
      'zzqqxx-host.test:0': <String>['zzqqxx'],
      'zzqqxx-host.test:70000': <String>['zzqqxx', '70000'],
      '[zzqqxx]:9099': <String>['zzqqxx', '9099'],
      '[12345::1]:9099': <String>['12345', '9099'],
      'zzqqxx.googleapis.com:8443': <String>['zzqqxx', 'googleapis', '8443'],
      'zzqqxx..test:8443': <String>['zzqqxx', '8443'],
      'https://zzqqxx.test:8443/path?key=zzqqxx': <String>['zzqqxx', '8443'],
    };
    inputs.forEach((String input, List<String> parts) {
      final String text = _errorTextOf(() => EmulatorHost.parse(input));
      for (final String part in parts) {
        expect(text, isNot(contains(part)), reason: '"$input"');
      }
    });
    final String fromParts = _errorTextOf(
      () => EmulatorHost('user:secret@zzqqxx', 9099),
    );
    expect(fromParts, isNot(contains('secret')));
    expect(fromParts, isNot(contains('zzqqxx')));
  });

  test('emulator hosts host., .host and a..b are refused', () {
    for (final String host in <String>['host.', '.host', 'a..b', '.', '..']) {
      expect(
        () => EmulatorHost.parse('$host:8080'),
        _refusedWith(_expectedHostAndPort),
        reason: host,
      );
      expect(
        () => EmulatorHost(host, 8080),
        _refusedWith(_expectedHostAndPort),
        reason: host,
      );
    }
  });

  test('each of the four messages', () {
    expect(
      () => EmulatorHost.parse('localhost'),
      _refusedWith('emulator host: expected host:port'),
    );
    expect(
      () => EmulatorHost.parse('localhost:0'),
      _refusedWith('emulator host: the port must be 1 to 65535'),
    );
    expect(
      () => EmulatorHost.parse('[:::]:9000'),
      _refusedWith('emulator host: not an IPv6 address'),
    );
    expect(
      () => EmulatorHost.parse('firestore.googleapis.com:443'),
      _refusedWith('emulator host: a production host is not an emulator'),
    );
  });

  test('reading 7: the message is that of the first rule that fails', () {
    // Pattern, then port range, then IPv6, then production suffix, then dot shape.
    const Map<String, String> inputs = <String, String>{
      'user@googleapis.com:0': _expectedHostAndPort,
      'googleapis.com:0': _portOutOfRange,
      '[:::]:0': _portOutOfRange,
      '.host:70000': _portOutOfRange,
      '[:::]:9000': _notIpv6,
      '[1.2.3.4]:9000': _notIpv6,
      '[12345::1]:9000': _notIpv6,
      '[1::2::3]:9000': _notIpv6,
      'googleapis.com.:443': _productionHost,
      '.googleapis.com:443': _productionHost,
      'a..googleapis.com:443': _productionHost,
      'a..b:443': _expectedHostAndPort,
    };
    inputs.forEach((String input, String message) {
      expect(
        () => EmulatorHost.parse(input),
        _refusedWith(message),
        reason: input,
      );
    });
  });

  test('the two-argument constructor applies the same rules', () {
    final EmulatorHost named = EmulatorHost('LocalHost', 8080);
    expect(named.host, 'localhost');
    expect(named.port, 8080);
    expect(EmulatorHost('10.0.2.2', 9099).isLoopback, isFalse);
    expect(EmulatorHost('::1', 9000).host, '::1');

    expect(() => EmulatorHost('localhost', 0), _refusedWith(_portOutOfRange));
    expect(() => EmulatorHost('localhost', -1), _refusedWith(_portOutOfRange));
    expect(
      () => EmulatorHost('localhost', 65536),
      _refusedWith(_portOutOfRange),
    );
    expect(() => EmulatorHost('::1', 0), _refusedWith(_portOutOfRange));
    expect(() => EmulatorHost(':::', 9000), _refusedWith(_notIpv6));
    expect(() => EmulatorHost('1.2.3.4:', 9000), _refusedWith(_notIpv6));
    const List<String> badHosts = <String>[
      '',
      '[::1]',
      'gggg::1',
      '::1%eth0',
      'localhost:8080',
      'http://localhost',
      'local host',
      'localhost/',
      'user@localhost',
      'local%68ost',
      'localhost\n',
    ];
    for (final String host in badHosts) {
      expect(
        () => EmulatorHost(host, 8080),
        _refusedWith(_expectedHostAndPort),
        reason: '"$host"',
      );
    }
  });
}

void _emulatorHostValueTests() {
  test('owns: default ports, case, another port', () {
    // url.port is used, so the default of the scheme applies.
    expect(
      EmulatorHost('localhost', 80).owns(Uri.parse('http://localhost/x')),
      isTrue,
    );
    expect(
      EmulatorHost('localhost', 443).owns(Uri.parse('https://localhost/x')),
      isTrue,
    );
    expect(
      EmulatorHost('localhost', 80).owns(Uri.parse('https://localhost/x')),
      isFalse,
    );
    expect(
      EmulatorHost('localhost', 80).owns(Uri.parse('ws://localhost/x')),
      isFalse,
    );

    final EmulatorHost emulator = EmulatorHost.parse('Emulator.Internal:8080');
    expect(emulator.owns(Uri.parse('http://emulator.internal:8080/')), isTrue);
    expect(emulator.owns(Uri.parse('HTTP://EMULATOR.INTERNAL:8080/')), isTrue);
    expect(emulator.owns(Uri.parse('ws://emulator.internal:8080/s')), isTrue);
    expect(emulator.owns(Uri.parse('https://emulator.internal:8080/')), isTrue);

    expect(emulator.owns(Uri.parse('http://emulator.internal:8081/')), isFalse);
    expect(emulator.owns(Uri.parse('http://emulator.internal/')), isFalse);
    expect(emulator.owns(Uri.parse('http://other.internal:8080/')), isFalse);
    expect(
      emulator.owns(Uri.parse('http://emulator.internal.evil.test:8080/')),
      isFalse,
    );
    expect(
      emulator.owns(Uri.parse('http://sub.emulator.internal:8080/')),
      isFalse,
    );
    expect(emulator.owns(Uri.parse('/relative')), isFalse);
  });

  test('reading 8: owns compares IPv6 hosts by parsed address', () {
    final EmulatorHost long = EmulatorHost('0:0:0:0:0:0:0:1', 9000);
    expect(long.owns(Uri.parse('http://[::1]:9000/x')), isTrue);
    expect(long.owns(Uri.parse('http://[0:0:0:0:0:0:0:1]:9000/x')), isTrue);
    expect(long.owns(Uri.parse('http://[::0001]:9000/x')), isTrue);
    expect(long.owns(Uri.parse('http://[::2]:9000/x')), isFalse);
    expect(long.owns(Uri.parse('http://[::1]:9001/x')), isFalse);
    expect(long.owns(Uri.parse('http://localhost:9000/x')), isFalse);

    final EmulatorHost upper = EmulatorHost.parse('[2001:DB8::A]:9000');
    expect(
      upper.owns(Uri.parse('http://[2001:db8:0:0:0:0:0:a]:9000/')),
      isTrue,
    );
  });

  test('reading 8: an IPv6 host is stored in canonical text', () {
    const Map<String, String> canonical = <String, String>{
      '0:0:0:0:0:0:0:1': '::1',
      '::1': '::1',
      '0:0:0:0:0:0:0:0': '::',
      '2001:DB8::1': '2001:db8::1',
      '2001:0db8:0000:0000:0000:0000:0000:0001': '2001:db8::1',
      '2001:db8:0:0:1:0:0:1': '2001:db8::1:0:0:1',
      '2001:0:0:1:0:0:0:1': '2001:0:0:1::1',
      '1:0:2:3:4:5:6:7': '1:0:2:3:4:5:6:7',
      '1:0:0:0:0:0:0:0': '1::',
      'fe80::1': 'fe80::1',
    };
    canonical.forEach((String input, String host) {
      final EmulatorHost emulator = EmulatorHost(input, 9000);
      expect(emulator.host, host, reason: input);
      expect(emulator.authority, '[$host]:9000', reason: input);
      expect('$emulator', '[$host]:9000', reason: input);
      expect(EmulatorHost.parse('[$input]:9000'), emulator, reason: input);
    });

    final EmulatorHost long = EmulatorHost('0:0:0:0:0:0:0:1', 9000);
    final EmulatorHost short = EmulatorHost.parse('[::1]:9000');
    expect(long, short);
    expect(long.hashCode, short.hashCode);
    expect(long.isLoopback, isTrue);

    // An IPv4-mapped address is stored as hex groups and is not loopback.
    final EmulatorHost mapped = EmulatorHost.parse('[::FFFF:127.0.0.1]:9000');
    expect(mapped.host, '::ffff:7f00:1');
    expect(mapped.authority, '[::ffff:7f00:1]:9000');
    expect(mapped.isLoopback, isFalse);
    expect(mapped, EmulatorHost('::ffff:7f00:1', 9000));
    expect(mapped.owns(Uri.parse('http://[::ffff:127.0.0.1]:9000/')), isTrue);
    expect(mapped.owns(Uri.parse('http://127.0.0.1:9000/')), isFalse);
  });

  test('== and hashCode', () {
    final EmulatorHost parsed = EmulatorHost.parse('LOCALHOST:8080');
    final EmulatorHost built = EmulatorHost('localhost', 8080);
    expect(parsed, built);
    expect(parsed.hashCode, built.hashCode);
    expect(<EmulatorHost>{parsed, built}, hasLength(1));
    expect(parsed, isNot(EmulatorHost('localhost', 8081)));
    expect(parsed, isNot(EmulatorHost('127.0.0.1', 8080)));
    expect(parsed == ('localhost:8080' as Object), isFalse);
  });

  test('authority and toString', () {
    final EmulatorHost named = EmulatorHost.parse('LocalHost:8080');
    expect(named.authority, 'localhost:8080');
    expect('$named', 'localhost:8080');
    final EmulatorHost ipv4 = EmulatorHost('10.0.2.2', 9099);
    expect(ipv4.authority, '10.0.2.2:9099');
    expect('$ipv4', '10.0.2.2:9099');
    expect(EmulatorHost.parse(ipv4.authority), ipv4);
    final EmulatorHost ipv6 = EmulatorHost('::1', 9000);
    expect(ipv6.authority, '[::1]:9000');
    expect(EmulatorHost.parse(ipv6.authority), ipv6);
  });
}

void _mayCarryTokensTests() {
  test('mayCarryTokens table', () {
    final EmulatorHost emulator = EmulatorHost('10.0.2.2', 9099);
    // scheme://host -> [without an emulator, with the emulator]
    const Map<String, List<bool>> table = <String, List<bool>>{
      'https://localhost:9099/x': <bool>[true, true],
      'https://10.0.2.2:9099/x': <bool>[true, true],
      'https://api.example.test/x': <bool>[true, true],
      'wss://localhost:9099/x': <bool>[true, true],
      'wss://10.0.2.2:9099/x': <bool>[true, true],
      'wss://api.example.test/x': <bool>[true, true],
      'http://localhost:9099/x': <bool>[true, true],
      'http://127.0.0.1/x': <bool>[true, true],
      'http://[::1]:9099/x': <bool>[true, true],
      'http://10.0.2.2:9099/x': <bool>[false, true],
      'http://10.0.2.2:9098/x': <bool>[false, false],
      'http://10.0.2.2/x': <bool>[false, false],
      'http://api.example.test/x': <bool>[false, false],
      'http://api.example.test:9099/x': <bool>[false, false],
      'http://a.localhost/x': <bool>[false, false],
      'http://localhost./x': <bool>[false, false],
      'http://0.0.0.0/x': <bool>[false, false],
      'http://127.0.0.01/x': <bool>[false, false],
      'ws://localhost:9099/x': <bool>[true, true],
      'ws://localhost/x': <bool>[true, true],
      'ws://10.0.2.2:9099/x': <bool>[false, true],
      'ws://10.0.2.2/x': <bool>[false, false],
      'ws://api.example.test:80/x': <bool>[false, false],
      'ftp://localhost/x': <bool>[false, false],
      'ftp://10.0.2.2:9099/x': <bool>[false, false],
      'ftp://api.example.test/x': <bool>[false, false],
      'file://localhost/x': <bool>[false, false],
      'grpc://api.example.test:443/x': <bool>[false, false],
      '//api.example.test/x': <bool>[false, false],
      'HTTPS://API.EXAMPLE.TEST/x': <bool>[true, true],
      'HTTP://LOCALHOST/x': <bool>[true, true],
    };
    table.forEach((String text, List<bool> expected) {
      final Uri url = Uri.parse(text);
      expect(mayCarryTokens(url), expected[0], reason: text);
      expect(
        mayCarryTokens(url, emulator: emulator),
        expected[1],
        reason: '$text with the emulator',
      );
    });
  });

  test('mayCarryTokens: user info; empty host', () {
    final EmulatorHost emulator = EmulatorHost('10.0.2.2', 9099);
    const List<String> never = <String>[
      'https://user@api.example.test/x',
      'https://user:pw@api.example.test/x',
      'https://:pw@api.example.test/x',
      'wss://user@api.example.test:443/x',
      'http://user@localhost/x',
      'http://user:pw@10.0.2.2:9099/x',
      'https:///x',
      'https:x',
      'http:///x',
      '/x',
      'x',
      '',
      'mailto:someone@example.test',
    ];
    for (final String text in never) {
      final Uri url = Uri.parse(text);
      expect(mayCarryTokens(url), isFalse, reason: '"$text"');
      expect(mayCarryTokens(url, emulator: emulator), isFalse, reason: text);
    }
  });
}

void _originTests() {
  test('checkOrigin table', () {
    const Map<String, String> accepted = <String, String>{
      'https://api.example.test': 'https://api.example.test',
      'https://api.example.test/': 'https://api.example.test',
      'https://API.Example.test:8443': 'https://api.example.test:8443',
      'https://api.example.test:443': 'https://api.example.test',
      'HTTPS://api.example.test': 'https://api.example.test',
      'http://localhost': 'http://localhost',
      'http://localhost:80': 'http://localhost',
      'http://LOCALHOST:8080/': 'http://localhost:8080',
      'http://127.0.0.1:9099': 'http://127.0.0.1:9099',
      'http://[::1]:9000': 'http://[::1]:9000',
      'https://[2001:DB8::1]': 'https://[2001:db8::1]',
    };
    accepted.forEach((String input, String origin) {
      expect('${checkOrigin(Uri.parse(input))}', origin, reason: input);
    });

    const List<String> refused = <String>[
      'http://api.example.test',
      'http://a.localhost',
      'http://0.0.0.0',
      'http://127.0.0.01',
      'ws://localhost:9000',
      'wss://api.example.test:443',
      'ftp://api.example.test',
      'api.example.test',
      '//api.example.test',
      'https://api.example.test/v1',
      'https://api.example.test//',
      'https://api.example.test?x=1',
      'https://api.example.test?',
      'https://api.example.test#f',
      'https://api.example.test/#',
      'https://user@api.example.test',
      'https://user:pw@api.example.test',
      'http://user@localhost',
      'https:///',
      'https:',
      '',
    ];
    for (final String input in refused) {
      expect(
        () => checkOrigin(Uri.parse(input)),
        throwsArgumentError,
        reason: '"$input"',
      );
    }
  });

  test('checkOrigin: the message names only the scheme and the host', () {
    final String text = _errorTextOf(
      () => checkOrigin(
        Uri.parse(
          'https://zzuser:zzpass@api.example.test:8443/zzpath?k=zzquery#zzfrag',
        ),
      ),
    );
    for (final String part in <String>[
      'zzuser',
      'zzpass',
      'zzpath',
      'zzquery',
      'zzfrag',
    ]) {
      expect(text, isNot(contains(part)), reason: part);
    }
    final String clearText = _errorTextOf(
      () => checkOrigin(Uri.parse('http://zzuser:zzpass@remote.example.test')),
    );
    expect(clearText, isNot(contains('zzuser')));
    expect(clearText, isNot(contains('zzpass')));
  });

  test('reading 16: checkOrigin and tokenOrigin canonicalise an IPv6 host', () {
    final Uri long = Uri.parse('http://[0:0:0:0:0:0:0:1]:9000');
    final Uri short = Uri.parse('http://[::1]:9000');
    expect('${checkOrigin(long)}', 'http://[::1]:9000');
    expect(checkOrigin(long), checkOrigin(short));
    expect('${tokenOrigin(long)}', 'http://[::1]:9000');
    expect(tokenOrigin(long), tokenOrigin(short));
    expect(tokenOrigin(long).hashCode, tokenOrigin(short).hashCode);
    expect(
      tokenOrigin(Uri.parse('wss://[2001:DB8:0:0:0:0:0:1]:443/socket')),
      tokenOrigin(Uri.parse('https://[2001:db8::1]/v1')),
    );
    expect(
      tokenOrigin(Uri.parse('ws://[0:0:0:0:0:0:0:1]:9000/socket')),
      checkOrigin(short),
    );
  });

  test('tokenOrigin table', () {
    const Map<String, String> table = <String, String>{
      // ws and wss mapped.
      'ws://localhost:9000/stream': 'http://localhost:9000',
      'wss://api.example.test:8443/socket?x=1': 'https://api.example.test:8443',
      'wss://api.example.test:443/socket': 'https://api.example.test',
      'ws://localhost:80/socket': 'http://localhost',
      'WSS://API.example.test:443': 'https://api.example.test',
      // Default ports for http and https.
      'https://api.example.test/v1/call?x=1#f': 'https://api.example.test',
      'https://api.example.test:443/v1': 'https://api.example.test',
      'https://API.Example.Test:8443/v1': 'https://api.example.test:8443',
      'http://localhost/v1': 'http://localhost',
      'http://localhost:80/v1': 'http://localhost',
      'http://localhost:8080/v1': 'http://localhost:8080',
      'https://user:pw@api.example.test/v1': 'https://api.example.test',
      // Reading 10: another scheme keeps its scheme, host and explicit port.
      'ftp://files.example.test:21/x': 'ftp://files.example.test:21',
      'ftp://files.example.test/x': 'ftp://files.example.test',
    };
    table.forEach((String input, String origin) {
      expect('${tokenOrigin(Uri.parse(input))}', origin, reason: input);
    });
    expect(tokenOrigin(Uri.parse('https://api.example.test/v1')).port, 443);
    expect(tokenOrigin(Uri.parse('wss://api.example.test:443/s')).port, 443);
    expect(tokenOrigin(Uri.parse('http://localhost/v1')).port, 80);
    expect(tokenOrigin(Uri.parse('ws://localhost:80/s')).port, 80);
    expect(
      tokenOrigin(Uri.parse('wss://api.example.test:443/socket')),
      tokenOrigin(Uri.parse('https://api.example.test/v1/call')),
    );
    expect(
      tokenOrigin(Uri.parse('wss://api.example.test:8443/socket')),
      isNot(tokenOrigin(Uri.parse('https://api.example.test/v1/call'))),
    );
    expect(
      tokenOrigin(Uri.parse('http://api.example.test:443/')),
      isNot(tokenOrigin(Uri.parse('https://api.example.test/'))),
    );
  });

  test('a wss URL without a port throws', () {
    const List<String> withoutPort = <String>[
      'wss://api.example.test/socket',
      'wss://api.example.test',
      'ws://localhost/socket',
      'WS://localhost',
      // Reading 10: a port of 0 counts as no port.
      'ws://localhost:0/socket',
      'wss://api.example.test:0',
    ];
    for (final String input in withoutPort) {
      expect(
        () => tokenOrigin(Uri.parse(input)),
        throwsArgumentError,
        reason: input,
      );
    }
    final String text = _errorTextOf(
      () => tokenOrigin(
        Uri.parse('wss://zzuser:zzpass@api.example.test/zzpath?k=zzquery'),
      ),
    );
    for (final String part in <String>[
      'zzuser',
      'zzpass',
      'zzpath',
      'zzquery',
    ]) {
      expect(text, isNot(contains(part)), reason: part);
    }
  });

  test('reading 10: rules T and O refuse a URL of another scheme', () {
    final Uri other = Uri.parse('ftp://localhost:21/x');
    expect('${tokenOrigin(other)}', 'ftp://localhost:21');
    expect(mayCarryTokens(other), isFalse);
    expect(
      mayCarryTokens(other, emulator: EmulatorHost('localhost', 21)),
      isFalse,
    );
    expect(() => checkOrigin(tokenOrigin(other)), throwsArgumentError);
  });
}

void _hostLabelTests() {
  test('host label table', () {
    final List<String> labels = <String>[
      'us-central1',
      'a' * 63,
      'a',
      '0',
      'demo-project-123',
      'a--b',
      '1a',
    ];
    for (final String label in labels) {
      expect(isHostLabel(label), isTrue, reason: label);
    }
    final List<String> refused = <String>[
      '',
      'a' * 64,
      'Us-central1',
      'US',
      'us.central1',
      'us/central1',
      'attacker.example/',
      '-us',
      'us-',
      '-',
      'us central1',
      ' us',
      'us\n',
      'us\u0000',
      'us_central1',
      'us:80',
      'us@x',
      'us%2e',
      'ü',
      '#',
      '?',
    ];
    for (final String label in refused) {
      expect(isHostLabel(label), isFalse, reason: '"$label"');
    }
  });

  test('a host built from checked labels keeps its host', () {
    const String project = 'demo-project';
    for (final String region in <String>[
      'attacker.example/',
      'x@evil',
      'a#b',
    ]) {
      expect(isHostLabel(region), isFalse);
    }
    const String region = 'us-central1';
    expect(isHostLabel(region) && isHostLabel(project), isTrue);
    final Uri url = Uri(
      scheme: 'https',
      host: '$region-$project.cloudfunctions.net',
      path: '/fn',
    );
    expect(url.host, 'us-central1-demo-project.cloudfunctions.net');
  });
}
