import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';

import 'platform_detection.dart';

bool _sweeping = false;
DateTime? _lastSweep;

// Point cached_network_image at a cache manager with a shorter stale period and
// a higher object count than the library default. The object count is a soft
// cap only, the real ceiling is the byte budget enforced by
// enforceImageCacheBudget. Files stay in the library's default directory so an
// existing cache is never orphaned on update.
Future<void> configureImageDiskCache() async {
  try {
    final key = DefaultCacheManager.key;
    const stalePeriod = Duration(days: 14);
    const maxObjects = 600;
    Config config;
    if (PlatformDetection.isAppleTV) {
      final cacheDir = await getApplicationCacheDirectory();
      config = Config(
        key,
        stalePeriod: stalePeriod,
        maxNrOfCacheObjects: maxObjects,
        fileService: ImageFileService(),
        repo: JsonCacheInfoRepository.withFile(
          File('${cacheDir.path}/$key.json'),
        ),
      );
    } else {
      config = Config(
        key,
        stalePeriod: stalePeriod,
        maxNrOfCacheObjects: maxObjects,
        fileService: ImageFileService(),
      );
    }
    // Deliberately a plain CacheManager: nothing asks the disk layer to resize,
    // and if anything ever does, this trips an assert rather than silently
    // storing a second re-encoded copy of every image.
    CachedNetworkImageProvider.defaultCacheManager = CacheManager(config);
  } catch (_) {}
}

// Trim the image cache directory to [budgetBytes] by deleting the least recently
// written files first. A missing file is a cache miss the manager re-downloads,
// so deleting directly is safe. Best effort only, so a failure never blocks.
Future<void> enforceImageCacheBudget(
  int budgetBytes, {
  bool throttle = false,
}) async {
  if (budgetBytes <= 0 || _sweeping) return;
  final now = DateTime.now();
  if (throttle &&
      _lastSweep != null &&
      now.difference(_lastSweep!) < const Duration(minutes: 3)) {
    return;
  }
  _sweeping = true;
  _lastSweep = now;
  try {
    final temp = await getTemporaryDirectory();
    final dir = Directory('${temp.path}/${DefaultCacheManager.key}');
    if (!await dir.exists()) return;

    final entries = <({File file, int size, DateTime modified})>[];
    var total = 0;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      try {
        final stat = await entity.stat();
        total += stat.size;
        entries.add((file: entity, size: stat.size, modified: stat.modified));
      } catch (_) {}
    }
    if (total <= budgetBytes) return;

    entries.sort((a, b) => a.modified.compareTo(b.modified));
    final target = (budgetBytes * 0.9).round();
    for (final entry in entries) {
      if (total <= target) break;
      // Never delete a file that may still be downloading.
      if (now.difference(entry.modified) < const Duration(seconds: 30)) continue;
      try {
        await entry.file.delete();
        total -= entry.size;
      } catch (_) {}
    }
  } catch (_) {
  } finally {
    _sweeping = false;
  }
}

Future<void> clearImageDiskCache() async {
  try {
    await CachedNetworkImageProvider.defaultCacheManager.emptyCache();
  } catch (_) {}
}

/// The cache manager's stock file service has two ways to strand a pooled
/// connection, and the image pool is capped at 12 per host, so a handful of
/// them leave every later poster (and the server it shares a host with)
/// waiting:
/// - a non-200 reply throws without its body ever being read, and an unread
///   body keeps the socket checked out;
/// - nothing times out, so a reply that sends headers and then goes quiet
///   holds its socket forever.
/// This one drains error bodies and puts deadlines on both the headers and
/// every gap in the body.
class ImageFileService extends FileService {
  ImageFileService({
    http.Client? httpClient,
    this.headerTimeout = const Duration(seconds: 20),
    this.bodyIdleTimeout = const Duration(seconds: 20),
  }) : _httpClient = httpClient ??
            IOClient(
              HttpClient()
                ..connectionTimeout = const Duration(seconds: 15)
                ..idleTimeout = const Duration(seconds: 15),
            );

  final http.Client _httpClient;
  final Duration headerTimeout;
  final Duration bodyIdleTimeout;

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    if (headers != null) request.headers.addAll(headers);
    final response = await _httpClient.send(request).timeout(headerTimeout);

    final status = response.statusCode;
    if (status != HttpStatus.ok && status != HttpStatus.accepted) {
      // The cache manager rejects these without reading them; read the body
      // here so the connection goes back to the pool.
      unawaited(
        response.stream
            .timeout(bodyIdleTimeout)
            .drain<void>()
            .catchError((Object _) {}),
      );
      return HttpGetResponse(
        http.StreamedResponse(
          const Stream<List<int>>.empty(),
          status,
          headers: response.headers,
          request: response.request,
          reasonPhrase: response.reasonPhrase,
        ),
      );
    }

    return HttpGetResponse(
      http.StreamedResponse(
        response.stream.timeout(bodyIdleTimeout),
        status,
        contentLength: response.contentLength,
        headers: response.headers,
        request: response.request,
        reasonPhrase: response.reasonPhrase,
      ),
    );
  }
}
