import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../auth/repositories/server_repository.dart';
import '../../sipflix/sipflix_connection_manager.dart';
import '../../sipflix/sipflix_servers.dart';
import 'playback/player_loading_overlay.dart';

/// Sipflix: the detail page's loading state, said out loud.
///
/// This screen is ONE network call — `itemsApi.getItem` — after which the page
/// is drawn and everything else (ratings, seasons, similar, extras) streams in
/// behind it, unawaited. So there is no long list of steps to narrate honestly;
/// what matters when it hangs for 5-10s is WHICH server it is waiting on and
/// HOW LONG it has been waiting, because the customer reads that back to
/// support verbatim.
class SipflixDetailLoading extends StatefulWidget {
  const SipflixDetailLoading({super.key, this.logoSize = 120});

  final double logoSize;

  @override
  State<SipflixDetailLoading> createState() => _SipflixDetailLoadingState();
}

class _SipflixDetailLoadingState extends State<SipflixDetailLoading> {
  /// Below this the wait is unremarkable and a stopwatch would just be noise.
  static const _slowAfter = Duration(seconds: 4);

  late final DateTime _start;
  Timer? _ticker;
  int _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _start = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = DateTime.now().difference(_start).inSeconds);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// The route this request is going over, so a stuck page names the path.
  String? get _routeLabel {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<ServerRepository>()) return null;
    final server = SipflixServers.findServer(getIt<ServerRepository>().servers);
    if (server == null) return null;
    return SipflixConnectionManager.currentRoute(server).label;
  }

  @override
  Widget build(BuildContext context) {
    final route = _routeLabel;
    final slow = _elapsed >= _slowAfter.inSeconds;
    final detail = StringBuffer();
    if (route != null) detail.write('via $route');
    if (slow) {
      if (detail.isNotEmpty) detail.write('  ·  ');
      detail.write('waiting ${_elapsed}s');
    }

    return Center(
      child: PlayerLoadingOverlay(
        customSize: widget.logoSize,
        label: slow
            ? 'Still waiting on the server...'
            : 'Loading title details...',
        detail: detail.isEmpty ? null : detail.toString(),
      ),
    );
  }
}
