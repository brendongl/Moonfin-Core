import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

class EmbyAdminLibraryApi implements AdminLibraryApi {
  final Dio _dio;

  EmbyAdminLibraryApi(this._dio);

  @override
  Future<List<VirtualFolderInfo>> getVirtualFolders() async {
    final response = await _dio.get('/Library/VirtualFolders/Query');
    final items = (response.data as Map<String, dynamic>)['Items'] as List?;
    return [
      for (final e in items ?? const [])
        VirtualFolderInfo.fromJson(e as Map<String, dynamic>),
    ];
  }

  @override
  Future<void> addVirtualFolder({
    required String name,
    String? collectionType,
    List<String>? paths,
    Map<String, dynamic>? libraryOptions,
    bool refreshLibrary = false,
  }) async {
    final hasPaths = paths != null && paths.isNotEmpty;
    await _dio.post(
      '/Library/VirtualFolders',
      queryParameters: {
        'name': name,
        'collectionType': ?collectionType,
        'refreshLibrary': refreshLibrary,
      },
      // The server reads a new library's folders from its library options.
      data: {
        if (libraryOptions != null || hasPaths)
          'LibraryOptions': {
            ...?libraryOptions,
            if (hasPaths)
              'PathInfos': [
                for (final path in paths) {'Path': path},
              ],
          },
      },
    );
  }

  @override
  Future<void> removeVirtualFolder(
    String name, {
    bool refreshLibrary = false,
    String? libraryId,
  }) async {
    await _dio.delete(
      '/Library/VirtualFolders',
      queryParameters: {
        'name': name,
        'Id': _require(libraryId),
        'refreshLibrary': refreshLibrary,
      },
    );
  }

  @override
  Future<void> renameVirtualFolder(
    String name,
    String newName, {
    bool refreshLibrary = false,
    String? libraryId,
  }) async {
    await _dio.post(
      '/Library/VirtualFolders/Name',
      queryParameters: {
        'name': name,
        'newName': newName,
        'Id': _require(libraryId),
        'refreshLibrary': refreshLibrary,
      },
    );
  }

  @override
  Future<void> addMediaPath(
    String libraryName,
    String path, {
    bool refreshLibrary = false,
    String? libraryId,
  }) async {
    await _dio.post(
      '/Library/VirtualFolders/Paths',
      queryParameters: {'refreshLibrary': refreshLibrary},
      data: {
        'Name': libraryName,
        'PathInfo': {'Path': path},
        'Id': _require(libraryId),
      },
    );
  }

  @override
  Future<void> updateMediaPath(
    String libraryName,
    Map<String, dynamic> pathInfo, {
    String? libraryId,
  }) async {
    await _dio.post(
      '/Library/VirtualFolders/Paths/Update',
      data: {
        'Name': libraryName,
        'PathInfo': pathInfo,
        'Id': _require(libraryId),
      },
    );
  }

  @override
  Future<void> removeMediaPath(
    String libraryName,
    String path, {
    bool refreshLibrary = false,
    String? libraryId,
  }) async {
    await _dio.delete(
      '/Library/VirtualFolders/Paths',
      queryParameters: {
        'name': libraryName,
        'path': path,
        'Id': _require(libraryId),
        'refreshLibrary': refreshLibrary,
      },
    );
  }

  @override
  Future<void> updateLibraryOptions(
    String libraryId,
    Map<String, dynamic> options,
  ) async {
    await _dio.post(
      '/Library/VirtualFolders/LibraryOptions',
      data: {'Id': libraryId, 'LibraryOptions': options},
    );
  }

  @override
  Future<void> refreshLibrary() async {
    await _dio.post('/Library/Refresh');
  }

  @override
  Future<List<String>> getPhysicalPaths() async {
    final response = await _dio.get('/Library/PhysicalPaths');
    return (response.data as List<dynamic>).cast<String>();
  }

  /// A user's library access is saved as each folder's Guid, so that's the
  /// [VirtualFolderInfo.itemId] here. `isHidden: false` leaves out the
  /// folders whose access can't be set, like Playlists.
  @override
  Future<List<VirtualFolderInfo>> getMediaFolders({bool? isHidden}) async {
    final response = await _dio.get('/Library/SelectableMediaFolders');
    return [
      for (final f in (response.data as List).cast<Map<String, dynamic>>())
        if (isHidden != false || f['IsUserAccessConfigurable'] != false)
          VirtualFolderInfo(
            name: f['Name'] as String? ?? '',
            itemId: (f['Guid'] ?? f['Id']) as String? ?? '',
          ),
    ];
  }

  @override
  Future<Map<String, dynamic>> getAvailableLibraryOptions(
    String? contentType,
  ) async {
    final response = await _dio.get(
      '/Libraries/AvailableOptions',
      queryParameters: {
        if (contentType != null && contentType.isNotEmpty)
          'LibraryContentType': contentType,
        'IsNewLibrary': false,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  // Emby finds the library by its Id and fails without one.
  static String _require(String? libraryId) =>
      libraryId ?? (throw ArgumentError.notNull('libraryId'));
}
