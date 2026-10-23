import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../util/error_message.dart';
import '../admin_draft.dart';
import '../admin_search_index.dart';
import '../settings/admin_number_input.dart';
import '../widgets/admin_form_styles.dart';
import '../widgets/filesystem_browser.dart';
import '../widgets/premiere_note.dart';

typedef L10nText = String Function(AppLocalizations l10n);

enum AdminConfigKind {
  toggle,
  number,
  text,
  password,
  path,
  file,
  user,
  list,
  choice,
}

class AdminConfigField {
  const AdminConfigField(
    this.key,
    this.kind,
    this.label, {
    this.help,
    this.min = 0,
    this.max,
    this.inverted = false,
    this.choices = const [],
  });

  final String key;
  final AdminConfigKind kind;
  final L10nText label;
  final L10nText? help;
  final num min;
  final num? max;

  /// A toggle that shows the opposite of the stored flag.
  final bool inverted;

  final List<(Object, L10nText)> choices;
}

class AdminConfigSection {
  const AdminConfigSection(this.title, this.icon, this.fields);

  final L10nText title;
  final IconData icon;
  final List<AdminConfigField> fields;
}

/// A settings page over one configuration object, the base one or the named
/// one in [namedKey].
class AdminConfigPage {
  const AdminConfigPage({
    required this.id,
    required this.title,
    required this.icon,
    required this.sections,
    this.namedKey,
    this.warning,
    this.premiere = false,
  });

  final String id;
  final L10nText title;
  final IconData icon;
  final List<AdminConfigSection> sections;
  final String? namedKey;
  final L10nText? warning;

  /// The whole page needs Premiere.
  final bool premiere;

  List<AdminSearchEntry> get searchEntries => [
    for (final section in sections)
      for (final field in section.fields)
        adminSettingRow(id, field.key, field.label, section.title),
  ];
}

class AdminConfigFormScreen extends StatefulWidget {
  const AdminConfigFormScreen({super.key, required this.page, this.footer});

  final AdminConfigPage page;

  final Widget? footer;

  @override
  State<AdminConfigFormScreen> createState() => _AdminConfigFormScreenState();
}

