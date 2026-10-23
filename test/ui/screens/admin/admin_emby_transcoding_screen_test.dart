import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/admin_draft.dart';
import 'package:moonfin/ui/screens/admin/admin_nav.dart';
import 'package:moonfin/ui/screens/admin/emby/admin_emby_transcoding_screen.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

class _FakeSystemApi extends Fake implements AdminSystemApi {
  Map<String, dynamic> encoding = {
    'HardwareAccelerationMode': 0,
    'CodecConfigurations': <Object>[],
    'EnableThrottling': false,
    'EnableSoftwareToneMapping': false,
    'TranscodingMaxWidth': 0,
    'DownMixAudioBoost': 2,
  };
  final posted = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> getNamedConfiguration(String key) async {
    expect(key, 'encoding');
    return Map<String, dynamic>.from(encoding);
  }

  @override
  Future<void> updateNamedConfiguration(
    String key,
    Map<String, dynamic> config,
  ) async {
    expect(key, 'encoding');
    posted.add(config);
    encoding = Map<String, dynamic>.from(config);
  }
}

class _FakeInfoApi extends Fake implements SystemApi {
  @override
  Future<Map<String, dynamic>> getSystemInfo() async => {
    'Id': 'emby',
    'HardwareAccelerationRequiresPremiere': true,
  };
}

Map<String, dynamic> _codec(
  String id,
  String direction,
  String type, {
  int priority = 0,
  bool enabled = false,
}) => {
  'Id': id,
  'Name': id,
  'Direction': direction,
  'MediaTypeName': type,
  'IsHardwareCodec': true,
  'DefaultPriority': priority,
  'IsEnabledByDefault': enabled,
};

class _FakeEmbyApi extends Fake implements EmbyAdminApi {
  bool active = false;

  @override
  Future<PremiereStatus> getPremiereStatus() async =>
      PremiereStatus(isActive: active, hasKey: active);

  @override
  Future<List<Map<String, dynamic>>> getVideoCodecInformation() async => [
    _codec('qsv-h264-dec', 'Decoder', 'H.264', priority: 90, enabled: true),
    _codec('vaapi-h264-dec', 'Decoder', 'H.264', priority: 80, enabled: true),
    _codec('qsv-h264-enc', 'Encoder', 'H.264', priority: 50),
    {
      'Id': 'V-E-libx264',
      'Name': 'x264',
      'Direction': 'Encoder',
      'IsHardwareCodec': false,
    },
  ];

  @override
  Future<Map<String, dynamic>> getToneMapOptions() async => {
    'Object': {
      'FeatureRequiresPremiere': true,
      'OptionsVisibility': {
        'IsSoftwareToneMappingAvailable': true,
        'IsAnyHardwareToneMappingAvailable': false,
      },
    },
  };
}

void main() {
  late _FakeSystemApi api;
  late _FakeEmbyApi emby;
  late AppLocalizations l10n;

  setUp(() async {
    api = _FakeSystemApi();
    emby = _FakeEmbyApi();
    final client = _MockMediaServerClient();
    when(() => client.adminSystemApi).thenReturn(api);
    when(() => client.systemApi).thenReturn(_FakeInfoApi());
    when(() => client.embyAdminApi).thenReturn(emby);
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() async {
    AdminDraft.active.value = null;
    await GetIt.instance.reset();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The Premiere dialog links to the key page through the router.
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: AdminServerScope(
              serverType: ServerType.emby,
              child: AdminEmbyTranscodingScreen(),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pickMode(WidgetTester tester, String label) async {
    await tester.tap(find.text(l10n.no).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<Map<String, dynamic>> save() async {
    expect(await AdminDraft.active.value!.save(), isTrue);
    return api.posted.last;
  }

  testWidgets('turning hardware acceleration on asks about Premiere', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text(l10n.adminPremiereNote), findsNWidgets(2));

    await pickMode(tester, l10n.yes);
    expect(find.text(l10n.embyPremiereRequiredTitle), findsOneWidget);
    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();
    expect(AdminDraft.active.value!.isDirty, isFalse);

    await pickMode(tester, l10n.yes);
    await tester.tap(find.text(l10n.embyPremiereSaveAnyway));
    await tester.pumpAndSettle();
    expect((await save())['HardwareAccelerationMode'], 1);
  });

  testWidgets('with Premiere there is no dialog or note', (tester) async {
    emby.active = true;
    await pump(tester);
    expect(find.text(l10n.adminPremiereNote), findsNothing);

    await pickMode(tester, l10n.yes);
    expect(find.text(l10n.embyPremiereRequiredTitle), findsNothing);
    expect((await save())['HardwareAccelerationMode'], 1);
  });

  testWidgets('Advanced lists the hardware codecs to enable and reorder', (
    tester,
  ) async {
    emby.active = true;
    await pump(tester);
    await pickMode(tester, l10n.adminTranscodingHwaAdvanced);

    // Section labels show in capitals.
    expect(
      find.text(l10n.adminTranscodingHwDecoders.toUpperCase()),
      findsOneWidget,
    );
    expect(
      find.text(l10n.adminTranscodingHwEncoders.toUpperCase()),
      findsOneWidget,
    );
    expect(find.text('x264'), findsNothing);

    // The second decoder moves above the first.
    final vaapi = find.widgetWithText(CheckboxListTile, 'vaapi-h264-dec');
    await tester.tap(
      find.descendant(of: vaapi, matching: find.byIcon(Icons.arrow_upward)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('qsv-h264-enc'));
    await tester.pumpAndSettle();

    final codecs = {
      for (final c in (await save())['CodecConfigurations'] as List)
        c['CodecId']: c,
    };
    expect(codecs['vaapi-h264-dec']['Priority'], 100);
    expect(codecs['qsv-h264-dec']['Priority'], 99);
    expect(codecs['qsv-h264-dec']['IsEnabled'], isTrue);
    expect(codecs['qsv-h264-enc']['IsEnabled'], isTrue);
    expect(codecs['qsv-h264-enc']['Priority'], 50);
    expect(codecs, isNot(contains('V-E-libx264')));
  });

  testWidgets('leaving Advanced drops the codec list', (tester) async {
    emby.active = true;
    api.encoding['HardwareAccelerationMode'] = 2;
    api.encoding['CodecConfigurations'] = [
      {'CodecId': 'qsv-h264-dec', 'Priority': 100, 'IsEnabled': true},
    ];
    await pump(tester);
    // A codec missing from a saved list shows up switched off.
    final vaapi = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'vaapi-h264-dec'),
    );
    expect(vaapi.value, isFalse);
    expect(AdminDraft.active.value!.isDirty, isFalse);

    await tester.tap(find.text(l10n.adminTranscodingHwaAdvanced).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.yes).last);
    await tester.pumpAndSettle();

    final posted = await save();
    expect(posted['HardwareAccelerationMode'], 1);
    expect(posted['CodecConfigurations'], isEmpty);
  });

  testWidgets('tone mapping saves into the encoding configuration', (
    tester,
  ) async {
    emby.active = true;
    await pump(tester);
    expect(find.text(l10n.adminTranscodingToneMapHardware), findsNothing);

    await tester.tap(
      find.widgetWithText(SwitchListTile, l10n.adminTranscodingToneMapSoftware),
    );
    await tester.pumpAndSettle();
    expect((await save())['EnableSoftwareToneMapping'], isTrue);
  });
}
