import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

class JellyfinAdminLibraryApi implements AdminLibraryApi {
  final Dio _dio;

  JellyfinAdminLibraryApi(this._dio);

  @override
  Future<List<VirtualFolderInfo>> getVirtualFolders() async {
    final response = await _dio.get('/Library/VirtualFolders');
    return (response.data as List<dynamic>)
        .map((e) => VirtualFolderInfo.fromJson(e as Map<String, dynamic>))
        .toList();
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
      // The server reads a new library's folders from its library options and
      // ignores any other body field. Its query list splits on commas, which
      // breaks a folder with one in its name.
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
        'Path': path,
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
      data: {
        'Id': libraryId,
        'LibraryOptions': options,
      },
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

  @override
  Future<List<VirtualFolderInfo>> getMediaFolders({bool? isHidden}) async {
    final response = await _dio.get(
      '/Library/MediaFolders',
      queryParameters: {'isHidden': ?isHidden},
    );
    final data = response.data as Map<String, dynamic>;
    return (data['Items'] as List<dynamic>?)
            ?.map(
                (e) => VirtualFolderInfo.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];
  }

  @override
  Future<Map<String, dynamic>> getAvailableLibraryOptions(
    String? contentType,
  ) async {
    final response = await _dio.get(
      '/Libraries/AvailableOptions',
      queryParameters: {
        if (contentType != null && contentType.isNotEmpty)
          'libraryContentType': contentType,
        'isNewLibrary': false,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }
}
