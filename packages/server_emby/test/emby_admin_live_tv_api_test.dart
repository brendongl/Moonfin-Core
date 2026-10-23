import 'package:server_emby/src/api/emby_admin_live_tv_api.dart';
import 'package:test/test.dart';

import 'admin_fake.dart';

void main() {
  late AdminFake fake;
  late EmbyAdminLiveTvApi api;

  setUp(() {
    fake = AdminFake();
    api = EmbyAdminLiveTvApi(fake.dio);
  });

  test('tuners and providers come from their own routes', () async {
    fake.responses['/LiveTv/TunerHosts'] = [
      {'Id': 't1', 'Type': 'm3u'},
    ];
    fake.responses['/LiveTv/ListingProviders'] = [
      {'Id': 'p1', 'Type': 'xmltv'},
    ];

    expect((await api.getTunerHosts()).single['Id'], 't1');
    expect((await api.getListingProviders()).single['Id'], 'p1');
    expect(fake.requests.map((o) => o.path), [
      '/LiveTv/TunerHosts',
      '/LiveTv/ListingProviders',
    ]);
  });

  test('removals post to the delete routes with the id', () async {
    await api.removeTunerHost('t1');
    expect(fake.last.method, 'POST');
    expect(fake.last.path, '/LiveTv/TunerHosts/Delete');
    expect(fake.last.queryParameters, {'Id': 't1'});

    await api.removeListingProvider('p1');
    expect(fake.last.method, 'POST');
    expect(fake.last.path, '/LiveTv/ListingProviders/Delete');
    expect(fake.last.queryParameters, {'Id': 'p1'});
  });

  test('discovery sends no filter', () async {
    await api.discoverTuners();

    expect(fake.last.path, '/LiveTv/Tuners/Discover');
    expect(fake.last.queryParameters, isEmpty);
  });

  test('a provider add only sends the checks it asks for', () async {
    fake.responses['/LiveTv/ListingProviders'] = {'Id': 'new'};

    final added = await api.addListingProvider({
      'Type': 'xmltv',
      'Path': '/guide.xml',
    }, validateListings: true);

    expect(added['Id'], 'new');
    expect(fake.last.queryParameters, {'ValidateListings': true});
    expect(fake.last.data, {'Type': 'xmltv', 'Path': '/guide.xml'});
  });

  test('Schedules Direct countries are unsupported', () async {
    await expectLater(
      api.getSchedulesDirectCountries(),
      throwsUnsupportedError,
    );
    expect(fake.requests, isEmpty);
  });

  test(
    'lineups send a saved provider id, else the Emby Guide Data type',
    () async {
      await api.getListingProviderLineups(
        providerId: 'p1',
        location: '10001',
        country: 'USA',
      );
      expect(fake.last.queryParameters, {
        'Id': 'p1',
        'Location': '10001',
        'Country': 'USA',
      });

      await api.getListingProviderLineups(location: '10001', country: 'USA');
      expect(fake.last.queryParameters, {
        'Type': 'embygn',
        'Location': '10001',
        'Country': 'USA',
      });
    },
  );

  test('a mapping puts the provider in the query', () async {
    fake.responses['/LiveTv/ChannelMappings'] = {'IsManualMapping': true};

    final result = await api.setChannelMapping('p1', 'm1', 'verify.one');

    expect(result['IsManualMapping'], isTrue);
    expect(fake.last.method, 'POST');
    expect(fake.last.queryParameters, {'ProviderId': 'p1'});
    expect(fake.last.data, {
      'TunerChannelId': 'm1',
      'ProviderChannelId': 'verify.one',
    });

    await api.getChannelMappingOptions('p1');
    expect(fake.last.path, '/LiveTv/ChannelMappingOptions');
    expect(fake.last.queryParameters, {'ProviderId': 'p1'});
  });
}
