abstract class AdminLiveTvApi {
  Future<List<Map<String, dynamic>>> getTunerHosts();
  Future<List<Map<String, dynamic>>> getTunerHostTypes();
  Future<Map<String, dynamic>> addTunerHost(Map<String, dynamic> tunerInfo);
  Future<void> removeTunerHost(String id);

  /// Devices on the network that aren't set up yet.
  Future<List<Map<String, dynamic>>> discoverTuners();

  Future<List<Map<String, dynamic>>> getListingProviders();

  /// A new provider with the server's default categories.
  Future<Map<String, dynamic>> getDefaultListingProvider();
  Future<Map<String, dynamic>> addListingProvider(
    Map<String, dynamic> providerInfo, {
    bool validateLogin,
    bool validateListings,
  });
  Future<void> removeListingProvider(String id);

  /// Countries as Schedules Direct sends them ({shortName, fullName}),
  /// sorted by name.
  Future<List<Map<String, dynamic>>> getSchedulesDirectCountries();
  Future<List<Map<String, dynamic>>> getListingProviderLineups({
    String? providerId,
    required String location,
    required String country,
  });

  /// {TunerChannels, ProviderChannels, Mappings, ProviderName} for one
  /// provider.
  Future<Map<String, dynamic>> getChannelMappingOptions(String providerId);

  /// Maps one tuner channel and returns its updated TunerChannelMapping.
  /// Picking the channel it's already mapped to removes the mapping.
  Future<Map<String, dynamic>> setChannelMapping(
    String providerId,
    String tunerChannelId,
    String providerChannelId,
  );

  Future<Map<String, dynamic>> getLiveTvConfiguration();
  Future<void> updateLiveTvConfiguration(Map<String, dynamic> config);
}
