import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

class JellyfinAdminLiveTvApi implements AdminLiveTvApi {
  final Dio _dio;

  JellyfinAdminLiveTvApi(this._dio);

  @override
  Future<List<Map<String, dynamic>>> getTunerHosts() async {
    final config = await getLiveTvConfiguration();
    final hosts = config['TunerHosts'];
    if (hosts is List) {
      return hosts.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> getTunerHostTypes() async {
    final response = await _dio.get('/LiveTv/TunerHosts/Types');
    return _asList(response.data);
  }

  @override
  Future<Map<String, dynamic>> addTunerHost(Map<String, dynamic> tunerInfo) async {
    final response = await _dio.post('/LiveTv/TunerHosts', data: tunerInfo);
    return _asMap(response.data);
  }

  @override
  Future<void> removeTunerHost(String id) async {
    await _dio.delete('/LiveTv/TunerHosts', queryParameters: {'id': id});
  }

  @override
  Future<List<Map<String, dynamic>>> discoverTuners() async {
    final response = await _dio.get(
      '/LiveTv/Tuners/Discover',
      queryParameters: {'NewDevicesOnly': true},
    );
    return _asList(response.data);
  }

  @override
  Future<List<Map<String, dynamic>>> getListingProviders() async {
    final config = await getLiveTvConfiguration();
    final providers = config['ListingProviders'];
    if (providers is List) {
      return providers.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    return const [];
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
    await _dio.delete('/LiveTv/ListingProviders', queryParameters: {'id': id});
  }

  @override
  Future<List<Map<String, dynamic>>> getSchedulesDirectCountries() async {
    final response =
        await _dio.get('/LiveTv/ListingProviders/SchedulesDirect/Countries');
    final data = response.data;
    final countries = <Map<String, dynamic>>[];
    // The server passes the Schedules Direct reply through, a map of region
    // to [{shortName, fullName}]. The ZZZ region is left out.
    if (data is Map) {
      data.forEach((region, list) {
        if (region == 'ZZZ' || list is! List) return;
        countries.addAll(
          list.whereType<Map>().map((e) => e.cast<String, dynamic>()),
        );
      });
    }
    String name(Map<String, dynamic> c) => c['fullName']?.toString() ?? '';
    countries.sort((a, b) => name(a).compareTo(name(b)));
    return countries;
  }

  @override
  Future<List<Map<String, dynamic>>> getListingProviderLineups({
    String? providerId,
    required String location,
    required String country,
  }) async {
    final response = await _dio.get(
      '/LiveTv/ListingProviders/Lineups',
      queryParameters: {
        if (providerId != null && providerId.isNotEmpty) 'Id': providerId,
        'Location': location,
        'Country': country,
      },
    );
    return _asList(response.data);
  }

  @override
  Future<Map<String, dynamic>> getChannelMappingOptions(String providerId) async {
    final response = await _dio.get(
      '/LiveTv/ChannelMappingOptions',
      queryParameters: {'providerId': providerId},
    );
    return _asMap(response.data);
  }

  @override
  Future<Map<String, dynamic>> setChannelMapping(
    String providerId,
    String tunerChannelId,
    String providerChannelId,
  ) async {
    final response = await _dio.post(
      '/LiveTv/ChannelMappings',
      data: {
        'ProviderId': providerId,
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
      return data.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    return const [];
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    return const {};
  }
}
