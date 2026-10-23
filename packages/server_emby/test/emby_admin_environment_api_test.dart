import 'package:dio/dio.dart';
import 'package:server_emby/src/api/emby_admin_environment_api.dart';
import 'package:test/test.dart';

import 'admin_fake.dart';

void main() {
  test('validate path spells ValidateWriteable', () async {
    final fake = AdminFake();
    await EmbyAdminEnvironmentApi(
      fake.dio,
    ).validatePath('/media', writable: true);

    expect(fake.last.data, {'ValidateWriteable': true, 'Path': '/media'});
  });

  test('parent path is read as text and empty means none', () async {
    final fake = AdminFake({'/Environment/ParentPath': '/media'});
    final api = EmbyAdminEnvironmentApi(fake.dio);

    expect(await api.getParentPath('/media/Movies'), '/media');
    expect(fake.last.responseType, ResponseType.plain);
    expect(fake.last.queryParameters, {'Path': '/media/Movies'});

    final root = AdminFake({'/Environment/ParentPath': ''});
    expect(await EmbyAdminEnvironmentApi(root.dio).getParentPath('/'), isNull);
  });

  test('directory contents pass only the flags given', () async {
    final fake = AdminFake({'/Environment/DirectoryContents': <dynamic>[]});
    await EmbyAdminEnvironmentApi(
      fake.dio,
    ).getDirectoryContents('/media', includeDirectories: true);

    expect(fake.last.queryParameters, {
      'Path': '/media',
      'IncludeDirectories': true,
    });
  });
}
