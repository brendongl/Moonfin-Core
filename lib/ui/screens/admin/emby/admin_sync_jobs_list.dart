import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../util/error_message.dart';
import '../../../widgets/adaptive/adaptive_dialog.dart';
import '../widgets/admin_form_styles.dart';

/// Emby's conversion and download jobs, each of which an admin can cancel.
class AdminSyncJobsList extends StatefulWidget {
  const AdminSyncJobsList({super.key});

  @override
  State<AdminSyncJobsList> createState() => _AdminSyncJobsListState();
}

class _AdminSyncJobsListState extends State<AdminSyncJobsList> {
  EmbyAdminApi get _api => GetIt.instance<MediaServerClient>().embyAdminApi!;
  List<Map<String, dynamic>>? _conversions;
  List<Map<String, dynamic>>? _downloads;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _api.getSyncJobs(conversions: true),
        _api.getSyncJobs(conversions: false),
      ]);
      if (!mounted) return;
      setState(() {
        _conversions = results[0];
        _downloads = results[1];
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = describeError(e, AppLocalizations.of(context)));
    }
  }

  Future<void> _cancel(Map<String, dynamic> job) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: Text(l10n.adminSyncJobCancel),
        content: Text(l10n.adminSyncJobCancelConfirm('${job['Name'] ?? ''}')),
        actions: [
          adaptiveDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          adaptiveDialogAction(
            isDestructive: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.adminSyncJobCancel),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _api.cancelSyncJob('${job['Id']}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.adminCommandFailed(describeError(e, l10n))),
        ),
      );
    }
    await _load();
  }

  String? _status(AppLocalizations l10n, Object? status) => switch (status) {
    'Queued' => l10n.queuedDownload,
    'Converting' => l10n.adminSyncJobConverting,
    'ReadyToTransfer' => l10n.adminSyncJobReady,
    'Transferring' => l10n.adminSyncJobTransferring,
    'Completed' => l10n.completedStatus,
    'CompletedWithError' => l10n.adminSyncJobCompletedWithError,
    'Failed' => l10n.failedStatus,
    _ => status?.toString(),
  };

  Widget _job(AppLocalizations l10n, Map<String, dynamic> job) {
    final progress = (job['Progress'] as num?)?.toDouble();
    final details = [
      job['TargetName'],
      _status(l10n, job['Status']),
      if (job['ItemCount'] case final int count)
        l10n.adminSyncJobItemCount(count),
    ].whereType<String>().where((s) => s.isNotEmpty);
    return ListTile(
      title: Text('${job['Name'] ?? ''}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(details.join(' · ')),
          if (progress != null && progress > 0 && progress < 100)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(value: progress / 100),
            ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.cancel_outlined),
        tooltip: l10n.adminSyncJobCancel,
        onPressed: () => _cancel(job),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_error != null) {
      return adminSection(
        context,
        title: l10n.adminSyncJobsConversions,
        icon: Icons.sync_outlined,
        children: [
          ListTile(
            title: Text(_error!),
            trailing: TextButton(onPressed: _load, child: Text(l10n.retry)),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (title, icon, jobs) in [
          (l10n.adminSyncJobsConversions, Icons.sync_outlined, _conversions),
          (l10n.adminSyncJobsDownloads, Icons.download_outlined, _downloads),
        ])
          adminSection(
            context,
            title: title,
            icon: icon,
            children: [
              if (jobs == null)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (jobs.isEmpty)
                ListTile(title: Text(l10n.adminSyncJobsEmpty))
              else
                for (final job in jobs) _job(l10n, job),
            ],
          ),
      ],
    );
  }
}
