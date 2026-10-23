import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

class JellyfinAdminBackupApi implements AdminBackupApi {
  final Dio _dio;

  JellyfinAdminBackupApi(this._dio);

  static const _createTimeout = Duration(hours: 12);

  @override
  Future<List<Map<String, dynamic>>> getBackups() async {
    final response = await _dio.get('/Backup');
    final data = response.data;
    if (data is List) {
      return data.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    return const [];
  }

  @override
  Future<Map<String, dynamic>> createBackup([
    Map<String, dynamic>? options,
  ]) async {
    // The server answers only once the archive is written, which takes far
    // longer than the client's 30 s receive timeout on a real library. Not
    // Duration.zero: on web the xhr timeout is connect + receive, so zero
    // would cut the request at the 8 s connect timeout.
    final response = await _dio.post(
      '/Backup/Create',
      data: options,
      options: Options(receiveTimeout: _createTimeout),
    );

    final data = response.data;
    if (data is Map<String, dynamic>) {
      return data;
    }
    return const {};
  }

  @override
  Future<void> restoreBackup(String backupPath) async {
    await _dio.post('/Backup/Restore', data: {'ArchiveFileName': backupPath});
  }

  @override
  Future<Map<String, dynamic>> getBackupManifest(String backupPath) async {
    final response = await _dio.get(
      '/Backup/Manifest',
      queryParameters: {'path': backupPath},
    );

    // 204 means the archive has no manifest.
    final data = response.data;
    if (data is Map<String, dynamic>) {
      return data;
    }
    return const {};
  }
}
