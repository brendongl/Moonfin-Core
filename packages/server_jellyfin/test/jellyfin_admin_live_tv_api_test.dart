import 'package:dio/dio.dart';
import 'package:server_jellyfin/src/api/jellyfin_admin_live_tv_api.dart';
import 'package:test/test.dart';

class _FakeServer extends Interceptor {
  _FakeServer(this.handle);

  final void Function(RequestOptions options, RequestInterceptorHandler handler)
  handle;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) =>
      handle(options, handler);
}

void main() {
  final requests = <RequestOptions>[];
  Object? reply;
  var status = 200;
  late JellyfinAdminLiveTvApi api;

  setUp(() {
    requests.clear();
    reply = null;
    status = 200;
    final dio = Dio()
      ..interceptors.add(
        _FakeServer((options, handler) {
          requests.add(options);
          final response = Response<dynamic>(
            requestOptions: options,
            statusCode: status,
            data: reply,
          );
          if (status >= 400) {
            handler.reject(
              DioException.badResponse(
                statusCode: status,
                requestOptions: options,
                response: response,
              ),
            );
          } else {
            handler.resolve(response);
          }
        }),
      );
    api = JellyfinAdminLiveTvApi(dio);
  });

  test('a mapping posts one tuner and provider channel pair', () async {
    reply = {'Id': 't1', 'ProviderChannelId': 'p1'};
    final mapping = await api.setChannelMapping('prov', 't1', 'p1');

    expect(requests.single.method, 'POST');
    expect(requests.single.path, '/LiveTv/ChannelMappings');
    expect(requests.single.data, {
      'ProviderId': 'prov',
      'TunerChannelId': 't1',
      'ProviderChannelId': 'p1',
    });
    expect(mapping['ProviderChannelId'], 'p1');
  });

  test('mapping options are read per provider', () async {
    reply = {'TunerChannels': [], 'ProviderName': 'XmlTV'};
    await api.getChannelMappingOptions('prov');

    expect(requests.single.path, '/LiveTv/ChannelMappingOptions');
    expect(requests.single.queryParameters, {'providerId': 'prov'});
  });

  test('discovery asks for new devices only', () async {
    reply = [];
    await api.discoverTuners();

    expect(requests.single.path, '/LiveTv/Tuners/Discover');
    expect(requests.single.queryParameters, {'NewDevicesOnly': true});
  });

  test('a 404 surfaces at once, with no retry on a made-up path', () async {
    status = 404;
    reply = {'message': 'File not found'};

    await expectLater(
      api.addTunerHost({'Type': 'm3u', 'Url': '/missing.m3u'}),
      throwsA(isA<DioException>()),
    );
    expect(requests.map((r) => r.path), ['/LiveTv/TunerHosts']);
  });

  test('livetv is read and saved under its own key only', () async {
    reply = {'TunerHosts': []};
    await api.getLiveTvConfiguration();
    await api.updateLiveTvConfiguration({'GuideDays': 4});

    expect(requests.map((r) => '${r.method} ${r.path}'), [
      'GET /System/Configuration/livetv',
      'POST /System/Configuration/livetv',
    ]);
  });

  test('countries keep the Schedules Direct keys, sorted, without ZZZ', () async {
    reply = {
      'North America': [
        {'fullName': 'United States', 'shortName': 'USA'},
        {'fullName': 'Canada', 'shortName': 'CAN'},
      ],
      'ZZZ': [
        {'fullName': 'Test', 'shortName': 'ZZZ'},
      ],
    };
    final countries = await api.getSchedulesDirectCountries();

    expect(countries.map((c) => c['shortName']), ['CAN', 'USA']);
  });

  test('a new XMLTV provider is read from the server default', () async {
    reply = {'MovieCategories': ['movie']};
    final info = await api.getDefaultListingProvider();

    expect(requests.single.path, '/LiveTv/ListingProviders/Default');
    expect(info['MovieCategories'], ['movie']);
  });

  test('a provider validation flag goes out as ValidateListings', () async {
    reply = {'Id': 'x'};
    await api.addListingProvider({'Type': 'xmltv'}, validateListings: true);

    expect(requests.single.queryParameters, {'ValidateListings': true});
  });
}
