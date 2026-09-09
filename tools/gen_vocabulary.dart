// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

void main() {
  final sqlDir = Directory('supabase/migrations');
  if (!sqlDir.existsSync()) {
    print('SQL directory not found');
    exit(1);
  }

  final views = <String>[];
  final tables = <String>[];
  final rpcInternal = <String>[];
  
  final rpcCallable = [
    'fn_record_meter_reading',
    'fn_post_bill_amount',
    'fn_record_payment',
    'fn_issue_disconnection_notice',
    'fn_close_disconnection_notice',
  ];

  final viewRegex = RegExp(r'create\s+(?:or\s+replace\s+)?view\s+(?:[a-z0-9_]+\.)?([a-z0-9_]+)', caseSensitive: false);
  final tableRegex = RegExp(r'create\s+table\s+(?:if\s+not\s+exists\s+)?(?:[a-z0-9_]+\.)?([a-z0-9_]+)', caseSensitive: false);
  final functionRegex = RegExp(r'create\s+(?:or\s+replace\s+)?function\s+(?:[a-z0-9_]+\.)?([a-z0-9_]+)', caseSensitive: false);
  final triggerBoundRegex = RegExp(r'create\s+trigger\s+.*?\s+execute\s+function\s+([a-z0-9_]+)', caseSensitive: false);

  final triggerFunctions = <String>{};
  
  for (final file in sqlDir.listSync().whereType<File>().where((f) => f.path.endsWith('.sql'))) {
    final content = file.readAsStringSync();
    
    for (final match in triggerBoundRegex.allMatches(content)) {
      triggerFunctions.add(match.group(1)!.toLowerCase());
    }
  }

  for (final file in sqlDir.listSync().whereType<File>().where((f) => f.path.endsWith('.sql'))) {
    final content = file.readAsStringSync();
    
    for (final match in viewRegex.allMatches(content)) {
      views.add(match.group(1)!);
    }
    for (final match in tableRegex.allMatches(content)) {
      tables.add(match.group(1)!);
    }
    for (final match in functionRegex.allMatches(content)) {
      final fn = match.group(1)!.toLowerCase();
      if (!rpcCallable.contains(fn) && !triggerFunctions.contains(fn)) {
        if (!rpcInternal.contains(fn)) {
          print('WARNING: Unknown callable function $fn found. Not in allowlist and not trigger-bound. Treating as internal.');
          rpcInternal.add(fn);
        }
      } else if (triggerFunctions.contains(fn)) {
        if (!rpcInternal.contains(fn)) {
          rpcInternal.add(fn);
        }
      }
    }
  }

  final output = {
    'views': views.toSet().toList()..sort(),
    'tables': tables.toSet().toList()..sort(),
    'rpc_callable': rpcCallable..sort(),
    'rpc_internal': rpcInternal..sort(),
  };

  final outFile = File('tools/week11_vocabulary.json');
  outFile.createSync(recursive: true);
  outFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(output));
}
