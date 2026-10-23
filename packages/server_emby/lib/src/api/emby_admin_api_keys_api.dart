import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

class EmbyAdminApiKeysApi implements AdminApiKeysApi {
  final Dio _dio;

  EmbyAdminApiKeysApi(this._dio);

  /// Every key comes back in `Items`. `TotalRecordCount` stays 0 because no
  /// page size is sent.
  @override
  Future<Map<String, dynamic>> getApiKeys() async {
    final response = await _dio.get('/Auth/Keys');
    return response.data as Map<String, dynamic>;
  }

  @override
  Future<void> createApiKey(String appName) async {
    await _dio.post('/Auth/Keys', queryParameters: {'App': appName});
  }

  @override
  Future<void> revokeApiKey(String key) async {
    await _dio.delete('/Auth/Keys/${Uri.encodeComponent(key)}');
  }
}
