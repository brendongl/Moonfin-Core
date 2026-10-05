import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/repositories/item_mutation_repository.dart';
import 'package:moonfin/data/repositories/mdblist_repository.dart';
import 'package:moonfin/data/repositories/tmdb_repository.dart';
import 'package:moonfin/data/viewmodels/item_detail_view_model.dart';
import 'package:server_core/server_core.dart';

/// R4-H3 §1.1: `load()`'s `getItem()` call had no timeout at all — a server
/// that accepts the connection and then stalls the body left the detail page
/// on [ItemDetailState.loading] forever (the "Still waiting on the
/// server..." overlay never resolved to anything). This guards the fix: a
/// `getItem()` that never completes must still drive the view model to
/// [ItemDetailState.error] within a bounded time, with the plain
/// [ItemDetailViewModel.loadTimeoutMessage] text, not a raw
/// `TimeoutException`.
class _FakeItemsApi implements ItemsApi {
  @override
  Future<Map<String, dynamic>> getItem(
    String itemId, {
    String? mediaSourceId,
    String? fields,
  }) {
    // Never completes — simulates a server that stalls the response body
    // after accepting the connection.
    return Completer<Map<String, dynamic>>().future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClient implements MediaServerClient {
  final _itemsApi = _FakeItemsApi();

  @override
  ItemsApi get itemsApi => _itemsApi;

  @override
  String? get accessToken => null;

  @override
  String get baseUrl => 'http://fake';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'a getItem() that never completes drives the page to an error state, '
    'not an infinite "Still waiting on the server" hang',
    () {
      fakeAsync((async) {
        final client = _FakeClient();
        final vm = ItemDetailViewModel(
          itemId: 'item1',
          client: client,
          mutations: ItemMutationRepository(client),
          mdbListRepository: MdbListRepository(client, TmdbRepository(client)),
          tmdbRepository: TmdbRepository(client),
        );

        unawaited(vm.load());
        async.elapse(const Duration(seconds: 21));

        expect(vm.state, ItemDetailState.error);
        expect(vm.errorMessage, ItemDetailViewModel.loadTimeoutMessage);
      });
    },
  );
}
