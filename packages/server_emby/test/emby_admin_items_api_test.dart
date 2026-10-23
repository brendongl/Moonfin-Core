import 'package:server_core/server_core.dart';
import 'package:server_emby/src/api/emby_admin_items_api.dart';
import 'package:test/test.dart';

import 'admin_fake.dart';

void main() {
  test('refresh sends the modes and no trickplay flag', () async {
    final fake = AdminFake();
    await EmbyAdminItemsApi(fake.dio).refreshItem(
      '12',
      replaceAllMetadata: true,
      regenerateTrickplay: true,
      metadataRefreshMode: MetadataRefreshMode.fullRefresh,
    );

    expect(fake.last.path, '/Items/12/Refresh');
    expect(fake.last.queryParameters, {
      'MetadataRefreshMode': 'FullRefresh',
      'ImageRefreshMode': 'Default',
      'ReplaceAllMetadata': true,
    });
  });

  test('tags go out as TagItems, and only when they were sent', () async {
    final fake = AdminFake();
    final api = EmbyAdminItemsApi(fake.dio);
    await api.updateItem('12', {
      'Name': 'Sintel',
      'Tags': ['a', 'b'],
    });
    expect(fake.last.data['TagItems'], [
      {'Name': 'a'},
      {'Name': 'b'},
    ]);

    await api.updateItem('12', {'Name': 'Sintel'});
    expect((fake.last.data as Map).containsKey('TagItems'), isFalse);
  });

  test('an image is deleted by Index', () async {
    final fake = AdminFake();
    await EmbyAdminItemsApi(
      fake.dio,
    ).deleteItemImage('12', imageType: ImageType.backdrop, imageIndex: 1);

    expect(fake.last.method, 'DELETE');
    expect(fake.last.path, '/Items/12/Images/Backdrop');
    expect(fake.last.queryParameters, {'Index': 1});
  });

  test('an upload posts base64', () async {
    final fake = AdminFake();
    await EmbyAdminItemsApi(fake.dio).uploadItemImage(
      '12',
      imageType: ImageType.primary,
      bytes: [1, 2, 3],
      contentType: 'image/png',
    );

    expect(fake.last.path, '/Items/12/Images/Primary');
    expect(fake.last.data, 'AQID');
    expect(fake.last.contentType, 'image/png');
  });

  test('content type is unsupported', () {
    final fake = AdminFake();
    expect(
      () => EmbyAdminItemsApi(fake.dio).updateContentType('12', 'movies'),
      throwsUnsupportedError,
    );
    expect(fake.requests, isEmpty);
  });

  test('remote search and images read their lists', () async {
    final fake = AdminFake({
      '/Items/RemoteSearch/Game': [
        {'Name': 'Doom'},
      ],
      '/Items/12/RemoteImages': {
        'Images': [
          {'Url': 'u'},
        ],
        'Providers': ['TheMovieDb', ''],
        'TotalRecordCount': 1,
      },
    });
    final api = EmbyAdminItemsApi(fake.dio);

    expect(await api.searchRemote('game', {}), [
      {'Name': 'Doom'},
    ]);
    final images = await api.getRemoteImages(
      '12',
      imageType: ImageType.primary,
      providerName: '',
    );
    expect(fake.last.queryParameters, {'Type': 'Primary'});
    expect(images['Providers'], ['TheMovieDb']);
    expect(images['Images'], hasLength(1));
  });
}
