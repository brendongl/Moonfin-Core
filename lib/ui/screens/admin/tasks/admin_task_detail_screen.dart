import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../providers/admin_user_providers.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../util/error_message.dart';
import '../../../widgets/adaptive/adaptive_dialog.dart';
import '../widgets/admin_form_styles.dart';
import 'admin_tasks_screen.dart';

const _ticksPerMinute = 600000000;
const _ticksPerHour = 60 * _ticksPerMinute;

/// A trigger time of day in the locale's own format.
String _timeOfDayText(BuildContext context, int ticks) {
  final minutes = ticks ~/ _ticksPerMinute;
  return MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay(hour: minutes ~/ 60 % 24, minute: minutes % 60),
  );
}

String _dayName(String day, AppLocalizations l10n) => switch (day) {
      'Sunday' => l10n.adminDaySunday,
      'Monday' => l10n.adminDayMonday,
      'Tuesday' => l10n.adminDayTuesday,
      'Wednesday' => l10n.adminDayWednesday,
      'Thursday' => l10n.adminDayThursday,
      'Friday' => l10n.adminDayFriday,
      'Saturday' => l10n.adminDaySaturday,
      _ => day,
    };

/// 1.5 for 90 minutes, 2 for two hours.
String _hoursNumber(double hours) => hours == hours.roundToDouble()
    ? '${hours.round()}'
    : hours.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

/// An hour count that may be fractional.
String _hoursText(double hours, AppLocalizations l10n) =>
    hours == hours.roundToDouble()
        ? l10n.adminTaskTriggerHours(hours.round())
        : l10n.adminTaskHoursValue(_hoursNumber(hours));

class AdminTaskDetailScreen extends ConsumerStatefulWidget {
  final String taskId;
  const AdminTaskDetailScreen({super.key, required this.taskId});

  @override
  ConsumerState<AdminTaskDetailScreen> createState() =>
      _AdminTaskDetailScreenState();
}

