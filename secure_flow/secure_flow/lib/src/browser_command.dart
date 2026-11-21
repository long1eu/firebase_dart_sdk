/// The command that opens [url] in the default browser of [operatingSystem] (a value of
/// `Platform.operatingSystem`): `open` on macOS, `rundll32 url.dll,FileProtocolHandler` on Windows,
/// `xdg-open` on Linux. The URL is one argument, for a process started without a shell. Null on
/// other systems.
({String executable, List<String> arguments})? browserCommand(
  String operatingSystem,
  Uri url,
) => switch (operatingSystem) {
  'macos' => (executable: 'open', arguments: <String>[url.toString()]),
  'windows' => (
    executable: 'rundll32',
    arguments: <String>['url.dll,FileProtocolHandler', url.toString()],
  ),
  'linux' => (executable: 'xdg-open', arguments: <String>[url.toString()]),
  _ => null,
};
