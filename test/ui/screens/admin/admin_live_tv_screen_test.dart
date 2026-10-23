import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/admin_draft.dart';
import 'package:moonfin/ui/screens/admin/admin_nav.dart';
import 'package:moonfin/ui/screens/admin/livetv/admin_live_tv_screen.dart';
import 'package:moonfin/ui/screens/admin/providers/admin_user_providers.dart';
import 'package:moonfin/ui/screens/admin/widgets/admin_settings_search.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

const _tunerId = '1c92f00ffde046528c7174f564e0e6b2';
const _xmltvId = '1a2e1b1caee4458b94bbadbd55bdec42';
const _tunerChannel =
    'm3u_2925a32d0298519852e0f1360e0ab103b0a453701e596babd753d82a4e50ed07';

T _copy<T>(T value) => jsonDecode(jsonEncode(value)) as T;

/// Serves a 12.2 server's LiveTvOptions and records each call.
class _FakeLiveTvApi extends Fake implements AdminLiveTvApi {
  _FakeLiveTvApi() {
    config = jsonDecode(
      File('test/fixtures/admin/live_tv_options.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    (config['ListingProviders'] as List).first['ChannelMappings'] = [
      {'Name': _tunerChannel, 'Value': 'verify.one'},
    ];
  }

  late Map<String, dynamic> config;

  /// Answers mapping calls the way Emby does.
  bool emby = false;
  final configPosts = <Map<String, dynamic>>[];
  final tunerPosts = <Map<String, dynamic>>[];
  final providerPosts = <(Map<String, dynamic>, bool, bool)>[];
  final mappingPosts = <List<String>>[];
  final lineupCalls = <String?>[];
  final deletedTuners = <String>[];
  final deletedProviders = <String>[];

  @override
  Future<Map<String, dynamic>> getLiveTvConfiguration() async => _copy(config);

  @override
  Future<void> updateLiveTvConfiguration(Map<String, dynamic> value) async {
    configPosts.add(_copy(value));
    config = _copy(value);
  }

  @override
  Future<List<Map<String, dynamic>>> getTunerHostTypes() async => [
        {'Name': 'HD Homerun', 'Id': 'hdhomerun'},
        {'Name': 'M3U Tuner', 'Id': 'm3u'},
      ];

  @override
  Future<Map<String, dynamic>> addTunerHost(Map<String, dynamic> info) async {
    tunerPosts.add(_copy(info));
    return info;
  }

  @override
  Future<void> removeTunerHost(String id) async => deletedTuners.add(id);

  @override
  Future<Map<String, dynamic>> getDefaultListingProvider() async => {
        'EnabledTuners': [],
        'EnableAllTuners': true,
        'NewsCategories': ['news', 'journalism', 'documentary', 'current affairs'],
        'SportsCategories': ['sports', 'basketball', 'baseball', 'football'],
        'KidsCategories': ['kids', 'family', 'children', 'childrens', 'disney'],
        'MovieCategories': ['movie'],
        'ChannelMappings': [],
      };

  @override
  Future<Map<String, dynamic>> addListingProvider(
    Map<String, dynamic> providerInfo, {
    bool validateLogin = false,
    bool validateListings = false,
  }) async {
    providerPosts.add((_copy(providerInfo), validateLogin, validateListings));
    return {...providerInfo, 'Id': providerInfo['Id'] ?? 'new'};
  }

  @override
  Future<void> removeListingProvider(String id) async =>
      deletedProviders.add(id);

  @override
  Future<List<Map<String, dynamic>>> getSchedulesDirectCountries() async => [
        {'fullName': 'United States', 'shortName': 'USA'},
      ];

  @override
  Future<List<Map<String, dynamic>>> getListingProviderLineups({
    String? providerId,
    required String location,
    required String country,
  }) async {
    lineupCalls.add(providerId);
    return [
      {'Name': 'Antenna', 'Id': 'USA-OTA-12345'},
    ];
  }

  @override
  Future<Map<String, dynamic>> getChannelMappingOptions(String id) async =>
      emby ? {'ProviderChannels': _providerChannels} : {
        'TunerChannels': [
          {
            'Name': '101 Verify One',
            'ProviderChannelName': 'Verify One',
            'ProviderChannelId': 'verify.one',
            'Id': _tunerChannel,
          },
        ],
        'ProviderChannels': _providerChannels,
        'Mappings': [],
        'ProviderName': 'XmlTV',
      };

  @override
  Future<Map<String, dynamic>> setChannelMapping(
    String providerId,
    String tunerChannelId,
    String providerChannelId,
  ) async {
    mappingPosts.add([providerId, tunerChannelId, providerChannelId]);
    if (emby) return {'IsManualMapping': true};
    return {
      'Name': '101 Verify One',
      'ProviderChannelName': 'Verify Two',
      'ProviderChannelId': providerChannelId,
      'Id': tunerChannelId,
    };
  }
}

const _providerChannels = [
  {'Name': 'Verify Two', 'Id': 'verify.two'},
  {'Name': 'Verify One', 'Id': 'verify.one'},
];

const _managementId = '533330de911a4c9b9fc21f1712a6f14b_hdhr_1';

class _FakeEmbyApi extends Fake implements EmbyAdminApi {
  @override
  Future<PremiereStatus> getPremiereStatus() async =>
      const PremiereStatus(isActive: false, hasKey: false);

