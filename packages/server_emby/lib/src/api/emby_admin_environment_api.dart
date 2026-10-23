import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

class EmbyAdminEnvironmentApi implements AdminEnvironmentApi {
  final Dio _dio;

  EmbyAdminEnvironmentApi(this._dio);

  @override
  Future<List<Map<String, dynamic>>> getDirectoryContents(
    String path, {
    bool? includeFiles,
    bool? includeDirectories,
  }) async {
    final response = await _dio.get(
      '/Environment/DirectoryContents',
      queryParameters: {
        'Path': path,
        'IncludeFiles': ?includeFiles,
        'IncludeDirectories': ?includeDirectories,
      },
    );
    return (response.data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  @override
  Future<void> validatePath(
    String path, {
    bool writable = false,
    bool? isFile,
  }) async {
    await _dio.post(
      '/Environment/ValidatePath',
      // Emby spells it Writeable.
      data: {'ValidateWriteable': writable, 'Path': path, 'IsFile': ?isFile},
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getDrives() async {
    final response = await _dio.get('/Environment/Drives');
    return (response.data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  @override
  Future<String?> getParentPath(String path) async {
    final response = await _dio.get(
      '/Environment/ParentPath',
      queryParameters: {'Path': path},
      // The bare path comes back labeled as json, which doesn't decode.
      options: Options(responseType: ResponseType.plain),
    );
    final parent = response.data as String?;
    return parent == null || parent.isEmpty ? null : parent;
  }
}
