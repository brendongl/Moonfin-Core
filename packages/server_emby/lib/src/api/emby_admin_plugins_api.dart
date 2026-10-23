import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

/// Emby has one plugin catalog and no repositories, and a plugin is either
/// installed or not, so there's nothing to enable or disable.
class EmbyAdminPluginsApi implements AdminPluginsApi {
  final Dio _dio;

  EmbyAdminPluginsApi(this._dio);

  @override
  Future<List<PluginInfo>> getInstalledPlugins() async {
    final response = await _dio.get('/Plugins');
    return (response.data as List<dynamic>)
        .map((e) => PluginInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> enablePlugin(String pluginId, String version) async =>
      throw UnsupportedError('Emby plugins cannot be enabled or disabled');

  @override
  Future<void> disablePlugin(String pluginId, String version) async =>
      throw UnsupportedError('Emby plugins cannot be enabled or disabled');

  /// Takes effect after a restart, though the plugin leaves the list at once.
  @override
  Future<void> uninstallPlugin(String pluginId, String version) async {
    await _dio.post('/Plugins/${Uri.encodeComponent(pluginId)}/Delete');
  }

  /// Only plugins with a `ConfigurationFileName` have one. The others fail.
  @override
  Future<Map<String, dynamic>> getPluginConfiguration(String pluginId) async {
    final response = await _dio.get('/Plugins/$pluginId/Configuration');
    return response.data as Map<String, dynamic>;
  }

  @override
  Future<void> updatePluginConfiguration(
    String pluginId,
    Map<String, dynamic> config,
  ) async {
    await _dio.post('/Plugins/$pluginId/Configuration', data: config);
  }

  @override
  Future<List<PackageInfo>> getAvailablePackages() async {
    final response = await _dio.get(
      '/Packages',
      queryParameters: {
        'TargetSystems': 'Server',
        'IsAdult': false,
        'PackageType': 'UserInstalled',
      },
    );
    return (response.data as List<dynamic>)
        .map((e) => PackageInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Only settings pages. Without the filter Emby also lists each plugin's
  /// scripts.
  @override
  Future<List<Map<String, dynamic>>> getConfigurationPages() async {
    final response = await _dio.get(
      '/web/ConfigurationPages',
      queryParameters: {'PageType': 'PluginConfiguration'},
    );
    return (response.data as List<dynamic>)
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  @override
  Future<PackageInfo?> getPackageInfo(
    String name, {
    String? assemblyGuid,
  }) async {
    try {
      final response = await _dio.get(
        '/Packages/${Uri.encodeComponent(name)}',
        queryParameters: {'AssemblyGuid': ?assemblyGuid},
      );
      return PackageInfo.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      // Emby answers an unknown package with a 400.
      final status = e.response?.statusCode;
      if (status == 400 || status == 404) return null;
      rethrow;
    }
  }

  /// Takes effect after a restart. Without [updateClass] Emby only looks in
  /// the Release channel.
  @override
  Future<void> installPackage(
    String name, {
    String? assemblyGuid,
    String? version,
    String? repositoryUrl,
    String? updateClass,
  }) async {
    await _dio.post(
      '/Packages/Installed/${Uri.encodeComponent(name)}',
      queryParameters: {
        'AssemblyGuid': ?assemblyGuid,
        'Version': ?version,
        'UpdateClass': ?updateClass,
      },
    );
  }

  @override
  Future<void> cancelPackageInstallation(String packageId) async {
    await _dio.post(
      '/Packages/Installing/${Uri.encodeComponent(packageId)}/Delete',
    );
  }

  @override
  Future<List<RepositoryInfo>> getRepositories() async => const [];

  @override
  Future<void> setRepositories(List<RepositoryInfo> repositories) async =>
      throw UnsupportedError('Emby has no plugin repositories');
}