class _AdminTaskDetailScreenState
    extends ConsumerState<AdminTaskDetailScreen> {
  AdminTasksApi get _api =>
      GetIt.instance<MediaServerClient>().adminTasksApi;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final taskAsync = ref.watch(adminTaskProvider(widget.taskId));

    return taskAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.adminTaskLoadFailed(describeError(error, l10n))),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => ref
                ..invalidate(adminTasksProvider)
                ..invalidate(adminTaskByIdProvider(widget.taskId)),
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
      data: (task) => _buildContent(context, task),
    );
  }

  Widget _buildContent(BuildContext context, TaskInfo task) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isRunning = task.state == 'Running';
    final isCancelling = task.state == 'Cancelling';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      children: [
        adminScreenHeader(
          context,
          title: task.name,
          subtitle: task.description,
          icon: Icons.task_alt_outlined,
        ),
        if (task.category != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Chip(label: Text(task.category!)),
          ),
          const SizedBox(height: 16),
        ],

        adminSectionLabel(context, l10n.status, icon: Icons.info_outline),
        adminGlassGroup(
          context,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isRunning
                          ? Icons.sync
                          : isCancelling
                              ? Icons.hourglass_top
                              : Icons.check_circle_outline,
                      color: isRunning
                          ? theme.colorScheme.primary
                          : isCancelling
                              ? AppColorScheme.recordingScheduled
                              : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(task.state, style: theme.textTheme.bodyLarge),
                    const Spacer(),
                    if (isRunning || isCancelling)
                      FilledButton.tonalIcon(
                        onPressed: isCancelling
                            ? null
                            : () => _stopTask(task.id),
                        icon: const Icon(Icons.stop),
                        label: Text(l10n.adminTaskStop),
                      )
                    else
                      FilledButton.tonalIcon(
                        onPressed: () => _startTask(task.id),
                        icon: const Icon(Icons.play_arrow),
                        label: Text(l10n.adminRunNow),
                      ),
                  ],
                ),
                if ((isRunning || isCancelling) &&
                    task.currentProgressPercentage != null) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                      value: task.currentProgressPercentage! / 100),
                  const SizedBox(height: 4),
                  Text(
                      '${task.currentProgressPercentage!.toStringAsFixed(1)}%'),
                ],
              ],
            ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (task.lastExecutionResult != null) ...[
          _LastExecutionCard(result: task.lastExecutionResult!),
          const SizedBox(height: 12),
        ],

        _TriggersSection(
          triggers: task.triggers,
          onAdd: () => _showAddTriggerDialog(task),
          onRemove: (index) => _removeTrigger(task, index),
        ),
      ],
    );
  }

  Future<void> _startTask(String taskId) async {
    try {
      await _api.startTask(taskId);
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.adminTaskStartFailed(describeError(e, l10n)))));
      }
    }
  }

  Future<void> _stopTask(String taskId) async {
    try {
      await _api.stopTask(taskId);
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.adminTaskStopFailed(describeError(e, l10n)))));
      }
    }
  }

  Future<void> _removeTrigger(TaskInfo task, int index) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: Text(l10n.adminDeleteTaskTrigger),
        content: Text(l10n.adminDeleteTaskTriggerConfirm),
        actions: [
          adaptiveDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final triggers = List<TaskTriggerInfo>.from(task.triggers)
      ..removeAt(index);
    try {
      await _api.updateTaskTriggers(
        task.id,
        triggers.map((t) => t.toJson()).toList(),
      );
      ref
        ..invalidate(adminTasksProvider)
        ..invalidate(adminTaskByIdProvider(widget.taskId));
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.adminTriggerRemoveFailed(describeError(e, l10n)))));
      }
    }
  }

  Future<void> _showAddTriggerDialog(TaskInfo task) async {
    final trigger = await showDialog<TaskTriggerInfo>(
      context: context,
      builder: (context) => const _AddTriggerDialog(),
    );
    if (trigger == null || !mounted) return;

    final triggers = [...task.triggers, trigger];
    try {
      await _api.updateTaskTriggers(
        task.id,
        triggers.map((t) => t.toJson()).toList(),
      );
      ref
        ..invalidate(adminTasksProvider)
        ..invalidate(adminTaskByIdProvider(widget.taskId));
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.adminTriggerAddFailed(describeError(e, l10n)))));
      }
    }
  }
}

class _LastExecutionCard extends StatelessWidget {
  final TaskResult result;
  const _LastExecutionCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final duration = result.endTime.difference(result.startTime);

    Color statusColor;
    switch (result.status) {
      case 'Completed':
        statusColor = AppColorScheme.statusAvailable;
      case 'Failed':
        statusColor = theme.colorScheme.error;
      case 'Cancelled':
      case 'Aborted':
        statusColor = AppColorScheme.recordingScheduled;
      default:
        statusColor = theme.colorScheme.onSurfaceVariant;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        adminSectionLabel(context, l10n.adminTaskDetailLastExecution,
            icon: Icons.history),
        adminGlassGroup(
          context,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.circle, size: 10, color: statusColor),
                      const SizedBox(width: 8),
                      Text(result.status,
                          style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _infoRow(l10n.adminTaskDetailStarted,
                      _formatDateTime(result.startTime)),
                  _infoRow(l10n.adminTaskDetailEnded,
                      _formatDateTime(result.endTime)),
                  _infoRow(l10n.adminTaskDetailDuration,
                      taskDurationText(duration, l10n)),
                  if (result.errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(l10n.adminTaskDetailErrorLabel,
                        style: TextStyle(color: theme.colorScheme.error)),
                    const SizedBox(height: 4),
                    Text(result.errorMessage!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
                width: 80,
                child: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w500))),
            Text(value),
          ],
        ),
      );

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-${_p(local.month)}-${_p(local.day)} '
        '${_p(local.hour)}:${_p(local.minute)}:${_p(local.second)}';
  }

  String _p(int n) => n.toString().padLeft(2, '0');
}

class _TriggersSection extends StatelessWidget {
  final List<TaskTriggerInfo> triggers;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;

