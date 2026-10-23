import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/database/offline_database.dart';
import 'package:moonfin/data/repositories/offline_repository.dart';
import 'package:moonfin/data/services/download_notification_service.dart';
import 'package:moonfin/data/services/download_service.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RowRepository extends OfflineRepository {
  _RowRepository(super.db, this.row);

  final DownloadedItem row;

  @override
  Future<DownloadedItem?> getItem(String itemId) async =>
      itemId == row.itemId ? row : null;
}

class _FakeClient implements MediaServerClient {
  _FakeClient(this.baseUrl, [this.serverType = ServerType.jellyfin]);

  @override
  final String baseUrl;

  @override
  final ServerType serverType;

  @override
  String? get accessToken => 'test-token';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late OfflineDatabase db;
  late Directory tempDir;
  late HttpServer server;
  late List<String> requests;
  late DownloadService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    final store = PreferenceStore();
    await store.init();

    tempDir = await Directory.systemTemp.createTemp('moonfin_sub_repair');
    db = OfflineDatabase(DatabaseConnection(NativeDatabase.memory()));

    requests = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      requests.add(request.uri.path);
      request.response
        ..write('1\n00:00:01,000 --> 00:00:02,000\nHi\n')
        ..close();
    });

    final moviePath = '${tempDir.path}/Movie.mkv';
    await File(moviePath).writeAsString('video');
    // Index 3 is an image subtitle the server can't extract and index 4
    // already has its file, so only indexes 2 and 5 should be fetched. Index 5
    // is PGS flagged the way Emby flags it.
    await File('${tempDir.path}/Movie_sub_4.srt').writeAsString('kept');

    final row = DownloadedItem(
      itemId: 'movie-1',
      serverId: 'server-1',
      type: 'Movie',
      name: 'Movie',
      localFilePath: moviePath,
      metadataJson: jsonEncode({
        'Id': 'movie-1',
        'Type': 'Movie',
        'MediaSources': [
          {'Id': 'source-1'},
        ],
        'MediaStreams': [
          {'Type': 'Video', 'Index': 0},
          {
            'Type': 'Subtitle',
            'Index': 2,
            'Codec': 'subrip',
            'IsExternal': true,
          },
          {
            'Type': 'Subtitle',
            'Index': 3,
            'Codec': 'dvdsub',
            'SupportsExternalStream': false,
          },
          {
            'Type': 'Subtitle',
            'Index': 4,
            'Codec': 'subrip',
            'SupportsExternalStream': true,
          },
          {
            'Type': 'Subtitle',
            'Index': 5,
            'Codec': 'PGSSUB',
            'SupportsExternalStream': false,
          },
        ],
      }),
      downloadStatus: 2,
      downloadProgress: 1,
      fileSizeBytes: 5,
      playbackPositionTicks: 0,
      progressSynced: true,
      qualityPreset: 'original',
      downloadSource: 'manual',
    );

    final getIt = GetIt.instance;
    getIt.registerSingleton<UserPreferences>(UserPreferences(store));
    getIt.registerSingleton<OfflineRepository>(_RowRepository(db, row));

    service = DownloadService(
      _FakeClient('http://127.0.0.1:${server.port}'),
      DownloadNotificationService(),
    );
  });

  tearDown(() async {
    service.dispose();
    await server.close(force: true);
    await GetIt.instance.reset();
    await db.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('fetches only the missing subtitles, once per run', () async {
    await service.restoreMissingSubtitles('movie-1');

    expect(requests, [
      '/Videos/movie-1/source-1/Subtitles/2/0/Stream.srt',
      '/Videos/movie-1/source-1/Subtitles/5/0/Stream.pgssub',
    ]);
    expect(
      await File('${tempDir.path}/Movie_sub_2.srt').readAsString(),
      contains('Hi'),
    );
    expect(File('${tempDir.path}/Movie_sub_5.pgssub').existsSync(), isTrue);
    expect(
      await File('${tempDir.path}/Movie_sub_4.srt').readAsString(),
      'kept',
    );

    await File('${tempDir.path}/Movie_sub_2.srt').delete();
    await service.restoreMissingSubtitles('movie-1');
    expect(requests, hasLength(2));
  });

  test('asks Emby for PGS as .sup', () async {
    final emby = DownloadService(
      _FakeClient('http://127.0.0.1:${server.port}', ServerType.emby),
      DownloadNotificationService(),
    );
    addTearDown(emby.dispose);

    await emby.restoreMissingSubtitles('movie-1');

    expect(
      requests,
      contains('/Videos/movie-1/source-1/Subtitles/5/0/Stream.sup'),
    );
    expect(File('${tempDir.path}/Movie_sub_5.pgssub').existsSync(), isTrue);
  });

  test('ignores items that are not downloaded', () async {
    await service.restoreMissingSubtitles('other');
    expect(requests, isEmpty);
  });
}
