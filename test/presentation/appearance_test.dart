import 'package:billalert/presentation/appearance_controller.dart';
import 'package:billalert/presentation/common/appearance_setting.dart';
import 'package:billalert/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'defaults to system and restores persisted choice in a new container',
    () async {
      final first = ProviderContainer();
      expect(
        await first.read(appearanceControllerProvider.future),
        ThemeMode.system,
      );
      expect(
        await first
            .read(appearanceControllerProvider.notifier)
            .select(ThemeMode.dark),
        isTrue,
      );
      first.dispose();
      final reopened = ProviderContainer();
      addTearDown(reopened.dispose);
      expect(
        await reopened.read(appearanceControllerProvider.future),
        ThemeMode.dark,
      );
      await reopened
          .read(appearanceControllerProvider.notifier)
          .select(ThemeMode.system);
      expect(
        await const FlutterSecureStorage().read(
          key: AppearanceController.storageKey,
        ),
        'system',
      );
    },
  );

  testWidgets('picker changes app brightness and System follows the device', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, _) {
            return MaterialApp(
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode:
                  ref.watch(appearanceControllerProvider).value ??
                  ThemeMode.system,
              home: const Scaffold(body: AppearanceSetting()),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    Brightness brightness() =>
        Theme.of(tester.element(find.byType(AppearanceSetting))).brightness;
    expect(brightness(), Brightness.dark);
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.light);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.dark);
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.light);
    expect(tester.takeException(), isNull);
  });
}
