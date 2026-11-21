// Asks for a code with the presenter that fits the environment: at the terminal when there is
// one, otherwise in a small page in the system browser.
//
//     dart run example/main.dart

import 'dart:io';

import 'package:secure_flow/secure_flow.dart';

Future<void> main() async {
  try {
    final String code = await const CodeEntryFlow(
      prompt: 'Type any code to finish the example',
    ).run(timeout: const Duration(minutes: 2));
    stdout.writeln('Received a code of ${code.length} characters.');
  } on SecureFlowException catch (e) {
    stderr.writeln(e.message);
    exitCode = 1;
  }
}
