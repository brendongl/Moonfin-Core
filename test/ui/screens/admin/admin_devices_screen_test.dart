import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/devices/admin_devices_screen.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

class _FakeDevicesApi extends Fake implements AdminDevicesApi {
  final renamed = <(String, String?)>[];
  final deleted = <String>[];
  List<DeviceInfoDto> devices = const [
    DeviceInfoDto(id: 'tv', name: 'Living room', appName: 'Moonfin'),
  ];

  @override
  Future<List<DeviceInfoDto>> getDevices({String? userId}) async => devices;

  @override
  Future<void> updateDeviceOptions(String id, DeviceOptionsDto options) async {
    renamed.add((id, options.customName));
  }

  @override
  Future<void> deleteDevice(String id) async => deleted.add(id);
}

void main() {
  late _FakeDevicesApi devices;
  late AppLocalizations l10n;

  setUp(() async {
    devices = _FakeDevicesApi();
    final client = _MockMediaServerClient();
    when(() => client.adminDevicesApi).thenReturn(devices);
    when(() => client.deviceInfo).thenReturn(const DeviceInfo(
      id: 'this-one',
      name: 'Test',
      appName: 'Moonfin',
      appVersion: '1',
    ));
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() => GetIt.instance.reset());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: AdminDevicesScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> rename(WidgetTester tester, String name) async {
    await tester.tap(find.byTooltip(l10n.adminEditName));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, name);
    await tester.tap(find.widgetWithText(FilledButton, l10n.save));
    await tester.pumpAndSettle();
  }

  testWidgets('rename posts the custom name', (tester) async {
    await pump(tester);
    await rename(tester, 'Den');
    expect(devices.renamed.single, ('tv', 'Den'));
  });

  testWidgets('an unchanged name posts nothing', (tester) async {
    await pump(tester);
    await rename(tester, 'Living room');
    expect(devices.renamed, isEmpty);
  });

  testWidgets('delete asks first and then deletes', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip(l10n.delete));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.delete));
    await tester.pumpAndSettle();
    expect(devices.deleted, ['tv']);
  });

  testWidgets('delete all spares this device by its Emby reported id', (
    tester,
  ) async {
    devices.devices = const [
      DeviceInfoDto(id: '1', name: 'Living room', reportedDeviceId: 'tv'),
      DeviceInfoDto(id: '2', name: 'This app', reportedDeviceId: 'this-one'),
    ];
    await pump(tester);

    await tester.tap(find.byTooltip(l10n.adminDeleteAllDevices));
    await tester.pumpAndSettle();
    expect(find.text(l10n.adminDeleteAllDevicesConfirm(1)), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, l10n.delete));
    await tester.pumpAndSettle();
    expect(devices.deleted, ['1']);
  });
}
