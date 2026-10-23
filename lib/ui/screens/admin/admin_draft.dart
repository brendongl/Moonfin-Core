import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../widgets/adaptive/adaptive_dialog.dart';

/// One object a page edits and saves as a whole, e.g. `/System/Configuration`.
class AdminDraftTarget {
  AdminDraftTarget({
    required this.working,
    required this.reload,
    required this.post,
  }) : _original = _copy(working);

  /// The map the page reads and edits in place.
  final Map<String, dynamic> working;

  /// Fetches the object fresh, so a save lays only this page's edits over
  /// whatever another page, admin or client saved meanwhile.
  final Future<Map<String, dynamic>> Function() reload;

  final Future<void> Function(Map<String, dynamic> value) post;

  Map<String, dynamic> _original;

  bool get isDirty => !_eq.equals(_original, working);

  Iterable<String> get _changedKeys => {
    ...working.keys,
    ..._original.keys,
  }.where((k) => !_eq.equals(working[k], _original[k]));

  Future<void> _save() async {
    final changed = _changedKeys.toList();
    final merged = await reload();
    for (final key in changed) {
      if (working.containsKey(key)) {
        merged[key] = _copy(working[key]);
      } else {
        merged.remove(key);
      }
    }
    await post(merged);
    _original = _copy(merged);
    _reset(working, merged);
  }

  void _discard() => _reset(working, _original);
}

/// The unsaved edits of the admin page on screen. The shell shows the
/// Discard/Save bar from it and every admin route asks before leaving it dirty.
class AdminDraft extends ChangeNotifier {
  AdminDraft(this.targets);

  AdminDraft.single({
    required Map<String, dynamic> working,
    required Future<Map<String, dynamic>> Function() reload,
    required Future<void> Function(Map<String, dynamic> value) post,
  }) : this({
         'main': AdminDraftTarget(working: working, reload: reload, post: post),
       });

  /// The draft of the page on screen, set by the page once it has loaded.
  static final active = ValueNotifier<AdminDraft?>(null);

  final Map<String, AdminDraftTarget> targets;

  /// Bumped when the working maps are replaced, so pages re-key their fields
  /// (uncontrolled fields only read their initial value).
  int revision = 0;
  bool saving = false;
  Object? error;
  bool _dirty = false;

  bool get isDirty => _dirty;

  /// Call after any edit to a working map.
  void touch() {
    final dirty = targets.values.any((t) => t.isDirty);
    if (dirty == _dirty && error == null) return;
    _dirty = dirty;
    error = null;
    notifyListeners();
  }

  /// Saves each dirty target in turn. One that fails stays dirty, and the
  /// ones before it are kept.
  Future<bool> save() async {
    if (saving) return false;
    saving = true;
    error = null;
    notifyListeners();
    try {
      for (final target in targets.values) {
        if (target.isDirty) await target._save();
      }
      return true;
    } catch (e) {
      error = e;
      return false;
    } finally {
      saving = false;
      revision++;
      _dirty = targets.values.any((t) => t.isDirty);
      notifyListeners();
    }
  }

  void discard() {
    for (final target in targets.values) {
      target._discard();
    }
    revision++;
    _dirty = false;
    error = null;
    notifyListeners();
  }

  /// Makes this the page's draft, and [release] undoes it if still current.
  /// Both wait for the frame to end when called from initState or dispose,
  /// since the bar listening to [active] can't rebuild mid-frame.
  void claim() => _whenIdle(() => active.value = this);

  void release() => _whenIdle(() {
    if (active.value == this) active.value = null;
  });

  static void _whenIdle(VoidCallback apply) {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      apply();
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) => apply());
    }
  }
}

/// `GoRoute.onExit` for every admin page: asks once before leaving unsaved
/// edits. go_router calls it for each exiting match, and the second call finds
/// the draft already discarded.
Future<bool> confirmAdminLeave(BuildContext context, GoRouterState state) async {
  final draft = AdminDraft.active.value;
  if (draft == null || !draft.isDirty) return true;
  final l10n = AppLocalizations.of(context);
  final discard = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      title: Text(l10n.adminLeaveTitle),
      content: Text(l10n.adminLeaveMessage),
      actions: [
        adaptiveDialogAction(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.adminKeepEditing),
        ),
        adaptiveDialogAction(
          isDestructive: true,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.adminDiscard),
        ),
      ],
    ),
  );
  if (discard != true) return false;
  draft.discard();
  draft.release();
  return true;
}

const _eq = DeepCollectionEquality();

/// Config objects are plain JSON, so a JSON round trip is a full deep copy.
T _copy<T>(T value) => jsonDecode(jsonEncode(value)) as T;

void _reset(Map<String, dynamic> into, Map<String, dynamic> from) {
  into
    ..clear()
    ..addAll(_copy(from));
}

/// What every admin settings page does with its [AdminDraft]: claim it,
/// rebuild when it changes, and re-key its fields when edits are replaced.
mixin AdminDraftHost<T extends StatefulWidget> on State<T> {
  AdminDraft? draft;

  void hostDraft(AdminDraft value) {
    draft?.removeListener(_onDraft);
    draft?.release();
    draft = value..addListener(_onDraft);
    value.claim();
  }

  /// Call after any edit to the draft's working maps.
  void edited() => draft?.touch();

  /// Wraps the page's fields so Discard and Save rebuild them from the maps.
  Widget draftKeyed(Widget child) =>
      KeyedSubtree(key: ValueKey(draft?.revision ?? 0), child: child);

  void _onDraft() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    draft?.removeListener(_onDraft);
    draft?.release();
    super.dispose();
  }
}
