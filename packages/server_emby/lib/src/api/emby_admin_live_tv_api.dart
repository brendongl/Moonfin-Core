import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

class EmbyAdminLiveTvApi implements AdminLiveTvApi {
  final Dio _dio;

  EmbyAdminLiveTvApi(this._dio);

  @override
  Future<List<Map<String, dynamic>>> getTunerHosts() async {
    final response = await _dio.get('/LiveTv/TunerHosts');
    return _asList(response.data);
  }

  @override
  Future<List<Map<String, dynamic>>> getTunerHostTypes() async {
    final response = await _dio.get('/LiveTv/TunerHosts/Types');
    return _asList(response.data);
  }

  @override
  Future<Map<String, dynamic>> addTunerHost(
    Map<String, dynamic> tunerInfo,
  ) async {
    final response = await _dio.post('/LiveTv/TunerHosts', data: tunerInfo);
    return _asMap(response.data);
  }

  @override
  Future<void> removeTunerHost(String id) async {
    await _dio.post('/LiveTv/TunerHosts/Delete', queryParameters: {'Id': id});
  }

  @override
  Future<List<Map<String, dynamic>>> discoverTuners() async {
    final response = await _dio.get('/LiveTv/Tuners/Discover');
    return _asList(response.data);
  }

  @override
  Future<List<Map<String, dynamic>>> getListingProviders() async {
    final response = await _dio.get('/LiveTv/ListingProviders');
    return _asList(response.data);
  }

  @override
  Future<Map<String, dynamic>> getDefaultListingProvider() async {
    final response = await _dio.get('/LiveTv/ListingProviders/Default');
    return _asMap(response.data);
  }

  @override
  Future<Map<String, dynamic>> addListingProvider(
    Map<String, dynamic> providerInfo, {
    bool validateLogin = false,
    bool validateListings = false,
  }) async {
    final response = await _dio.post(
      '/LiveTv/ListingProviders',
      data: providerInfo,
      queryParameters: {
        if (validateLogin) 'ValidateLogin': true,
        if (validateListings) 'ValidateListings': true,
      },
    );
    return _asMap(response.data);
  }

  @override
  Future<void> removeListingProvider(String id) async {
    await _dio.post(
      '/LiveTv/ListingProviders/Delete',
      queryParameters: {'Id': id},
    );
  }

  /// Emby has no Schedules Direct. Its guide sources come from
  /// [EmbyAdminApi.getAvailableListingProviders].
  @override
  Future<List<Map<String, dynamic>>> getSchedulesDirectCountries() async =>
      throw UnsupportedError('Emby has no Schedules Direct provider');

  /// [country] is a three letter region code. Emby Guide Data needs Premiere
  /// to list lineups.
  @override
  Future<List<Map<String, dynamic>>> getListingProviderLineups({
    String? providerId,
    required String location,
    required String country,
  }) async {
    final response = await _dio.get(
      '/LiveTv/ListingProviders/Lineups',
      queryParameters: {
        // A saved provider brings its own type. Emby Guide Data is the only
        // new one that has lineups.
        if (providerId != null && providerId.isNotEmpty)
          'Id': providerId
        else
          'Type': 'embygn',
        'Location': location,
        'Country': country,
      },
    );
    return _asList(response.data);
  }

  /// Emby only sends `ProviderChannels` ({Id, Name}). The tuner side is each
  /// channel's `ManagementId` from [EmbyAdminApi.getManagedChannels].
  @override
  Future<Map<String, dynamic>> getChannelMappingOptions(
    String providerId,
  ) async {
    final response = await _dio.get(
      '/LiveTv/ChannelMappingOptions',
      queryParameters: {'ProviderId': providerId},
    );
    return _asMap(response.data);
  }

  /// [tunerChannelId] is the channel's `ManagementId`. Emby answers with
  /// `IsManualMapping`.
  @override
  Future<Map<String, dynamic>> setChannelMapping(
    String providerId,
    String tunerChannelId,
    String providerChannelId,
  ) async {
    final response = await _dio.post(
      '/LiveTv/ChannelMappings',
      queryParameters: {'ProviderId': providerId},
      data: {
        'TunerChannelId': tunerChannelId,
        'ProviderChannelId': providerChannelId,
      },
    );
    return _asMap(response.data);
  }

  @override
  Future<Map<String, dynamic>> getLiveTvConfiguration() async {
    final response = await _dio.get('/System/Configuration/livetv');
    return _asMap(response.data);
  }

  @override
  Future<void> updateLiveTvConfiguration(Map<String, dynamic> config) async {
    await _dio.post('/System/Configuration/livetv', data: config);
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