  const _TriggersSection({
    required this.triggers,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: adminSectionLabel(context, l10n.adminTriggers,
                  icon: Icons.schedule),
            ),
            FilledButton.tonalIcon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(l10n.adminAddTrigger),
            ),
          ],
        ),
        if (triggers.isEmpty)
          adminGlassGroup(
            context,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 20),
                child: Text(l10n.adminNoTriggers,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ),
            ],
          )
        else
          adminGlassGroup(
            context,
            children: [
              ...triggers.asMap().entries.map((entry) {
                final i = entry.key;
                final trigger = entry.value;
                return ListTile(
                  leading: Icon(_triggerIcon(trigger.type)),
                  title: Text(_triggerDescription(context, trigger, l10n)),
                  subtitle: trigger.maxRuntimeTicks != null
                      ? Text(l10n.adminTimeLimitDuration(_hoursText(
                          trigger.maxRuntimeTicks! / _ticksPerHour, l10n)))
                      : null,
                  // Emby's system event triggers can't be made here, so they
                  // stay as they are.
                  trailing: trigger.type == 'SystemEventTrigger'
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: l10n.delete,
                          onPressed: () => onRemove(i),
                        ),
                );
              }),
            ],
          ),
      ],
    );
  }

  IconData _triggerIcon(String type) {
    switch (type) {
      case 'DailyTrigger':
        return Icons.today;
      case 'WeeklyTrigger':
        return Icons.calendar_view_week;
      case 'IntervalTrigger':
        return Icons.timer;
      case 'StartupTrigger':
        return Icons.power_settings_new;
      case 'SystemEventTrigger':
        return Icons.bolt_outlined;
      default:
        return Icons.schedule;
    }
  }

  String _triggerDescription(
    BuildContext context,
    TaskTriggerInfo trigger,
    AppLocalizations l10n,
  ) {
    switch (trigger.type) {
      case 'DailyTrigger':
        return l10n.adminTaskTriggerDaily(
            _timeOfDayText(context, trigger.timeOfDayTicks ?? 0));
      case 'WeeklyTrigger':
        return l10n.adminTaskTriggerWeekly(
          _dayName(trigger.dayOfWeek ?? l10n.unknown, l10n),
          _timeOfDayText(context, trigger.timeOfDayTicks ?? 0),
        );
      case 'IntervalTrigger':
        return _intervalText(trigger.intervalTicks ?? 0, l10n);
      case 'StartupTrigger':
        return l10n.adminTaskTriggerStartup;
      case 'SystemEventTrigger':
        return l10n.adminTaskTriggerSystemEvent(
          trigger.systemEvent ?? l10n.unknown,
        );
      default:
        return trigger.type;
    }
  }
}

String _intervalText(int ticks, AppLocalizations l10n) {
  if (ticks < _ticksPerHour) {
    return l10n.adminTaskTriggerEveryMinutes('${ticks ~/ _ticksPerMinute}');
  }
  if (ticks == _ticksPerHour) return l10n.adminTaskTriggerEveryHour;
  return l10n.adminTaskTriggerEveryHours(_hoursNumber(ticks / _ticksPerHour));
}

class _AddTriggerDialog extends StatefulWidget {
  const _AddTriggerDialog();

  @override
  State<_AddTriggerDialog> createState() => _AddTriggerDialogState();
}

class _AddTriggerDialogState extends State<_AddTriggerDialog> {
  String _type = 'DailyTrigger';
  int _timeOfDayTicks = 0;
  String _dayOfWeek = 'Sunday';
  int _intervalTicks = _intervals.first;
  final _timeLimit = TextEditingController();

