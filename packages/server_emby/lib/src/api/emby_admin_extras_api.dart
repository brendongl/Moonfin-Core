import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

class EmbyAdminExtrasApi implements EmbyAdminApi {
  final Dio _dio;

  EmbyAdminExtrasApi(this._dio);

  Future<Map<String, dynamic>> _securityInfo() async {
    final response = await _dio.get('/Plugins/SecurityInfo');
    return _asMap(response.data);
  }

  /// A removed key comes back as an empty string, not as a missing one.
  @override
  Future<PremiereStatus> getPremiereStatus() async {
    final info = await _securityInfo();
    return PremiereStatus(
      isActive: info['IsMBSupporter'] == true,
      hasKey: (info['SupporterKey'] as String? ?? '').isNotEmpty,
    );
  }

  @override
  Future<String?> getPremiereKey() async {
    final key = (await _securityInfo())['SupporterKey'] as String?;
    return key == null || key.isEmpty ? null : key;
  }

  @override
  Future<void> setPremiereKey(String key) async {
    await _dio.post('/Plugins/SecurityInfo', data: {'SupporterKey': key});
  }

  @override
  Future<List<Map<String, dynamic>>> getVideoCodecInformation() async {
    final response = await _dio.get('/Encoding/CodecInformation/Video');
    return _asList(response.data);
  }

  @override
  Future<Map<String, dynamic>> getToneMapOptions() async {
    final response = await _dio.get('/Encoding/FullToneMapOptions');
    return _asMap(response.data);
  }

  @override
  Future<List<Map<String, dynamic>>> getSyncJobs({
    required bool conversions,
  }) async {
    const provider = 'ConvertSyncProvider';
    final response = await _dio.get(
      '/Sync/Jobs',
      queryParameters: {
        conversions ? 'IncludeProviders' : 'ExcludeProviders': provider,
      },
    );
    return _asList(_asMap(response.data)['Items']);
  }

  @override
  Future<void> cancelSyncJob(String jobId) async {
    await _dio.post('/Sync/Jobs/${Uri.encodeComponent(jobId)}/Delete');
  }

  @override
  Future<Map<String, dynamic>> getManagedChannels({
    int startIndex = 0,
    int limit = 100,
  }) async {
    final response = await _dio.get(
      '/LiveTv/Manage/Channels',
      queryParameters: {
        'StartIndex': startIndex,
        'Limit': limit,
        // The order a new sort index counts in.
        'SortBy': 'DefaultChannelOrder',
        'SortOrder': 'Ascending',
      },
    );
    return _asMap(response.data);
  }

  @override
  Future<void> setChannelDisabled(
    String channelId, {
    required String managementId,
    required bool disabled,
  }) async {
    await _dio.post(
      '/LiveTv/Manage/Channels/${Uri.encodeComponent(channelId)}/Disabled',
      queryParameters: {'ManagementId': managementId, 'Disabled': disabled},
    );
  }

  @override
  Future<void> setChannelSortIndex(
    String channelId, {
    required String managementId,
    required int newIndex,
  }) async {
    await _dio.post(
      '/LiveTv/Manage/Channels/${Uri.encodeComponent(channelId)}/SortIndex',
      queryParameters: {'ManagementId': managementId, 'NewIndex': newIndex},
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getAvailableListingProviders({
    String? country,
  }) async {
    final response = await _dio.get(
      '/LiveTv/ListingProviders/Available',
      queryParameters: {'Country': ?country},
    );
    return _asList(response.data);
  }

  @override
  Future<Map<String, dynamic>> linkConnectUser(
    String userId,
    String connectUsername,
  ) async {
    final response = await _dio.post(
      '/Users/$userId/Connect/Link',
      queryParameters: {'ConnectUsername': connectUsername},
    );
    return _asMap(response.data);
  }

  @override
  Future<void> unlinkConnectUser(String userId) async {
    await _dio.post('/Users/$userId/Connect/Link/Delete');
  }

  @override
  Future<Map<String, dynamic>> getBackupInfo() async {
    final response = await _dio.get('/BackupRestore/BackupInfo');
    return _asMap(response.data);
  }

  @override
  Future<void> restoreBackup({
    bool restoreServerId = false,
    String? lightBackupName,
  }) async {
    await _dio.post(
      '/BackupRestore/Restore',
      data: {'RestoreServerId': restoreServerId, 'UseFiles': lightBackupName},
    );
  }

  List<Map<String, dynamic>> _asList(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    return const [];
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    return const {};
  }
}
