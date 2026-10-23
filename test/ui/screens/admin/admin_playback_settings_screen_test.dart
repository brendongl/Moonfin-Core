import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/admin_draft.dart';
import 'package:moonfin/ui/screens/admin/settings/admin_playback_settings_screen.dart';
import 'package:moonfin/ui/screens/admin/widgets/admin_settings_search.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

/// A 12.2 server's EncodingOptions.
Map<String, dynamic> _fixture() =>
    jsonDecode(File('test/fixtures/admin/encoding_options.json').readAsStringSync())
        as Map<String, dynamic>;

/// Serves the named `encoding` config, records reads and posts, and can change
/// underneath the page.
class _FakeSystemApi extends Fake implements AdminSystemApi {
  Map<String, dynamic> encoding = _fixture();
  final reads = <String>[];
  final posted = <(String, Map<String, dynamic>)>[];

  @override
  Future<Map<String, dynamic>> getNamedConfiguration(String key) async {
    reads.add(key);
    return jsonDecode(jsonEncode(encoding)) as Map<String, dynamic>;
  }

  @override
  Future<void> updateNamedConfiguration(
    String key,
    Map<String, dynamic> config,
  ) async {
    posted.add((key, config));
    encoding = Map<String, dynamic>.from(config);
  }
}

void main() {
  late _FakeSystemApi api;
  late AppLocalizations l10n;

  setUp(() async {
    api = _FakeSystemApi();
    final client = _MockMediaServerClient();
    when(() => client.adminSystemApi).thenReturn(api);
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() async {
    AdminDraft.active.value = null;
    await GetIt.instance.reset();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: AdminPlaybackSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder row(String key) => find.byWidgetPredicate(
    (w) => w is AdminSettingAnchor && w.id == 'transcoding.$key',
  );

  Finder dropdown(String key) => find.descendant(
    of: row(key),
    matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
  );

  Finder field(String key) =>
      find.descendant(of: row(key), matching: find.byType(TextFormField));

  String text(WidgetTester tester, String key) => tester
      .widget<EditableText>(
        find.descendant(of: row(key), matching: find.byType(EditableText)),
      )
      .controller
      .text;

  Future<void> pick(WidgetTester tester, String key, String item) async {
    await tester.ensureVisible(dropdown(key));
    await tester.pumpAndSettle();
    await tester.tap(dropdown(key));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String key, String value) async {
    await tester.ensureVisible(field(key));
    await tester.enterText(field(key), value);
    await tester.pump();
  }

  Future<Map<String, dynamic>> save() async {
    expect(await AdminDraft.active.value!.save(), isTrue);
    expect(api.posted.single.$1, 'encoding');
    return api.posted.single.$2;
  }

  testWidgets('the Auto preset posts auto, not an empty string', (
    tester,
  ) async {
    api.encoding['EncoderPreset'] = 'fast';
    await pump(tester);

    await pick(tester, 'EncoderPreset', l10n.adminPlaybackAutoOption);
    expect((await save())['EncoderPreset'], 'auto');
  });

  testWidgets('a stored auto preset shows as Auto', (tester) async {
    await pump(tester);
    final preset = tester.widget<DropdownButtonFormField<String>>(
      dropdown('EncoderPreset'),
    );
    expect(preset.initialValue, 'auto');
  });

  testWidgets('rows show and hide per hardware type', (
    tester,
  ) async {
    const always = ['AllowHevcEncoding', 'EncodingThreadCount', 'FallbackFontPath'];
    const cases = <String, (List<String>, List<String>, List<String>)>{
      // type: (shown rows, hidden rows, codec chips)
      'none': (
        ['TonemappingAlgorithm', 'TonemappingRange', 'TonemappingParam'],
        [
          'HardwareDecodingCodecs', 'EnableHardwareEncoding',
          'EnableDecodingColorDepth10Hevc', 'EnableTonemapping',
          'TonemappingMode', 'PreferSystemNativeHwDecoder', 'VaapiDevice',
        ],
        [],
      ),
      'nvenc': (
        [
          'EnableEnhancedNvdecDecoder', 'EnableDecodingColorDepth10Hevc',
          'EnableDecodingColorDepth12HevcRext', 'EnableHardwareEncoding',
          'EnableTonemapping', 'TonemappingMode',
        ],
        [
          'PreferSystemNativeHwDecoder', 'EnableIntelLowPowerH264HwEncoder',
          'EnableVppTonemapping', 'QsvDevice',
        ],
        ['H.264', 'HEVC', 'MPEG-2', 'MPEG-4', 'VC-1', 'VP8', 'VP9', 'AV1'],
      ),
      'qsv': (
        [
          'QsvDevice', 'PreferSystemNativeHwDecoder',
          'EnableIntelLowPowerHevcHwEncoder', 'EnableVppTonemapping',
          'VppTonemappingContrast', 'EnableDecodingColorDepth10HevcRext',
        ],
        ['EnableEnhancedNvdecDecoder', 'VaapiDevice'],
        ['H.264', 'HEVC', 'MPEG-2', 'VC-1', 'VP8', 'VP9', 'AV1'],
      ),
      'rkmpp': (
        ['EnableDecodingColorDepth10Vp9', 'EnableTonemapping'],
        ['EnableDecodingColorDepth10HevcRext', 'PreferSystemNativeHwDecoder'],
        ['H.264', 'HEVC', 'MPEG-1', 'MPEG-2', 'MPEG-4', 'VP8', 'VP9', 'AV1'],
      ),
      'videotoolbox': (
        ['EnableVideoToolboxTonemapping', 'TonemappingMode'],
        ['EnableDecodingColorDepth10Hevc', 'EnableVppTonemapping'],
        ['H.264', 'HEVC', 'VP8', 'VP9', 'AV1'],
      ),
      'v4l2m2m': (
        ['EnableHardwareEncoding'],
        [
          'TonemappingAlgorithm', 'TonemappingRange', 'TonemappingDesat',
          'EnableTonemapping', 'EnableDecodingColorDepth10Hevc',
        ],
        ['H.264'],
      ),
    };
    const allChips = [
      'H.264', 'HEVC', 'MPEG-1', 'MPEG-2', 'MPEG-4', 'VC-1', 'VP8', 'VP9', 'AV1',
    ];

    for (final MapEntry(key: type, value: (shown, hidden, chips))
        in cases.entries) {
      api.encoding['HardwareAccelerationType'] = type;
      await pump(tester);
      for (final key in [...always, ...shown]) {
        expect(row(key), findsOneWidget, reason: '$type shows $key');
      }
      for (final key in hidden) {
        expect(row(key), findsNothing, reason: '$type hides $key');
      }
      for (final chip in allChips) {
        expect(
          find.widgetWithText(FilterChip, chip),
          chips.contains(chip) ? findsOneWidget : findsNothing,
          reason: '$type chip $chip',
        );
      }
      AdminDraft.active.value = null;
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('picking a type and a codec posts both', (tester) async {
    await pump(tester);
    await pick(tester, 'HardwareAccelerationType', 'Nvidia NVENC');
    expect(row('EnableEnhancedNvdecDecoder'), findsOneWidget);

    final mpeg4 = find.widgetWithText(FilterChip, 'MPEG-4');
    await tester.ensureVisible(mpeg4);
    await tester.tap(mpeg4);
    await tester.pump();
    final h264 = find.widgetWithText(FilterChip, 'H.264');
    await tester.tap(h264);
    await tester.pump();

    final body = await save();
    expect(body['HardwareAccelerationType'], 'nvenc');
    expect(body['HardwareDecodingCodecs'], ['vc1', 'mpeg4']);
  });

  testWidgets('a device path does not move into the other device field', (
    tester,
  ) async {
    api.encoding['HardwareAccelerationType'] = 'vaapi';
    await pump(tester);
    expect(text(tester, 'VaapiDevice'), '/dev/dri/renderD128');

    await pick(tester, 'HardwareAccelerationType', 'Intel Quicksync (QSV)');
    expect(row('VaapiDevice'), findsNothing);
    expect(text(tester, 'QsvDevice'), '');
  });

  testWidgets('thread count is a dropdown with Auto -1 and Max 0', (
    tester,
  ) async {
    await pump(tester);
    final threads = tester.widget<DropdownButtonFormField<int>>(
      dropdown('EncodingThreadCount'),
    );
    expect(threads.initialValue, -1);
    expect(find.text(l10n.adminTranscodingThreadCountHelp), findsOneWidget);
    expect(find.text(l10n.adminPlaybackAutomatic), findsNothing);

    await pick(tester, 'EncodingThreadCount', l10n.adminTranscodingThreadMax);
    expect((await save())['EncodingThreadCount'], 0);
  });

  testWidgets('audio seek strategy posts the enum name', (tester) async {
    await pump(tester);
    await pick(
      tester,
      'HlsAudioSeekStrategy',
      l10n.adminTranscodingTranscodeAudio,
    );
    expect((await save())['HlsAudioSeekStrategy'], 'TranscodeAudio');
  });

  testWidgets('number fields clamp to their bounds and fall back when empty', (
    tester,
  ) async {
    await pump(tester);
    await type(tester, 'H264Crf', '60');
    await type(tester, 'SegmentKeepSeconds', '5');
    await type(tester, 'DownMixAudioBoost', '0.7');
    await type(tester, 'ThrottleDelaySeconds', '');
    await type(tester, 'TonemappingPeak', '400');
    await tester.ensureVisible(row('EnableAudioVbr'));
    await tester.tap(row('EnableAudioVbr'));
    await tester.pump();

    final body = await save();
    expect(body['H264Crf'], 51);
    expect(body['SegmentKeepSeconds'], 10);
    expect(body['DownMixAudioBoost'], 0.7);
    expect(body['ThrottleDelaySeconds'], 180);
    expect(body['TonemappingPeak'], 400.0);
    expect(body['EnableAudioVbr'], isTrue);
    // Keys the page never shows go back as they came.
    expect(body['SubtitleExtractionTimeoutMinutes'], 30);
    expect(body['AllowOnDemandMetadataBasedKeyframeExtractionForExtensions'],
        ['mkv']);
  });

  testWidgets('save re-reads encoding and keeps keys changed meanwhile', (
    tester,
  ) async {
    await pump(tester);
    await type(tester, 'H265Crf', '30');
    api.encoding = {...api.encoding, 'MaxMuxingQueueSize': 4096};

    final body = await save();
    expect(api.reads, ['encoding', 'encoding']);
    expect(body['H265Crf'], 30);
    expect(body['MaxMuxingQueueSize'], 4096);
  });

  testWidgets('the FFmpeg path is shown read only', (tester) async {
    await pump(tester);
    final ffmpeg = tester.widget<TextField>(
      find.descendant(
        of: row('EncoderAppPathDisplay'),
        matching: find.byType(TextField),
      ),
    );
    expect(ffmpeg.enabled, isFalse);
    expect(text(tester, 'EncoderAppPathDisplay'),
        '/usr/lib/jellyfin-ffmpeg/ffmpeg');
  });

  testWidgets('the page has no save button of its own', (tester) async {
    await pump(tester);
    expect(find.widgetWithText(FilledButton, l10n.save), findsNothing);
  });
}
