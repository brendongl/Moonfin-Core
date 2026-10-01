import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/repositories/search_repository.dart';
import 'package:moonfin/data/viewmodels/search_view_model.dart';
import 'package:server_core/server_core.dart';

class _MockSearchRepository extends Mock implements SearchRepository {}

class _MockClient extends Mock implements MediaServerClient {}

AggregatedItem _item(String id, String type) => AggregatedItem(
  id: id,
  serverId: 's',
  rawData: {'Id': id, 'Name': id, 'Type': type},
);

DioException _gatewayTimeout() {
  final options = RequestOptions(path: '/Items');
  return DioException.badResponse(
    statusCode: 504,
    requestOptions: options,
    response: Response(requestOptions: options, statusCode: 504),
  );
}

Future<void> _runSearch(SearchViewModel vm, String query) {
  final done = Completer<void>();
  void listener() {
    if (vm.state == SearchState.ready || vm.state == SearchState.error) {
      if (!done.isCompleted) done.complete();
    }
  }

  vm.addListener(listener);
  vm.searchImmediate(query);
  return done.future.whenComplete(() => vm.removeListener(listener));
}

void main() {
  late _MockSearchRepository repo;
  late _MockClient client;

  setUp(() {
    repo = _MockSearchRepository();
    client = _MockClient();
    when(() => client.gamesApi).thenReturn(null);
    when(
      () => repo.searchPeople(any(), limit: any(named: 'limit')),
    ).thenAnswer((_) async => const []);
    when(() => repo.fetchLiveTvChannels()).thenAnswer((_) async => const []);
  });

  void answerBuckets(
    Future<List<AggregatedItem>> Function(List<String> types) answer,
  ) {
    when(
      () => repo.search(
        any(),
        includeItemTypes: any(named: 'includeItemTypes'),
        parentId: any(named: 'parentId'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer(
      (inv) => answer(inv.namedArguments[#includeItemTypes] as List<String>),
    );
  }

  test('never sends one all-types search', () async {
    final asked = <List<String>?>[];
    when(
      () => repo.search(
        any(),
        includeItemTypes: any(named: 'includeItemTypes'),
        parentId: any(named: 'parentId'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((inv) async {
      asked.add(inv.namedArguments[#includeItemTypes] as List<String>?);
      return const [];
    });

    await _runSearch(SearchViewModel(repo, client), 'slow horses');

    expect(asked, isNotEmpty);
    expect(asked.every((t) => t != null && t.isNotEmpty), isTrue);
    expect(
      asked.expand((t) => t!),
      containsAll(['Movie', 'Series', 'Episode']),
    );
  });

  test('keeps movie results when the episode search times out', () async {
    answerBuckets((types) async {
      if (types.contains('Episode')) throw _gatewayTimeout();
      if (types.contains('Series')) return [_item('sh', 'Series')];
      return const [];
    });

    final vm = SearchViewModel(repo, client);
    await _runSearch(vm, 'slow horses');

    expect(vm.state, SearchState.ready);
    final series = vm.results.expand((g) => g.items).map((i) => i.id);
    expect(series, contains('sh'));
  });

  test('shows a plain message when every search fails', () async {
    answerBuckets((_) async => throw _gatewayTimeout());

    final vm = SearchViewModel(repo, client);
    await _runSearch(vm, 'slow horses');

    expect(vm.state, SearchState.error);
    expect(vm.errorMessage, isNot(contains('DioException')));
    expect(vm.errorMessage, contains("Couldn't reach the server"));
  });

  group('a part that stalls', () {
    setUp(() => SearchViewModel.partDeadline = const Duration(milliseconds: 50));
    tearDown(
      () => SearchViewModel.partDeadline = const Duration(seconds: 20),
    );

    test('does not hold back the parts that answered', () async {
      answerBuckets((types) {
        if (types.contains('Episode')) {
          return Completer<List<AggregatedItem>>().future;
        }
        if (types.contains('Series')) {
          return Future.value([_item('sh', 'Series')]);
        }
        return Future.value(const <AggregatedItem>[]);
      });
      when(
        () => repo.searchPeople(any(), limit: any(named: 'limit')),
      ).thenAnswer((_) => Completer<List<AggregatedItem>>().future);

      final vm = SearchViewModel(repo, client);
      await _runSearch(vm, 'slow horses').timeout(const Duration(seconds: 5));

      expect(vm.state, SearchState.ready);
      expect(vm.results.expand((g) => g.items).map((i) => i.id), contains('sh'));
    });

    test('ends in the plain message when nothing answers', () async {
      answerBuckets((_) => Completer<List<AggregatedItem>>().future);

      final vm = SearchViewModel(repo, client);
      await _runSearch(vm, 'slow horses').timeout(const Duration(seconds: 5));

      expect(vm.state, SearchState.error);
      expect(vm.errorMessage, contains("Couldn't reach the server"));
    });
  });
}
