import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/admin_draft.dart';
import 'package:moonfin/ui/screens/admin/settings/admin_networking_screen.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

/// Serves GET /System/Configuration/network as Jellyfin 12.2 returns it and
/// records every post.
class _FakeSystemApi extends Fake implements AdminSystemApi {
  Map<String, dynamic> server = {
    'BaseUrl': '',
    'EnableHttps': false,
    'RequireHttps': false,
    'CertificatePath': '/config/ssl/server.pfx',
    'CertificatePassword': 'secret',
    'InternalHttpPort': 8096,
    'InternalHttpsPort': 8920,
    'PublicHttpPort': 8096,
    'PublicHttpsPort': 8920,
    'AutoDiscovery': true,
    'EnableUPnP': false,
    'EnableIPv4': true,
    'EnableIPv6': false,
    'EnableRemoteAccess': true,
    'LocalNetworkSubnets': <String>[],
    'LocalNetworkAddresses': <String>[],
    'KnownProxies': <String>[],
    'IgnoreVirtualInterfaces': true,
    'VirtualInterfaceNames': ['veth'],
    'EnablePublishedServerUriByRequest': false,
    'PublishedServerUriBySubnet': <String>[],
    'RemoteIPFilter': <String>[],
    'IsRemoteIPFilterBlacklist': false,
  };
  final posted = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> getNamedConfiguration(String key) async {
    expect(key, 'network');
    return Map<String, dynamic>.from(server);
  }

  @override
  Future<void> updateNamedConfiguration(
    String key,
    Map<String, dynamic> config,
  ) async {
    expect(key, 'network');
    posted.add(config);
    server = Map<String, dynamic>.from(config);
  }
}

class _FakeEnvironmentApi extends Fake implements AdminEnvironmentApi {
  final listed = <(String, bool?)>[];

  @override
  Future<List<Map<String, dynamic>>> getDirectoryContents(
    String path, {
    bool? includeFiles,
    bool? includeDirectories,
  }) async {
    listed.add((path, includeFiles));
    return const [];
  }
}

