import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../../l10n/app_localizations.dart';
import '../admin_nav.dart';
import '../admin_search_index.dart';

/// Wraps one setting row so a search result can scroll to it and flash it.
class AdminSettingAnchor extends StatefulWidget {
  const AdminSettingAnchor({super.key, required this.id, required this.child});

  /// Matches an [AdminSearchEntry.anchor].
  final String id;
  final Widget child;

  /// The row a search result is waiting to reveal once its page builds.
  static final pending = ValueNotifier<String?>(null);

  @override
  State<AdminSettingAnchor> createState() => _AdminSettingAnchorState();
}

class _AdminSettingAnchorState extends State<AdminSettingAnchor> {
  bool _flash = false;

  @override
  void initState() {
    super.initState();
    AdminSettingAnchor.pending.addListener(_reveal);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  @override
  void dispose() {
    AdminSettingAnchor.pending.removeListener(_reveal);
    super.dispose();
  }

  void _reveal() {
    if (!mounted || AdminSettingAnchor.pending.value != widget.id) return;
    AdminSettingAnchor.pending.value = null;
    Scrollable.ensureVisible(
      context,
      alignment: 0.3,
      duration: const Duration(milliseconds: 300),
    );
    setState(() => _flash = true);
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _flash = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: _flash
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.14)
            : Colors.transparent,
      ),
      child: widget.child,
    );
  }
}

/// Searches every admin page and setting. Results open the page and scroll
/// to the row.
class AdminSettingsSearch extends StatefulWidget {
  const AdminSettingsSearch({super.key, this.expandResults = false});

  /// Lists results under the field (phone) rather than in a popup (wide).
  final bool expandResults;

  @override
  State<AdminSettingsSearch> createState() => _AdminSettingsSearchState();
}

class _AdminSettingsSearchState extends State<AdminSettingsSearch> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _portal = OverlayPortalController();
  final _link = LayerLink();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_sync);
    _focus.addListener(_sync);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _sync() {
    setState(() {});
    if (widget.expandResults) return;
    if (_controller.text.trim().length >= 2 && _focus.hasFocus) {
      _portal.show();
    } else {
      _portal.hide();
    }
  }

  void _open(AdminSearchEntry entry) {
    final page = adminPageById(entry.pageId);
    if (page == null) return;
    _controller.clear();
    _focus.unfocus();
    AdminSettingAnchor.pending.value = entry.anchor;
    final here = GoRouterState.of(context).uri.path;
    if (here != page.route) context.push(page.route);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final entries = adminSearchEntries(AdminServerScope.of(context));
    final query = _controller.text.trim();
    final results = query.length < 2
        ? const <AdminSearchEntry>[]
        : matchAdminSearch(entries, query, l10n);

    final field = TextField(
      controller: _controller,
      focusNode: _focus,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) {
        if (results.isNotEmpty) _open(results.first);
      },
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: scheme.onSurface.withValues(alpha: 0.05),
        hintText: l10n.adminSearchSettingsHint(entries.length),
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: l10n.adminSearchClear,
                onPressed: _controller.clear,
              ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );

    final list = _ResultList(results: results, onOpen: _open);

    if (widget.expandResults) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          field,
          if (query.length >= 2) ...[const SizedBox(height: 8), list],
        ],
      );
    }

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 6),
          child: Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              width: 460,
              child: TapRegion(
                groupId: _link,
                child: Material(
                  elevation: 8,
                  color: scheme.surfaceContainerHigh,
                  borderRadius: AppRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 440),
                    child: list,
                  ),
                ),
              ),
            ),
          ),
        ),
        child: TapRegion(
          groupId: _link,
          onTapOutside: (_) => _focus.unfocus(),
          child: field,
        ),
      ),
    );
  }
}

class _ResultList extends StatelessWidget {
  const _ResultList({required this.results, required this.onOpen});

  final List<AdminSearchEntry> results;
  final ValueChanged<AdminSearchEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(l10n.adminSearchNoResults, style: theme.textTheme.bodyMedium),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: results.length,
      itemBuilder: (context, i) {
        final entry = results[i];
        return ListTile(
          dense: true,
          title: Text(entry.label(l10n)),
          subtitle: Text(
            entry.where(l10n),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          onTap: () => onOpen(entry),
        );
      },
    );
  }
}
