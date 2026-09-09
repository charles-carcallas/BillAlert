import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Check Supabase vocabulary in lib/', () {
    final vocabFile = File('tools/week11_vocabulary.json');
    if (!vocabFile.existsSync()) {
      fail('Vocabulary file missing. Run tools/gen_vocabulary.dart');
    }
    final vocab = jsonDecode(vocabFile.readAsStringSync()) as Map<String, dynamic>;
    final rpcCallable = List<String>.from(vocab['rpc_callable']);
    final rpcInternal = List<String>.from(vocab['rpc_internal']);
    final views = List<String>.from(vocab['views']);
    final tables = List<String>.from(vocab['tables']);

    final rpcRegex = RegExp(r"\.rpc\('([^']+)'\)");
    final fromRegex = RegExp(r"\.from\('([^']+)'\)");

    final libDir = Directory('lib');
    for (final file in libDir.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') || file.path.endsWith('.g.dart') || file.path.endsWith('.freezed.dart')) continue;

      final content = file.readAsStringSync();
      for (final match in rpcRegex.allMatches(content)) {
        final rpc = match.group(1)!;
        if (!rpcCallable.contains(rpc)) {
          fail('File ${file.path} calls internal or unknown RPC: $rpc');
        }
        if (rpcInternal.contains(rpc)) {
          fail('File ${file.path} calls internal RPC: $rpc');
        }
      }
      for (final match in fromRegex.allMatches(content)) {
        final from = match.group(1)!;
        if (!views.contains(from) && !tables.contains(from)) {
          fail('File ${file.path} queries unknown view or table: $from');
        }
      }
    }
  });
}
