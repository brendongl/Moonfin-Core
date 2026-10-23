import '../models/admin_models.dart';

abstract class AdminLibraryApi {
  Future<List<VirtualFolderInfo>> getVirtualFolders();
  /// [libraryOptions] is saved as sent, so pass the full set or the library
  /// gets the server's constructor defaults.
  Future<void> addVirtualFolder({
    required String name,
    String? collectionType,
    List<String>? paths,
    Map<String, dynamic>? libraryOptions,
    bool refreshLibrary = false,
  });
  // The mutations below take the library by name. Emby also wants its
  // [libraryId], which Jellyfin ignores.
  Future<void> removeVirtualFolder(
    String name, {
    bool refreshLibrary = false,
    String? libraryId,
  });
  Future<void> renameVirtualFolder(
    String name,
    String newName, {
    bool refreshLibrary = false,
    String? libraryId,
  });
  Future<void> addMediaPath(
    String libraryName,
    String path, {
    bool refreshLibrary = false,
    String? libraryId,
  });
  Future<void> updateMediaPath(
    String libraryName,
    Map<String, dynamic> pathInfo, {
    String? libraryId,
  });
  Future<void> removeMediaPath(
    String libraryName,
    String path, {
    bool refreshLibrary = false,
    String? libraryId,
  });
  Future<void> updateLibraryOptions(
    String libraryId,
    Map<String, dynamic> options,
  );
  Future<void> refreshLibrary();
  Future<List<String>> getPhysicalPaths();
  /// The library folders. Pass `isHidden: false` for the ones offered for
  /// user access.
  Future<List<VirtualFolderInfo>> getMediaFolders({bool? isHidden});

  /// Available metadata/image/subtitle/lyric fetchers and savers for a library
  /// content type, used to build the downloader-ordering UI. Returned as a raw
  /// map (`MetadataSavers`, `SubtitleFetchers`, `TypeOptions[]`, ...).
  Future<Map<String, dynamic>> getAvailableLibraryOptions(String? contentType);
}