  @override
  Future<List<Map<String, dynamic>>> getAvailableListingProviders({
    String? country,
  }) async => [
        {
          'Name': 'Emby Guide Data',
          'Id': 'embygn',
          'SetupUrl': 'configurationpage?name=embyguidedata',
        },
        {'Name': 'XmlTV', 'Id': 'xmltv', 'SetupUrl': 'configurationpage?name=xmltv'},
      ];

  @override
  Future<Map<String, dynamic>> getManagedChannels({
    int startIndex = 0,
    int limit = 100,
  }) async => {
        'Items': [
          {
            'Id': '80854',
            'Name': 'USA Disney Junior',
            'ManagementId': _managementId,
            'Disabled': false,
            'SortIndexNumber': 0,
            'ChannelNumber': '1',
            'ListingsProviderId': _xmltvId,
            'ListingsChannelId': 'verify.one',
            'ListingsChannelName': 'Verify One',
          },
        ],
        'TotalRecordCount': 1,
      };
}

class _FakeSystemApi extends Fake implements AdminSystemApi {
  @override
  Future<List<Map<String, dynamic>>> getCountries() async => [
        {
          'Name': 'US',
          'DisplayName': 'United States',
          'TwoLetterISORegionName': 'US',
          'ThreeLetterISORegionName': 'USA',
        },
      ];
}

void main() {
  late _FakeLiveTvApi api;
  late _MockMediaServerClient client;
  late AppLocalizations l10n;
  // What the ScheduledTasksInfo feed holds.
  var tasks = <TaskInfo>[];

  setUp(() async {
    tasks = [];
    api = _FakeLiveTvApi();
    client = _MockMediaServerClient();
    when(() => client.adminLiveTvApi).thenReturn(api);
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() async {
    AdminDraft.active.value = null;
    AdminSettingAnchor.pending.value = null;
    await GetIt.instance.reset();
  });

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1200, 2400),
    bool settle = true,
    bool onEmby = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminTasksProvider.overrideWith((ref) => Stream.value(tasks)),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: onEmby
                ? const AdminServerScope(
                    serverType: ServerType.emby,
                    child: AdminLiveTvScreen(),
                  )
                : const AdminLiveTvScreen(),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // A running task spins forever, so settling never ends.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
  }

  Future<void> openRecordings(WidgetTester tester) async {
    await tester.tap(find.text(l10n.adminLiveTvTabRecordings));
    await tester.pumpAndSettle();
  }

  Finder row(String label) => find.descendant(
        of: find
            .ancestor(of: find.text(label), matching: find.byType(Padding))
            .first,
        matching: find.byType(TextFormField),
      );

  Finder field(String label) => find.widgetWithText(TextField, label);

