import 'package:server_emby/src/api/emby_admin_library_api.dart';
import 'package:test/test.dart';

import 'admin_fake.dart';

void main() {
  test('virtual folders come from the query', () async {
    final fake = AdminFake({
      '/Library/VirtualFolders/Query': {
        'Items': [
          {
            'Name': 'Movies',
            'Locations': ['/media/Movies'],
            'CollectionType': 'movies',
            'ItemId': '3',
            'Id': '3',
            'Guid': '772c1dbfb8fb4c8fa982c2809f92c2d9',
          },
        ],
      },
    });
    final folders = await EmbyAdminLibraryApi(fake.dio).getVirtualFolders();

    expect(folders.single.itemId, '3');
    expect(folders.single.locations, ['/media/Movies']);
  });

  test('a new library sends its folders in the library options', () async {
    final fake = AdminFake();
    await EmbyAdminLibraryApi(fake.dio).addVirtualFolder(
      name: 'Films',
      collectionType: 'movies',
      paths: ['/a'],
      libraryOptions: {'EnableRealtimeMonitor': false},
    );

    expect(fake.last.path, '/Library/VirtualFolders');
    expect(fake.last.queryParameters, {
      'name': 'Films',
      'collectionType': 'movies',
      'refreshLibrary': false,
    });
    expect(fake.last.data, {
      'LibraryOptions': {
        'EnableRealtimeMonitor': false,
        'PathInfos': [
          {'Path': '/a'},
        ],
      },
    });
  });

  test('every mutation by name also sends the library Id', () async {
    final fake = AdminFake();
    final api = EmbyAdminLibraryApi(fake.dio);

    await api.removeVirtualFolder('Films', libraryId: '23');
    expect(fake.last.method, 'DELETE');
    expect(fake.last.queryParameters, {
      'name': 'Films',
      'Id': '23',
      'refreshLibrary': false,
    });

    await api.renameVirtualFolder('Films', 'Movies', libraryId: '23');
    expect(fake.last.path, '/Library/VirtualFolders/Name');
    expect(fake.last.queryParameters, {
      'name': 'Films',
      'newName': 'Movies',
      'Id': '23',
      'refreshLibrary': false,
    });

    await api.addMediaPath('Films', '/b', libraryId: '23');
    expect(fake.last.path, '/Library/VirtualFolders/Paths');
    expect(fake.last.data, {
      'Name': 'Films',
      'PathInfo': {'Path': '/b'},
      'Id': '23',
    });

    await api.updateMediaPath('Films', {
      'Path': '/b',
      'NetworkPath': 'smb://x',
    }, libraryId: '23');
    expect(fake.last.path, '/Library/VirtualFolders/Paths/Update');
    expect(fake.last.data, {
      'Name': 'Films',
      'PathInfo': {'Path': '/b', 'NetworkPath': 'smb://x'},
      'Id': '23',
    });

    await api.removeMediaPath('Films', '/b', libraryId: '23');
    expect(fake.last.method, 'DELETE');
    expect(fake.last.path, '/Library/VirtualFolders/Paths');
    expect(fake.last.queryParameters, {
      'name': 'Films',
      'path': '/b',
      'Id': '23',
      'refreshLibrary': false,
    });
  });

  test('a mutation without the library Id fails before sending', () async {
    final fake = AdminFake();
    final api = EmbyAdminLibraryApi(fake.dio);

    await expectLater(api.removeVirtualFolder('Films'), throwsArgumentError);
    await expectLater(api.addMediaPath('Films', '/b'), throwsArgumentError);
    expect(fake.requests, isEmpty);
  });

  test(
    'media folders are keyed by Guid and skip unconfigurable ones',
    () async {
      final fake = AdminFake({
        '/Library/SelectableMediaFolders': [
          {
            'Name': 'Movies',
            'Id': '3',
            'Guid': 'g3',
            'IsUserAccessConfigurable': true,
          },
          {'Name': 'Old', 'Id': '7', 'IsUserAccessConfigurable': true},
          {
            'Name': 'Playlists',
            'Id': '19',
            'Guid': 'g19',
            'IsUserAccessConfigurable': false,
          },
        ],
      });
      final api = EmbyAdminLibraryApi(fake.dio);

      final offered = await api.getMediaFolders(isHidden: false);
      expect(
        [for (final f in offered) (f.name, f.itemId)],
        [('Movies', 'g3'), ('Old', '7')],
      );
      expect(await api.getMediaFolders(), hasLength(3));
    },
  );
}
