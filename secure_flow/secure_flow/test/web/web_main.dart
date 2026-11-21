// Compiled by web_compile_test.dart: the library must build for the web.

import 'package:secure_flow/secure_flow.dart';

void main() {
  final SecureFlow<String> flow = RecaptchaFlow(siteKey: 'key');
  print(flow.purpose.name);
  print(RecaptchaFlow.enterprise(siteKey: 'key', action: 'verify').request);
  print(InPageRecaptchaPresenter(containerId: 'recaptcha').kind.name);
  print(SecureEnvironment.current().operatingSystem);
}
