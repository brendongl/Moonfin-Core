import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/sipflix/sipflix_sign_in.dart';
import 'package:moonfin/sipflix/sipflix_account_probe.dart';
import 'package:moonfin/sipflix/sipflix_servers.dart';

SipflixProbeResult accepted(SipflixServerDef server) => SipflixProbeResult(
  server: server,
  outcome: SipflixProbeOutcome.accepted,
  routeUrl: server.routes.first.url,
  authResult: const {
    'AccessToken': 'fixture',
    'User': {'Id': 'fixture'},
  },
);

class Flow extends Fake implements SipflixSignIn {
  Flow(this.results);
  final List<SipflixProbeResult> results;
  Completer<bool>? remembering, connecting;
  int connects = 0;
  final released = <SipflixProbeResult>[];
  @override
  Future<List<SipflixProbeResult>> probe(
    String username,
    String password, {
    List<SipflixServerDef> servers = SipflixServers.all,
  }) async => results;
  @override
  Future<bool> remember(
    SipflixProbeResult chosen, {
    required String username,
    required String password,
  }) => remembering?.future ?? Future.value(true);
  @override
  Future<bool> connect(
    SipflixProbeResult chosen, {
    required String username,
    required String password,
  }) {
    connects++;
    return connecting?.future ?? Future.value(true);
  }

  @override
  Future<void> release(Iterable<SipflixProbeResult> unused) async {
    released.addAll(unused);
  }
}

void main() {
  Future<BuildContext> mount(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );
    return context;
  }

  testWidgets(
    'disposed screen after connect cannot navigate or acknowledge success',
    (tester) async {
      final context = await mount(tester);
      final flow = Flow([accepted(SipflixServers.delta)])
        ..connecting = Completer<bool>();
      final result = runSipflixSignIn(
        context,
        username: 'fixture',
        password: 'fixture',
        signIn: flow,
      );
      await tester.pump();
      expect(flow.connects, 1);
      await tester.pumpWidget(const SizedBox());
      flow.connecting!.complete(true);
      expect(await result, isNotNull);
      expect(flow.released, isEmpty);
    },
  );
  testWidgets(
    'expired attempt after connect is not acknowledged even when screen is mounted',
    (tester) async {
      final context = await mount(tester);
      var cancelled = false;
      final flow = Flow([accepted(SipflixServers.delta)])
        ..connecting = Completer<bool>();
      final result = runSipflixSignIn(
        context,
        username: 'fixture',
        password: 'fixture',
        signIn: flow,
        isCancelled: () => cancelled,
      );
      await tester.pump();
      cancelled = true;
      flow.connecting!.complete(true);
      expect(await result, isNotNull);
      expect(flow.connects, 1);
    },
  );
  testWidgets(
    'cancellation after remembering never connects and only releases unclaimed token',
    (tester) async {
      final context = await mount(tester);
      var cancelled = false;
      final chosen = accepted(SipflixServers.delta),
          other = accepted(SipflixServers.alphaV2);
      final flow = Flow([chosen, other])..remembering = Completer<bool>();
      final result = runSipflixSignIn(
        context,
        username: 'fixture',
        password: 'fixture',
        signIn: flow,
        isCancelled: () => cancelled,
        pickServer: (_, choices) async => chosen,
      );
      await tester.pump();
      cancelled = true;
      flow.remembering!.complete(true);
      expect(await result, isNotNull);
      expect(flow.connects, 0);
      expect(flow.released, [chosen]);
    },
  );
}
