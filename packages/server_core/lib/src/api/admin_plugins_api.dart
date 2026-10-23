import '../models/plugin_models.dart';

abstract class AdminPluginsApi {
  Future<List<PluginInfo>> getInstalledPlugins();

  Future<void> enablePlugin(String pluginId, String version);

  Future<void> disablePlugin(String pluginId, String version);

  Future<void> uninstallPlugin(String pluginId, String version);

  Future<Map<String, dynamic>> getPluginConfiguration(String pluginId);

  Future<void> updatePluginConfiguration(
      String pluginId, Map<String, dynamic> config);

  Future<List<PackageInfo>> getAvailablePackages();

  /// GET /web/ConfigurationPages: the settings pages plugins register, each
  /// with `Name`, `PluginId` and `EnableInMainMenu`.
  Future<List<Map<String, dynamic>>> getConfigurationPages();

  Future<PackageInfo?> getPackageInfo(String name, {String? assemblyGuid});

  /// [updateClass] is the version's release channel. Emby looks the version
  /// up in it, Jellyfin ignores it.
  Future<void> installPackage(
    String name, {
    String? assemblyGuid,
    String? version,
    String? repositoryUrl,
    String? updateClass,
  });

  Future<void> cancelPackageInstallation(String packageId);

  Future<List<RepositoryInfo>> getRepositories();

  Future<void> setRepositories(List<RepositoryInfo> repositories);
}