void main() {
  late _FakeSystemApi api;
  late _FakeEnvironmentApi env;
  late AppLocalizations l10n;

  setUp(() async {
    api = _FakeSystemApi();
    env = _FakeEnvironmentApi();
    final client = _MockMediaServerClient();
    when(() => client.adminSystemApi).thenReturn(api);
    when(() => client.adminEnvironmentApi).thenReturn(env);
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() async {
    AdminDraft.active.value = null;
    await GetIt.instance.reset();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: AdminNetworkingScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder row(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(Padding)).first;

  Finder field(String label) =>
      find.descendant(of: row(label), matching: find.byType(TextField)).first;

  testWidgets('every control type saves into the full network config', (
    tester,
  ) async {
    await pump(tester);

    await tester.enterText(field(l10n.adminNetworkingLocalHttpPort), '8097');
    await tester.enterText(field(l10n.adminNetworkingBaseUrl), '/jellyfin');
    await tester.tap(find.text(l10n.adminNetworkingEnableIpv6));
    await tester.pump();

    await tester.enterText(field(l10n.adminNetworkingKnownProxies), '10.0.0.1');
    await tester.tap(
      find.descendant(
        of: row(l10n.adminNetworkingKnownProxies),
        matching: find.byIcon(Icons.add),
      ),
    );
    await tester.pump();

    await tester.tap(find.text(l10n.adminNetworkingWhitelist));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminNetworkingBlacklist).last);
    await tester.pumpAndSettle();

    expect(await AdminDraft.active.value!.save(), isTrue);
    final body = api.posted.single;
    expect(body['InternalHttpPort'], 8097);
    expect(body['BaseUrl'], '/jellyfin');
    expect(body['EnableIPv6'], isTrue);
    expect(body['KnownProxies'], ['10.0.0.1']);
    expect(body['IsRemoteIPFilterBlacklist'], isTrue);
    // Keys the page doesn't show go back too, or the server would reset them
    // to defaults.
    expect(body['EnableUPnP'], isFalse);
    expect(body['VirtualInterfaceNames'], ['veth']);
    expect(body.containsKey('HttpServerPortNumber'), isFalse);
    expect(body.containsKey('HttpsPortNumber'), isFalse);
  });

  // Saving 0 for an empty port would bring the server back on no port at all.
  testWidgets('a cleared port saves the default port, never 0', (
    tester,
  ) async {
    api.server = {...api.server, 'InternalHttpPort': 8097};
    await pump(tester);
    await tester.enterText(field(l10n.adminNetworkingLocalHttpPort), '');
    await tester.pump();

    expect(await AdminDraft.active.value!.save(), isTrue);
    expect(api.posted.single['InternalHttpPort'], 8096);
  });

  testWidgets('the certificate password is obscured', (tester) async {
    await pump(tester);
    final password = tester.widget<TextField>(
      field(l10n.adminNetworkingCertPassword),
    );
    expect(password.obscureText, isTrue);
  });

  testWidgets('the certificate browser lists files', (tester) async {
    await pump(tester);
    await tester.tap(
      find.descendant(
        of: row(l10n.adminNetworkingCustomCertPath),
        matching: find.byIcon(Icons.folder_open),
      ),
    );
    await tester.pumpAndSettle();

    expect(env.listed, [('/config/ssl/server.pfx', true)]);
  });

  // Keying the field on its value would rebuild it once the first keystroke
  // makes the page dirty, and drop focus.
  testWidgets('the certificate path keeps focus while typing', (tester) async {
    await pump(tester);
    final path = field(l10n.adminNetworkingCustomCertPath);
    await tester.enterText(path, '/config/ssl/other.pfx');
    await tester.pump();

    final input = tester.widget<EditableText>(
      find.descendant(of: path, matching: find.byType(EditableText)),
    );
    expect(input.focusNode.hasFocus, isTrue);
  });

  testWidgets('separate internal and external URIs keep subnet entries', (
    tester,
  ) async {
    api.server['PublishedServerUriBySubnet'] = [
      'internal=http://10.0.0.5:8096',
      'external=https://media.example.com',
      '192.168.1.0/24=http://192.168.1.5:8096',
    ];
    await pump(tester);

    expect(find.text(l10n.adminNetworkingInternalUri), findsOneWidget);
    expect(find.text('http://10.0.0.5:8096'), findsOneWidget);
    expect(find.text('192.168.1.0/24=http://192.168.1.5:8096'), findsOneWidget);

    await tester.enterText(
      field(l10n.adminNetworkingExternalUri),
      'https://jf.example.com',
    );
    await AdminDraft.active.value!.save();
    expect(api.posted.last['PublishedServerUriBySubnet'], [
      'internal=http://10.0.0.5:8096',
      'external=https://jf.example.com',
      '192.168.1.0/24=http://192.168.1.5:8096',
    ]);
  });

  testWidgets('one URI for both is sent as all=', (tester) async {
    await pump(tester);
    expect(find.text(l10n.adminNetworkingPublishedUri), findsOneWidget);

    await tester.enterText(
      field(l10n.adminNetworkingPublishedUri),
      'https://media.example.com',
    );
    await AdminDraft.active.value!.save();
    expect(api.posted.last['PublishedServerUriBySubnet'], [
      'all=https://media.example.com',
    ]);

    // Turning the switch off shows empty internal and external fields.
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.adminNetworkingSamePublishedUri));
    await tester.pump();
    expect(find.text(l10n.adminNetworkingInternalUri), findsOneWidget);
    expect(find.text('https://media.example.com'), findsNothing);
  });

  testWidgets('loads clean, with no save button of its own', (tester) async {
    await pump(tester);
    expect(AdminDraft.active.value!.isDirty, isFalse);
    expect(find.widgetWithText(FilledButton, l10n.save), findsNothing);
  });
}
