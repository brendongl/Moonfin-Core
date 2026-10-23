import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

class EmbyAdminSystemApi implements AdminSystemApi {
  final Dio _dio;

  EmbyAdminSystemApi(this._dio);

  @override
  Future<Map<String, dynamic>> getServerConfiguration() async {
    final response = await _dio.get('/System/Configuration');
    return response.data as Map<String, dynamic>;
  }

  @override
  Future<void> updateServerConfiguration(Map<String, dynamic> config) async {
    await _dio.post('/System/Configuration', data: config);
  }

  @override
  Future<Map<String, dynamic>> getNamedConfiguration(String key) async {
    final response = await _dio.get('/System/Configuration/$key');
    return response.data as Map<String, dynamic>;
  }

  @override
  Future<void> updateNamedConfiguration(
    String key,
    Map<String, dynamic> config,
  ) async {
    await _dio.post('/System/Configuration/$key', data: config);
  }

  /// Emby has no storage endpoint, only the folder paths in the system info.
  @override
  Future<StorageInfo> getStorageInfo() async {
    final response = await _dio.get('/System/Info');
    return StorageInfo.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<void> restartServer() async {
    await _dio.post('/System/Restart');
  }

  @override
  Future<void> shutdownServer() async {
    await _dio.post('/System/Shutdown');
  }

  @override
  Future<List<LogFileInfo>> getLogFiles() async {
    final response = await _dio.get('/System/Logs/Query');
    final items = (response.data as Map<String, dynamic>)['Items'] as List?;
    return [
      for (final e in items ?? const [])
        LogFileInfo.fromJson(e as Map<String, dynamic>),
    ];
  }

  @override
  Future<String> getLogFileContent(String name) async {
    final response = await _dio.get(
      '/System/Logs/${Uri.encodeComponent(name)}',
      options: Options(responseType: ResponseType.plain),
    );
    return response.data as String;
  }

  /// Emby filters by [startIndex], [limit], [minDate] and [hasUserId] only,
  /// so [maxDate], [severity] and [username] aren't sent.
  @override
  Future<ActivityLogResult> getActivityLog({
    int? startIndex,
    int? limit,
    bool? hasUserId,
    DateTime? minDate,
    DateTime? maxDate,
    String? severity,
    String? username,
  }) async {
    final response = await _dio.get(
      '/System/ActivityLog/Entries',
      queryParameters: {
        'StartIndex': ?startIndex,
        'Limit': ?limit,
        'HasUserId': ?hasUserId,
        'MinDate': ?minDate?.toUtc().toIso8601String(),
      },
    );
    return ActivityLogResult.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<Map<String, dynamic>>> _getList(String path) async {
    final response = await _dio.get(path);
    return (response.data as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getCultures() =>
      _getList('/Localization/Cultures');

  @override
  Future<List<Map<String, dynamic>>> getCountries() =>
      _getList('/Localization/Countries');

  @override
  Future<List<Map<String, dynamic>>> getLocalizationOptions() =>
      _getList('/Localization/Options');

  @override
  Future<List<Map<String, dynamic>>> getParentalRatings() =>
      _getList('/Localization/ParentalRatings');

  @override
  Future<List<Map<String, dynamic>>> getAuthProviders() =>
      _getList('/Auth/Providers');

  /// Emby has no password reset providers.
  @override
  Future<List<Map<String, dynamic>>> getPasswordResetProviders() async =>
      const [];

  @override
  Future<void> uploadSplashscreen(List<int> bytes, String contentType) =>
      throw UnsupportedError('Emby has no login splashscreen');

  @override
  Future<void> deleteSplashscreen() =>
      throw UnsupportedError('Emby has no login splashscreen');

  @override
  Future<Map<String, dynamic>> getItemCounts() async {
    final response = await _dio.get('/Items/Counts');
    return response.data as Map<String, dynamic>;
  }
}
