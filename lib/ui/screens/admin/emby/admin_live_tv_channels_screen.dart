import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../util/error_message.dart';
import '../widgets/admin_form_styles.dart';
import '../widgets/premiere_note.dart';

/// Emby's channel list in the channel order. Each change saves at once.
class AdminLiveTvChannelsScreen extends StatefulWidget {
  const AdminLiveTvChannelsScreen({super.key});

  @override
  State<AdminLiveTvChannelsScreen> createState() =>
      _AdminLiveTvChannelsScreenState();
}

class _AdminLiveTvChannelsScreenState extends State<AdminLiveTvChannelsScreen> {
  static const _pageSize = 100;

  EmbyAdminApi get _api => GetIt.instance<MediaServerClient>().embyAdminApi!;

  List<Map<String, dynamic>> _channels = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _busyId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<Map<String, dynamic>>> _fetch(int start, int limit) async {
    final page = await _api.getManagedChannels(startIndex: start, limit: limit);
    _total = (page['TotalRecordCount'] as num?)?.toInt() ?? 0;
    return [
      for (final c in (page['Items'] as List? ?? const []).whereType<Map>())
        Map<String, dynamic>.from(c),
    ];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final channels = await _fetch(0, _pageSize);
      if (!mounted) return;
      setState(() {
        _channels = channels;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeError(e, AppLocalizations.of(context));
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final more = await _fetch(_channels.length, _pageSize);
      if (mounted) setState(() => _channels = [..._channels, ...more]);
    } catch (e) {
      _failed(e);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _failed(Object e) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.adminFailed(describeError(e, l10n)))),
    );
  }

  /// Runs [action] on [channel] and reloads the loaded channels. A move
  /// renumbers the ones in between, and the server drops a channel's item when
  /// it's turned off and makes one with a new id when it's turned back on.
  Future<void> _change(
    Map<String, dynamic> channel,
    Future<void> Function() action,
  ) async {
    setState(() => _busyId = '${channel['Id']}');
    try {
      await action();
      final channels = await _fetch(0, _channels.length);
      if (mounted) setState(() => _channels = channels);
    } catch (e) {
      _failed(e);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _setDisabled(Map<String, dynamic> channel, bool disabled) =>
      _change(
        channel,
        () => _api.setChannelDisabled(
          '${channel['Id']}',
          managementId: '${channel['ManagementId']}',
          disabled: disabled,
        ),
      );

  Future<void> _move(int index, int delta) {
    final channel = _channels[index];
    return _change(
      channel,
      () => _api.setChannelSortIndex(
        '${channel['Id']}',
        managementId: '${channel['ManagementId']}',
        newIndex: index + delta,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.adminLiveTvLoadFailed,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: _load, child: Text(l10n.retry)),
          ],
        ),
      );
    }

    final hasMore = _channels.length < _total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: adminScreenHeader(
            context,
            title: l10n.adminDrawerLiveTvChannels,
            icon: Icons.format_list_numbered,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: PremiereNote(message: (l) => l.adminPremiereNoteLiveTv),
        ),
        Expanded(
          child: _channels.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l10n.adminLiveTvChannelsEmpty,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    MediaQuery.paddingOf(context).bottom + 40,
                  ),
                  itemCount: _channels.length + (hasMore ? 1 : 0),
                  itemBuilder: (context, index) => index == _channels.length
                      ? Center(
                          child: _loadingMore
                              ? const CircularProgressIndicator()
                              : OutlinedButton(
                                  onPressed: _loadMore,
                                  child: Text(l10n.showMore),
                                ),
                        )
                      : _channelRow(index, l10n),
                ),
        ),
      ],
    );
  }

  Widget _channelRow(int index, AppLocalizations l10n) {
    final channel = _channels[index];
    final disabled = channel['Disabled'] == true;
    final busy = _busyId == '${channel['Id']}';
    final idle = _busyId == null;
    final number = '${channel['ChannelNumber'] ?? ''}';
    final mapped = '${channel['ListingsChannelName'] ?? ''}';
    final subtitle = [number, mapped].where((t) => t.isNotEmpty).join(' - ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: adminListCard(
        child: ListTile(
          leading: Switch.adaptive(
            value: !disabled,
            onChanged: idle ? (on) => _setDisabled(channel, !on) : null,
          ),
          title: Text(
            '${channel['Name'] ?? ''}',
            style: disabled
                ? TextStyle(color: Theme.of(context).disabledColor)
                : null,
          ),
          subtitle: subtitle.isEmpty ? null : Text(subtitle),
          trailing: busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: l10n.moveUp,
                      icon: const Icon(Icons.keyboard_arrow_up),
                      onPressed: idle && index > 0
                          ? () => _move(index, -1)
                          : null,
                    ),
                    IconButton(
                      tooltip: l10n.moveDown,
                      icon: const Icon(Icons.keyboard_arrow_down),
                      onPressed: idle && index < _total - 1
                          ? () => _move(index, 1)
                          : null,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
