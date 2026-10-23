abstract class UserLibraryApi {
  bool get supportsNumericUserRatings;
  Future<void> markFavorite(String itemId);
  Future<void> unmarkFavorite(String itemId);
  Future<void> markPlayed(String itemId);
  Future<void> unmarkPlayed(String itemId);
  /// Saves a resume position outside a playback session, stamped with the
  /// current time so another device can tell which save is newer.
  Future<void> updatePlayedPosition(String itemId, {required int positionTicks});
  Future<void> updateUserRating(String itemId, {required bool likes});
  Future<void> updateNumericUserRating(String itemId, {required double rating});
  Future<void> deleteUserRating(String itemId);
  Future<Map<String, dynamic>> getItem(String itemId);
}

/// Implemented by a [UserLibraryApi] whose server can drop an item from its
/// Continue Watching list on its own, leaving the played state and resume
/// position alone. Emby does; Jellyfin has no such flag, so callers there
/// fall back to hiding the item on the client.
abstract interface class ResumeVisibilityApi {
  /// Hides [itemId] from the server's resume list, or brings it back when
  /// [hidden] is false.
  Future<void> setHiddenFromResume(String itemId, {required bool hidden});
}