class _AdminConfigFormScreenState extends State<AdminConfigFormScreen>
    with AdminDraftHost {
  AdminSystemApi get _api => GetIt.instance<MediaServerClient>().adminSystemApi;
  Map<String, dynamic>? _config;
  String? _error;
  List<ServerUser> _users = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, dynamic>> _fetch() {
    final key = widget.page.namedKey;
    return key == null
        ? _api.getServerConfiguration()
        : _api.getNamedConfiguration(key);
  }

  Future<void> _post(Map<String, dynamic> value) {
    final key = widget.page.namedKey;
    return key == null
        ? _api.updateServerConfiguration(value)
        : _api.updateNamedConfiguration(key, value);
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final config = await _fetch();
      final needsUsers = widget.page.sections.any(
        (s) => s.fields.any((f) => f.kind == AdminConfigKind.user),
      );
      final users = needsUsers
          ? await GetIt.instance<MediaServerClient>().adminUsersApi.getUsers()
          : const <ServerUser>[];
      if (!mounted) return;
      setState(() {
        _config = config;
        _users = users;
      });
      hostDraft(
        AdminDraft.single(working: config, reload: _fetch, post: _post),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = describeError(e, AppLocalizations.of(context)));
    }
  }

  void _set(String key, Object? value) {
    setState(() => _config![key] = value);
    edited();
  }

  Widget _field(AppLocalizations l10n, AdminConfigField field) {
    final anchor = '${widget.page.id}.${field.key}';
    final value = _config![field.key];
    final input = switch (field.kind) {
      AdminConfigKind.toggle => null,
      AdminConfigKind.number => adminNumberInput(
        text: '${value ?? ''}',
        fallback: field.min,
        min: field.min,
        max: field.max,
        onChanged: (n) => _set(field.key, n),
      ),
      AdminConfigKind.text || AdminConfigKind.password => TextFormField(
        initialValue: value?.toString() ?? '',
        obscureText: field.kind == AdminConfigKind.password,
        decoration: adminInputDecoration(),
        onChanged: (v) => _set(field.key, v),
      ),
      AdminConfigKind.list => TextFormField(
        initialValue: (value as List? ?? const []).join('\n'),
        minLines: 2,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        decoration: adminInputDecoration(hint: l10n.adminOnePerLine),
        onChanged: (v) => _set(field.key, [
          for (final line in v.split('\n'))
            if (line.trim().isNotEmpty) line.trim(),
        ]),
      ),
      AdminConfigKind.choice => adminChoiceDropdown<Object?>(
        value: value,
        options: [
          for (final (choice, label) in field.choices) (choice, label(l10n)),
        ],
        onChanged: (v) => _set(field.key, v),
      ),
      AdminConfigKind.user => adminChoiceDropdown<String>(
        value: _users.any((u) => u.id == value) ? value as String : '',
        options: [
          ('', l10n.none),
          for (final user in _users) (user.id, user.name ?? user.id),
        ],
        onChanged: (v) => _set(field.key, v == '' ? null : v),
      ),
      AdminConfigKind.path || AdminConfigKind.file => AdminPathInput(
        value: value?.toString(),
        files: field.kind == AdminConfigKind.file,
        onChanged: (v) => _set(field.key, v),
      ),
    };
    if (input == null) {
      return adminSwitchRow(
        title: field.label(l10n),
        subtitle: field.help?.call(l10n),
        anchor: anchor,
        value: (value as bool? ?? false) != field.inverted,
        onChanged: (v) => _set(field.key, v != field.inverted),
      );
    }
    return adminFieldRow(
      label: field.label(l10n),
      helper: field.help?.call(l10n),
      anchor: anchor,
      child: input,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final page = widget.page;
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.adminSettingsLoadFailed,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(_error!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: _load, child: Text(l10n.retry)),
          ],
        ),
      );
    }
    if (_config == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        20,
        16,
        MediaQuery.paddingOf(context).bottom + 40,
      ),
      children: [
        adminScreenHeader(context, title: page.title(l10n), icon: page.icon),
        if (page.premiere) const PremiereNote(),
        if (page.warning != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: const Icon(Icons.warning_amber_outlined),
              title: Text(page.warning!(l10n)),
            ),
          ),
        draftKeyed(
          Column(
            children: [
              for (final section in page.sections)
                adminSection(
                  context,
                  title: section.title(l10n),
                  icon: section.icon,
                  children: [
                    for (final field in section.fields) _field(l10n, field),
                  ],
                ),
            ],
          ),
        ),
        ?widget.footer,
      ],
    );
  }
}

/// A dropdown that also lists a stored [value] missing from [options], so
/// saving keeps it as it is.
DropdownButtonFormField<T> adminChoiceDropdown<T>({
  Key? key,
  required T value,
  required List<(T, String)> options,
  required ValueChanged<T?> onChanged,
}) => DropdownButtonFormField<T>(
  key: key,
  initialValue: value,
  isExpanded: true,
  decoration: adminInputDecoration(),
  items: [
    for (final (option, label) in options)
      DropdownMenuItem(value: option, child: Text(label)),
    if (!options.any((o) => o.$1 == value))
      DropdownMenuItem(value: value, child: Text('${value ?? ''}')),
  ],
  onChanged: onChanged,
);

/// A path box with a server folder browser, or a file browser with [files].
class AdminPathInput extends StatefulWidget {
  const AdminPathInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.files = false,
  });

  final String? value;
  final ValueChanged<String> onChanged;
  final bool files;

  @override
  State<AdminPathInput> createState() => _AdminPathInputState();
}

class _AdminPathInputState extends State<AdminPathInput> {
  late final _text = TextEditingController(text: widget.value ?? '');
  bool _browsing = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _text,
                decoration: adminInputDecoration(),
                onChanged: widget.onChanged,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(_browsing ? Icons.close : Icons.folder_open),
              tooltip: _browsing ? l10n.adminCloseBrowser : l10n.adminBrowse,
              onPressed: () => setState(() => _browsing = !_browsing),
            ),
          ],
        ),
        if (_browsing) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 300,
            child: FilesystemBrowser(
              initialPath: _text.text,
              includeFiles: widget.files,
              validateWritable: !widget.files,
              onPathSelected: (path) {
                setState(() => _browsing = false);
                _text.text = path;
                widget.onChanged(path);
              },
            ),
          ),
        ],
      ],
    );
  }
}