  static const _daysOfWeek = [
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  static const _intervals = [
    15 * _ticksPerMinute,
    30 * _ticksPerMinute,
    45 * _ticksPerMinute,
    1 * _ticksPerHour,
    2 * _ticksPerHour,
    3 * _ticksPerHour,
    4 * _ticksPerHour,
    6 * _ticksPerHour,
    8 * _ticksPerHour,
    12 * _ticksPerHour,
    24 * _ticksPerHour,
  ];

  @override
  void dispose() {
    _timeLimit.dispose();
    super.dispose();
  }

  /// Hours typed in the time limit field, null unless it's at least 1 and a
  /// multiple of 0.5.
  double? get _timeLimitHours {
    final hours = double.tryParse(_timeLimit.text.trim().replaceAll(',', '.'));
    return hours != null && hours >= 1 && hours * 2 == (hours * 2).roundToDouble()
        ? hours
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final triggerTypes = {
      'DailyTrigger': l10n.adminTaskTriggerTypeDaily,
      'WeeklyTrigger': l10n.adminTaskTriggerTypeWeekly,
      'IntervalTrigger': l10n.adminTaskTriggerTypeInterval,
      'StartupTrigger': l10n.adminTaskTriggerStartup,
    };
    final limitText = _timeLimit.text.trim();
    final limitValid = limitText.isEmpty || _timeLimitHours != null;
    return AlertDialog.adaptive(
      title: Text(l10n.adminAddTrigger),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _type,
              isExpanded: true,
              decoration: adminInputDecoration(label: l10n.adminTriggerType),
              items: triggerTypes.entries
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: 16),
            ..._buildTypeFields(),
            const SizedBox(height: 16),
            TextField(
              controller: _timeLimit,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: adminInputDecoration(
                label: l10n.adminTimeLimitHours,
                hint: l10n.adminNoLimit,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        adaptiveDialogAction(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: limitValid ? _save : null,
          child: Text(l10n.add),
        ),
      ],
    );
  }

  List<Widget> _buildTypeFields() {
    final l10n = AppLocalizations.of(context);
    switch (_type) {
      case 'DailyTrigger':
        return [_buildTimeField(l10n)];
      case 'WeeklyTrigger':
        return [
          DropdownButtonFormField<String>(
            initialValue: _dayOfWeek,
            isExpanded: true,
            decoration: adminInputDecoration(label: l10n.adminDayOfWeek),
            items: _daysOfWeek
                .map((d) =>
                    DropdownMenuItem(value: d, child: Text(_dayName(d, l10n))))
                .toList(),
            onChanged: (v) => setState(() => _dayOfWeek = v!),
          ),
          const SizedBox(height: 16),
          _buildTimeField(l10n),
        ];
      case 'IntervalTrigger':
        return [
          DropdownButtonFormField<int>(
            initialValue: _intervalTicks,
            isExpanded: true,
            decoration: adminInputDecoration(
                label: l10n.adminTaskTriggerIntervalLabel),
            items: [
              for (final ticks in _intervals)
                DropdownMenuItem(
                  value: ticks,
                  child: Text(ticks < _ticksPerHour
                      ? l10n.adminTaskMinutesValue('${ticks ~/ _ticksPerMinute}')
                      : l10n.adminTaskTriggerHours(ticks ~/ _ticksPerHour)),
                ),
            ],
            onChanged: (v) => setState(() => _intervalTicks = v!),
          ),
        ];
      default:
        return [];
    }
  }

  Widget _buildTimeField(AppLocalizations l10n) {
    return DropdownButtonFormField<int>(
      initialValue: _timeOfDayTicks,
      isExpanded: true,
      decoration: adminInputDecoration(label: l10n.adminTaskTriggerTime),
      items: [
        for (var minutes = 0; minutes < 24 * 60; minutes += 15)
          DropdownMenuItem(
            value: minutes * _ticksPerMinute,
            child: Text(_timeOfDayText(context, minutes * _ticksPerMinute)),
          ),
      ],
      onChanged: (v) => setState(() => _timeOfDayTicks = v!),
    );
  }

  void _save() {
    final hours = _timeLimitHours;
    final trigger = TaskTriggerInfo(
      type: _type,
      timeOfDayTicks: _type == 'DailyTrigger' || _type == 'WeeklyTrigger'
          ? _timeOfDayTicks
          : null,
      intervalTicks: _type == 'IntervalTrigger' ? _intervalTicks : null,
      dayOfWeek: _type == 'WeeklyTrigger' ? _dayOfWeek : null,
      maxRuntimeTicks: hours == null ? null : (hours * _ticksPerHour).round(),
    );

    Navigator.pop(context, trigger);
  }
}