  group('recordings', () {
    testWidgets('edits of each control type save onto a fresh livetv', (
      tester,
    ) async {
      await pump(tester);
      await openRecordings(tester);

      await tester.tap(find.byType(DropdownButtonFormField<int?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4').last);
      await tester.pumpAndSettle();
      await tester.enterText(row(l10n.adminLiveTvRecordingPath), '/rec');
      await tester.enterText(row(l10n.adminLiveTvStartWhenPossible), '1.5');
      await tester.tap(find.text(l10n.adminSaveRecordingNfo));
      await tester.pump();

      // A tuner added elsewhere meanwhile must survive the save.
      api.config['TunerHosts'] = [
        ...api.config['TunerHosts'] as List,
        {'Id': 'other', 'Type': 'hdhomerun'},
      ];
      expect(await AdminDraft.active.value!.save(), isTrue);

      final posted = api.configPosts.single;
      expect(posted['GuideDays'], 4);
      expect(posted['RecordingPath'], '/rec');
      expect(posted['PrePaddingSeconds'], 90);
      expect(posted['SaveRecordingNFO'], isFalse);
      expect((posted['TunerHosts'] as List).length, 2);
      expect(posted['RecordingPostProcessorArguments'], '"{path}"');
    });

    testWidgets('padding shows seconds over 60 without truncating', (
      tester,
    ) async {
      api.config['PrePaddingSeconds'] = 90;
      await pump(tester);
      await openRecordings(tester);

      expect(find.widgetWithText(TextFormField, '1.5'), findsOneWidget);
    });

    testWidgets('a stored guide days value is selected with no extra entry', (
      tester,
    ) async {
      api.config['GuideDays'] = 6;
      await pump(tester);
      await openRecordings(tester);

      final dropdown = tester.widget<DropdownButton<int?>>(
        find.byType(DropdownButton<int?>),
      );
      expect(dropdown.value, 6);
      expect(dropdown.items!.length, 15);
    });

    testWidgets('a search result for a recording row opens that tab', (
      tester,
    ) async {
      AdminSettingAnchor.pending.value = 'live-tv.GuideDays';
      await pump(tester);
      expect(find.text(l10n.adminLiveTvGuideDays), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('the page has no save button of its own', (tester) async {
      await pump(tester);
      await openRecordings(tester);
      expect(find.widgetWithText(FilledButton, l10n.save), findsNothing);
    });
  });

  group('tuners', () {
    testWidgets('there is no reset button', (tester) async {
      await pump(tester);
      expect(find.byIcon(Icons.restart_alt), findsNothing);
      expect(find.text('Verify M3U'), findsOneWidget);
      expect(find.text('http://169.254.1.2:9124/playlist.m3u'), findsOneWidget);
    });

    testWidgets('delete asks first', (tester) async {
      await pump(tester);
      final delete = find.descendant(
        of: find.widgetWithText(ListTile, 'Verify M3U'),
        matching: find.byIcon(Icons.delete_outline),
      );

      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();
      expect(api.deletedTuners, isEmpty);

      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.delete).last);
      await tester.pumpAndSettle();
      expect(api.deletedTuners, [_tunerId]);
    });

    testWidgets('a blank fallback bitrate is sent as 30 Mbps, never null', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text(l10n.adminLiveTvAddTuner));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('M3U Tuner').last);
      await tester.pumpAndSettle();
      await tester.enterText(field(l10n.adminTunerFileOrUrl), '/tv.m3u');
      await tester.enterText(field(l10n.adminTunerFallbackBitrate), '');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, l10n.save));
      await tester.pumpAndSettle();

      final posted = api.tunerPosts.single;
      expect(posted['Type'], 'm3u');
      expect(posted['Url'], '/tv.m3u');
      expect(posted['FallbackMaxStreamingBitrate'], 30000000);
      expect(posted.containsKey('Id'), isFalse);
    });

    testWidgets('editing a tuner locks its type and keeps its id', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('Verify M3U'));
      await tester.pumpAndSettle();

      final type = tester.widget<DropdownButton<String>>(
        find.byType(DropdownButton<String>),
      );
      expect(type.onChanged, isNull);

