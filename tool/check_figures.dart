// Checks the hand-written SVG figures under docs/images: every figure carries
// the same light and dark palette, every colour it draws with is mapped to a
// palette variable, and the text and mark colours meet WCAG AA contrast.
//
// Run from the repository root: dart tool/check_figures.dart
import 'dart:io';
import 'dart:math';

void main() {
  final List<File> files =
      Directory('docs/images')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.svg'))
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));
  final List<String> problems = <String>[];
  Map<String, String>? light;
  Map<String, String>? dark;

  for (final File file in files) {
    final String svg = file.readAsStringSync();
    final RegExpMatch? style = RegExp(
      r'<style id="figure-theme">(.*?)</style>',
      dotAll: true,
    ).firstMatch(svg);
    if (style == null) {
      problems.add('${file.path}: no <style id="figure-theme"> block');
      continue;
    }
    final String css = style.group(1)!;
    final int media = css.indexOf('@media (prefers-color-scheme: dark)');
    if (media < 0) {
      problems.add('${file.path}: no dark block');
      continue;
    }
    final Map<String, String> l = _vars(css.substring(0, media));
    final Map<String, String> d = _vars(css.substring(media));
    light ??= l;
    dark ??= d;
    if (!_same(l, light) || !_same(d, dark)) {
      problems.add('${file.path}: palette differs from ${files.first.path}');
    }
    // Every colour drawn with a presentation attribute needs a rule that maps it.
    for (final RegExpMatch m in RegExp(r'\b(fill|stroke)="(#[0-9a-fA-F]{3,6})"').allMatches(svg)) {
      final String rule = '[${m.group(1)}="${m.group(2)}"]';
      if (!css.contains(rule)) problems.add('${file.path}: no rule for $rule');
    }
    for (final String bad in <String>['<script', 'href="http', 'xlink:href="http', '@import']) {
      if (svg.contains(bad)) problems.add('${file.path}: contains $bad');
    }
    if (!svg.contains('<title') || !svg.contains('<desc')) {
      problems.add('${file.path}: needs <title> and <desc>');
    }
  }

  // Text needs 4.5:1, marks and bars 3:1, in both modes.
  const List<(String, List<String>, double)> pairs = <(String, List<String>, double)>[
    (
      'fg',
      <String>['bg', 'panel', 'panel-strong', 'accent-bg', 'success-bg', 'severe-bg', 'done-bg'],
      4.5,
    ),
    (
      'fg-muted',
      <String>['bg', 'panel', 'panel-strong', 'accent-bg', 'success-bg', 'severe-bg', 'done-bg'],
      4.5,
    ),
    ('accent', <String>['bg', 'panel'], 4.5),
    ('success', <String>['bg', 'panel'], 4.5),
    ('danger', <String>['bg', 'panel'], 4.5),
    ('on-bar', <String>['bar'], 4.5),
    ('attention', <String>['bg', 'panel'], 3),
    ('severe', <String>['bg', 'panel'], 3),
    ('done', <String>['bg', 'panel'], 3),
    ('faint', <String>['bg', 'panel'], 3),
    ('bar', <String>['bg', 'panel'], 3),
    ('on-accent', <String>['success', 'danger'], 3),
  ];
  for (final (String mode, Map<String, String>? palette) in <(String, Map<String, String>?)>[
    ('light', light),
    ('dark', dark),
  ]) {
    if (palette == null) continue;
    for (final (String fg, List<String> bgs, double need) in pairs) {
      for (final String bg in bgs) {
        final double ratio = _contrast(palette['--fig-$fg']!, palette['--fig-$bg']!);
        final String line =
            '$mode ${fg.padRight(10)} on ${bg.padRight(12)} '
            '${ratio.toStringAsFixed(2)} (needs $need)';
        if (ratio < need) {
          problems.add('contrast: $line');
        } else {
          stdout.writeln(line);
        }
      }
    }
  }

  if (problems.isEmpty) {
    stdout.writeln('${files.length} figures OK');
  } else {
    problems.forEach(stderr.writeln);
    exitCode = 1;
  }
}

Map<String, String> _vars(String css) => <String, String>{
  for (final RegExpMatch m in RegExp(r'(--fig-[a-z-]+):\s*(#[0-9a-fA-F]{6});').allMatches(css))
    m.group(1)!: m.group(2)!.toLowerCase(),
};

bool _same(Map<String, String> a, Map<String, String>? b) =>
    b != null && a.length == b.length && a.keys.every((String k) => a[k] == b[k]);

double _luminance(String hex) {
  double channel(int i) {
    final double c = int.parse(hex.substring(i, i + 2), radix: 16) / 255;
    return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(1) + 0.7152 * channel(3) + 0.0722 * channel(5);
}

double _contrast(String a, String b) {
  final double la = _luminance(a), lb = _luminance(b);
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}
