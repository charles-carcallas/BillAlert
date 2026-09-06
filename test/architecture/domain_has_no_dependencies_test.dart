import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The dependency rule, enforced rather than described.
///
/// `domain/` is pure Dart. It must not import Flutter, Supabase, Drift, http,
/// or anything else from `package:` other than the app's own code. If it
/// could, business rules would start depending on a database driver and the
/// use-case tests would need a network to run.
///
/// A document saying this drifts out of date in a fortnight. A test does not.
void main() {
  /// Package prefixes `domain/` is never allowed to import. `package:meta`
  /// and `package:collection` would be arguable, but they are not needed, and
  /// an empty allow-list is much easier to defend than a short one.
  const forbidden = <String>[
    'package:flutter/',
    'package:flutter_test/',
    'package:supabase',
    'package:postgrest',
    'package:drift',
    'package:sqlite3',
    'package:http',
    'package:connectivity_plus',
    'package:flutter_secure_storage',
    'package:path_provider',
    'package:uuid',
    'package:intl',
    'package:go_router',
    'package:flutter_riverpod',
    'dart:io',
    'dart:ui',
  ];

  late List<File> domainFiles;
  late List<File> coreFiles;

  setUpAll(() {
    domainFiles = _dartFilesIn('lib/domain');
    coreFiles = _dartFilesIn('lib/core');
  });

  test('there is a domain layer to check', () {
    // Guards against the test passing because the glob found nothing.
    expect(domainFiles.length, greaterThan(10));
  });

  test('domain/ imports no packages at all', () {
    final offences = <String>[];

    for (final File file in domainFiles) {
      for (final String import in _importsOf(file)) {
        for (final String banned in forbidden) {
          if (import.startsWith(banned)) {
            offences.add('${_relative(file)} imports $import');
          }
        }
      }
    }

    expect(
      offences,
      isEmpty,
      reason: 'domain/ must stay pure Dart:\n${offences.join('\n')}',
    );
  });

  test('domain/ imports only core/ and itself', () {
    // Stricter than the ban list, and the rule that actually matters: the
    // domain layer may reach sideways into core/ for Result and AppFailure,
    // and nowhere else. In particular it must never import data/ or
    // presentation/, which would invert the whole architecture.
    final offences = <String>[];

    for (final File file in domainFiles) {
      for (final String import in _importsOf(file)) {
        final isDartCore = import == 'dart:async' ||
            import == 'dart:convert' ||
            import == 'dart:math';
        final isRelative = !import.startsWith('package:') &&
            !import.startsWith('dart:');
        final isOwnPackage = import.startsWith('package:billalert/domain/') ||
            import.startsWith('package:billalert/core/');

        if (!isDartCore && !isRelative && !isOwnPackage) {
          offences.add('${_relative(file)} imports $import');
        }
        if (isRelative &&
            (import.contains('/data/') || import.contains('/presentation/'))) {
          offences.add('${_relative(file)} reaches into an outer layer: $import');
        }
      }
    }

    expect(offences, isEmpty, reason: offences.join('\n'));
  });

  test('core/ is pure Dart too', () {
    // core/ holds Result, AppFailure and AppConfig, which domain/ imports.
    // If core/ took a package dependency, domain/ would inherit it and the
    // test above would be quietly meaningless.
    final offences = <String>[];

    for (final File file in coreFiles) {
      for (final String import in _importsOf(file)) {
        if (import.startsWith('package:') &&
            !import.startsWith('package:billalert/')) {
          offences.add('${_relative(file)} imports $import');
        }
      }
    }

    expect(offences, isEmpty, reason: offences.join('\n'));
  });

  test('no peso amount is held in a double anywhere in lib/', () {
    // Catches the mistake this project is most likely to make: someone types
    // `double amount` or `double total` because it is quicker than Money.
    final pattern = RegExp(
      r'\bdouble\s+\w*(amount|total|balance|price|peso|paid|tendered|change)',
      caseSensitive: false,
    );
    final offences = <String>[];

    for (final File file in _dartFilesIn('lib')) {
      if (file.path.endsWith('.g.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) {
          offences.add('${_relative(file)}:${i + 1}  ${lines[i].trim()}');
        }
      }
    }

    expect(
      offences,
      isEmpty,
      reason: 'Money is an integer number of centavos, never a double:\n'
          '${offences.join('\n')}',
    );
  });
}

List<File> _dartFilesIn(String path) => Directory(path)
    .listSync(recursive: true)
    .whereType<File>()
    .where((File f) => f.path.endsWith('.dart'))
    .toList();

/// Every import URI in a file, including the ones inside doc comments'
/// code samples being harmless because they are not `import` lines.
List<String> _importsOf(File file) {
  final pattern = RegExp('''^\\s*import\\s+['"]([^'"]+)['"]''');
  return file
      .readAsLinesSync()
      .map((String line) => pattern.firstMatch(line)?.group(1))
      .whereType<String>()
      .toList();
}

String _relative(File file) => file.path.replaceAll(r'\', '/');
