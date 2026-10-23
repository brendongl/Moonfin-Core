/// Whether the server's Emby Premiere license is active, and whether a key is
/// set at all. The key itself stays in [EmbyAdminApi.getPremiereKey].
class PremiereStatus {
  const PremiereStatus({required this.isActive, required this.hasKey});

  final bool isActive;
  final bool hasKey;

  /// A key that's set but doesn't unlock anything is invalid or expired.
  bool get isKeyInvalid => hasKey && !isActive;
}

/// Admin endpoints only Emby has. Settings that live in a named configuration
/// (`cinemamode`, `dlna`, `devices`, `sync`) go through
/// [AdminSystemApi.getNamedConfiguration] instead.
abstract class EmbyAdminApi {
  Future<PremiereStatus> getPremiereStatus();

  /// The stored Premiere key, for the Premiere page to show masked.
  Future<String?> getPremiereKey();

  /// An empty key removes the stored one.
  Future<void> setPremiereKey(String key);

  Future<List<Map<String, dynamic>>> getVideoCodecInformation();

  /// An editor object with `Object` and `DefaultObject`.
  Future<Map<String, dynamic>> getToneMapOptions();

  /// Conversion jobs, or download jobs when [conversions] is false.
  Future<List<Map<String, dynamic>>> getSyncJobs({required bool conversions});

  Future<void> cancelSyncJob(String jobId);

  /// A page of channels with their management ids, in the channel order.
  Future<Map<String, dynamic>> getManagedChannels({
    int startIndex = 0,
    int limit = 100,
  });

  Future<void> setChannelDisabled(
    String channelId, {
    required String managementId,
    required bool disabled,
  });

  Future<void> setChannelSortIndex(
    String channelId, {
    required String managementId,
    required int newIndex,
  });

  /// The guide sources a new provider can use ({Name, Id, SetupUrl}).
  /// [country] is a three letter region code, and some sources only cover
  /// some countries.
  Future<List<Map<String, dynamic>>> getAvailableListingProviders({
    String? country,
  });

  /// Links an Emby Connect account to a user. The result has `IsPending`,
  /// `IsNewUserInvitation` and `GuestDisplayName`.
  Future<Map<String, dynamic>> linkConnectUser(
    String userId,
    String connectUsername,
  );

  Future<void> unlinkConnectUser(String userId);

  /// From the Backup & Restore plugin: `FullBackupInfo` (with `CanRestore`
  /// and the backed up `Users`) and the `LightBackups` list.
  Future<Map<String, dynamic>> getBackupInfo();

  /// Restores the full backup, or the light backup named [lightBackupName].
  /// The server shuts down when it's done.
  Future<void> restoreBackup({
    bool restoreServerId = false,
    String? lightBackupName,
  });
}
