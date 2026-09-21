import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest activity resolves to the Kotlin entry point', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final namespace = RegExp(
      r'namespace\s*=\s*"([^"]+)"',
    ).firstMatch(gradle)!.group(1)!;
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final activity = RegExp(
      r'<activity\s+android:name="([^"]+)"',
    ).firstMatch(manifest)!.group(1)!;
    final qualifiedName = activity.startsWith('.')
        ? '$namespace$activity'
        : activity;
    final source = File(
      'android/app/src/main/kotlin/${qualifiedName.replaceAll('.', '/')}.kt',
    );
    expect(
      source.existsSync(),
      isTrue,
      reason: 'Manifest launches $qualifiedName; its Kotlin file must exist.',
    );
    final kotlin = source.readAsStringSync();
    final packageName = qualifiedName.substring(
      0,
      qualifiedName.lastIndexOf('.'),
    );
    expect(kotlin, contains('package $packageName\n'));
    expect(
      kotlin,
      contains('class MainActivity : FlutterFragmentActivity()'),
      reason: 'Biometric unlock requires FlutterFragmentActivity.',
    );
  });
}