      await tester.tap(find.widgetWithText(FilledButton, l10n.save));
      await tester.pumpAndSettle();
      expect(api.tunerPosts.single['Id'], _tunerId);
      expect(api.tunerPosts.single['FallbackMaxStreamingBitrate'], 30000000);
      expect(api.tunerPosts.single['TunerCount'], 2);
    });

    testWidgets('the tuner form is full screen on a narrow window', (
      tester,
    ) async {
      await pump(tester, size: const Size(400, 900));
      await tester.tap(find.text(l10n.adminLiveTvAddTuner));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('guide providers', () {
    testWidgets('a running guide refresh shows its progress', (tester) async {
      tasks = [
        const TaskInfo(
          id: 'guide',
          name: 'Refresh Guide',
          key: 'RefreshGuide',
          state: 'Running',
          currentProgressPercentage: 40,
        ),
      ];
      await pump(tester, settle: false);

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 0.4);
      final refresh = find.ancestor(
        of: find.text(l10n.adminLiveTvRefreshGuide),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(tester.widget<ButtonStyleButton>(refresh).onPressed, isNull);
    });

    testWidgets('editing an XMLTV provider keeps its channel mappings', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text(l10n.adminProviderXmltv));
      await tester.pumpAndSettle();
      await tester.enterText(field(l10n.adminXmltvPath), '/new/guide.xml');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, l10n.save));
      await tester.pumpAndSettle();

      final (body, validateLogin, validateListings) = api.providerPosts.single;
      expect(body['Id'], _xmltvId);
      expect(body['Path'], '/new/guide.xml');
      expect(body['ChannelMappings'], [
        {'Name': _tunerChannel, 'Value': 'verify.one'},
      ]);
      expect(body['EnableAllTuners'], isTrue);
      expect(body['EnabledTuners'], isEmpty);
      expect(validateLogin, isFalse);
      expect(validateListings, isTrue);
    });

    testWidgets('a new XMLTV provider starts from the server default', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text(l10n.adminLiveTvAddProvider));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.adminProviderXmltv).last);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'movie'), findsOneWidget);
      await tester.enterText(field(l10n.adminXmltvPath), '/guide.xml');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, l10n.save));
      await tester.pumpAndSettle();

      final (body, _, _) = api.providerPosts.single;
      expect(body.containsKey('Id'), isFalse);
      expect(body['Type'], 'xmltv');
      expect(body['KidsCategories'], [
        'kids',
        'family',
        'children',
        'childrens',
        'disney',
      ]);
    });

    testWidgets('a mapping posts one tuner and provider channel pair', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byTooltip(l10n.adminLiveTvMapChannels));
      await tester.pumpAndSettle();
      expect(find.text('Verify One - XmlTV'), findsOneWidget);

      await tester.tap(find.text('101 Verify One'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verify Two'));
      await tester.pumpAndSettle();

      expect(api.mappingPosts, [
        [_xmltvId, _tunerChannel, 'verify.two'],
      ]);
      expect(find.text('Verify Two - XmlTV'), findsOneWidget);
    });

    testWidgets('Schedules Direct lists lineups with the stored login', (
      tester,
    ) async {
      api.config['ListingProviders'] = [
        {
          'Id': 'sd1',
          'Type': 'SchedulesDirect',
          'Username': 'user',
          'Password': 'stored',
          'ZipCode': '12345',
          'Country': 'USA',
          'ListingsId': 'USA-OTA-12345',
          'EnableAllTuners': false,
          'EnabledTuners': [_tunerId],
          'ChannelMappings': [
            {'Name': 'a', 'Value': 'b'},
          ],
        },
      ];
      await pump(tester);
      await tester.tap(find.text(l10n.adminProviderSchedulesDirect));
      await tester.pumpAndSettle();

      expect(api.lineupCalls, ['sd1']);
      expect(api.providerPosts, isEmpty);
      expect(find.text('Antenna'), findsOneWidget);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );

      await tester.tap(find.widgetWithText(FilledButton, l10n.save));
      await tester.pumpAndSettle();

      final (body, validateLogin, validateListings) = api.providerPosts.single;
      expect(validateLogin, isFalse);
      expect(validateListings, isTrue);
      expect(body['Password'], 'stored');
      expect(body['ListingsId'], 'USA-OTA-12345');
      expect(body['EnabledTuners'], [_tunerId]);
      expect(body['ChannelMappings'], [
        {'Name': 'a', 'Value': 'b'},
      ]);
    });

    testWidgets('delete asks first', (tester) async {
      await pump(tester);
      final delete = find.descendant(
        of: find.widgetWithText(ListTile, l10n.adminProviderXmltv),
        matching: find.byIcon(Icons.delete_outline),
      );
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(find.text(l10n.adminLiveTvDeleteProviderConfirm), findsOneWidget);
      await tester.tap(find.text(l10n.delete).last);
      await tester.pumpAndSettle();
      expect(api.deletedProviders, [_xmltvId]);
    });
  });

  group('on Emby', () {
    setUp(() {
      api.emby = true;
      // An Emby 4.9 server's livetv configuration.
      api.config = {
        'WakeServer': true,
        'TunerHosts': [
          {
            'Id': _tunerId,
            'Url': 'http://169.254.1.2:9124/playlist.m3u',
            'Type': 'm3u',
            'ImportFavoritesOnly': false,
            'AllowHWTranscoding': true,
            'TunerCount': 0,
          },
        ],
        'ListingProviders': [
          {
            'Id': _xmltvId,
            'Type': 'xmltv',
            'Path': 'http://169.254.1.2:9124/guide.xml',
            'EnabledTuners': [],
            'EnableAllTuners': true,
            'ChannelMappings': [],
          },
        ],
        'ChannelOptions': [],
        'PrePaddingSeconds': 0,
        'PostPaddingSeconds': 0,
        'RecordingPostProcessorArguments': '"{path}"',
      };
      when(() => client.embyAdminApi).thenReturn(_FakeEmbyApi());
      when(() => client.adminSystemApi).thenReturn(_FakeSystemApi());
    });

    testWidgets('the guide menu offers Emby sources, with a Premiere note', (
      tester,
    ) async {
      await pump(tester, onEmby: true);
      expect(find.text(l10n.adminPremiereNoteLiveTv), findsOneWidget);

      await tester.tap(find.text(l10n.adminLiveTvAddProvider));
      await tester.pumpAndSettle();
      expect(find.text(l10n.adminProviderEmbyGuide), findsOneWidget);
      expect(find.text(l10n.adminProviderSchedulesDirect), findsNothing);
    });

    testWidgets('Emby Guide Data saves with a three letter country', (
      tester,
    ) async {
      await pump(tester, onEmby: true);
      await tester.tap(find.text(l10n.adminLiveTvAddProvider));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.adminProviderEmbyGuide));
      await tester.pumpAndSettle();
      expect(find.text(l10n.adminSdUsername), findsNothing);

      await tester.tap(find.text(l10n.adminSdCountrySelect));
      await tester.pumpAndSettle();
      await tester.tap(find.text('United States').last);
      await tester.pumpAndSettle();
      await tester.enterText(field(l10n.adminSdPostalCode), '90210');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(api.lineupCalls, ['']);

      await tester.tap(find.text(l10n.adminLiveTvSdLineup));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Antenna').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, l10n.save));
      await tester.pumpAndSettle();

      final (body, validateLogin, validateListings) = api.providerPosts.single;
      expect(body['Type'], 'embygn');
      expect(body['Country'], 'USA');
      expect(body['ZipCode'], '90210');
      expect(body['ListingsId'], 'USA-OTA-12345');
      expect(validateLogin, isFalse);
      expect(validateListings, isTrue);
    });

    testWidgets('a mapping names the channel by its ManagementId', (
      tester,
    ) async {
      await pump(tester, onEmby: true);
      await tester.tap(find.byTooltip(l10n.adminLiveTvMapChannels));
      await tester.pumpAndSettle();
      expect(find.text('Verify One'), findsOneWidget);

      await tester.tap(find.text('1 USA Disney Junior'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verify Two'));
      await tester.pumpAndSettle();

      expect(api.mappingPosts, [
        [_xmltvId, _managementId, 'verify.two'],
      ]);
      expect(find.text('Verify Two'), findsOneWidget);
    });

    testWidgets('the tuner form has only the switches Emby keeps', (
      tester,
    ) async {
      await pump(tester, onEmby: true);
      await tester.tap(find.text(l10n.adminTunerTypeM3u));
      await tester.pumpAndSettle();

      expect(find.text(l10n.adminTunerAllowHwTranscoding), findsOneWidget);
      expect(find.text(l10n.adminTunerAllowFmp4), findsNothing);
      expect(find.text(l10n.adminTunerFallbackBitrate), findsNothing);
    });

    testWidgets('recordings show Wake server and no NFO rows', (tester) async {
      await pump(tester, onEmby: true);
      await openRecordings(tester);
      expect(find.text(l10n.adminSaveRecordingNfo), findsNothing);

      await tester.tap(find.text(l10n.adminLiveTvWakeServer));
      await tester.pump();
      expect(await AdminDraft.active.value!.save(), isTrue);
      expect(api.configPosts.single['WakeServer'], isFalse);
      expect(api.configPosts.single.containsKey('SaveRecordingNFO'), isFalse);
    });
  });
}
