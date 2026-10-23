import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../util/error_message.dart';
import '../widgets/admin_form_styles.dart';
import '../widgets/filesystem_browser.dart';

/// A tuner's title: its friendly name, else its type.
String liveTvTunerName(Map<String, dynamic> tuner, AppLocalizations l10n) {
  final name = tuner['FriendlyName']?.toString().trim() ?? '';
  if (name.isNotEmpty) return name;
  final type = tuner['Type']?.toString() ?? '';
  return switch (type.toLowerCase()) {
    'm3u' => l10n.adminTunerTypeM3u,
    'hdhomerun' => l10n.adminTunerTypeHdHomerun,
    _ => type.isEmpty ? l10n.unknown : type,
  };
}

/// Lets the admin pick a server path. Returns null on cancel.
Future<String?> pickServerPath(
  BuildContext context, {
  String? initial,
  bool files = false,
  bool writable = false,
}) {
  final l10n = AppLocalizations.of(context);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.adminBrowse),
      content: SizedBox(
        width: 520,
        height: 420,
        child: FilesystemBrowser(
          initialPath: initial,
          includeFiles: files,
          validateWritable: writable,
          onPathSelected: (path) => Navigator.pop(ctx, path),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.cancel),
        ),
      ],
    ),
  );
}

const _gap = SizedBox(height: 12);

/// A form dialog, full screen when the window is narrow.
class _FormFrame extends StatelessWidget {
  const _FormFrame({
    required this.title,
    required this.children,
    required this.actions,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
    if (MediaQuery.sizeOf(context).width < 600) {
      return Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(title: Text(title), automaticallyImplyLeading: false),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: body,
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                children: actions,
              ),
            ),
          ),
        ),
      );
    }
    return AlertDialog(
      title: Text(title),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: body)),
      actions: actions,
    );
  }
}

Widget _errorText(BuildContext context, String? error) => error == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          error,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );

Widget liveTvSpinner() => const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );

/// [list]'s maps, copied, or none when it isn't a list.
List<Map<String, dynamic>> liveTvMaps(Object? list) => [
      for (final e in (list as List? ?? const []).whereType<Map>())
        Map<String, dynamic>.from(e),
    ];

/// A file or URL field with a browse button that lists server files.
Widget _fileField(
  BuildContext context, {
  required TextEditingController controller,
  required String label,
  String? helper,
  required VoidCallback onChanged,
}) {
  return TextField(
    controller: controller,
    onChanged: (_) => onChanged(),
    decoration: adminInputDecoration(
      label: label,
      helper: helper,
      suffixIcon: IconButton(
        icon: const Icon(Icons.folder_open),
        tooltip: AppLocalizations.of(context).adminBrowse,
        onPressed: () async {
          final path = await pickServerPath(context, files: true);
          if (path == null) return;
          controller.text = path;
          onChanged();
        },
      ),
    ),
  );
}

String? _orNull(TextEditingController c) =>
    c.text.trim().isEmpty ? null : c.text.trim();

String _text(Map<String, dynamic> map, String key) =>
    map[key]?.toString() ?? '';

/// The provider as the server has it now, so a save keeps the keys the form
/// doesn't show (ChannelMappings, PreferredLanguage, the stored Password).
Future<Map<String, dynamic>> _storedProvider(
  AdminLiveTvApi api,
  String id,
  Map<String, dynamic> fallback,
) async {
  if (id.isNotEmpty) {
    final config = await api.getLiveTvConfiguration();
    for (final p in (config['ListingProviders'] as List? ?? const [])
        .whereType<Map>()) {
      if (p['Id'] == id) return Map<String, dynamic>.from(p);
    }
  }
  return Map<String, dynamic>.from(fallback);
}

/// "Enable for all tuner devices" and, when off, a tick per tuner.
mixin _EnabledTuners<T extends StatefulWidget> on State<T> {
  late bool _allTuners;
  late Set<String> _enabledTuners;

  List<Map<String, dynamic>> get tuners;

  void _initTuners(Map<String, dynamic> info) {
    _allTuners = info['EnableAllTuners'] as bool? ?? true;
    // Every tuner starts ticked while all are enabled.
    _enabledTuners = {
      for (final t in tuners)
        if (_allTuners ||
            (info['EnabledTuners'] as List? ?? const []).contains(t['Id']))
          t['Id'].toString(),
    };
  }

  void _applyTuners(Map<String, dynamic> info) {
    info['EnableAllTuners'] = _allTuners;
    info['EnabledTuners'] = _allTuners
        ? <String>[]
        : [
            for (final t in tuners)
              if (_enabledTuners.contains(t['Id'].toString()))
                t['Id'].toString(),
          ];
  }

  List<Widget> _tunerRows(AppLocalizations l10n) => [
        adminSwitchRow(
          title: l10n.adminEnableAllTuners,
          value: _allTuners,
          onChanged: (v) => setState(() => _allTuners = v),
        ),
        if (!_allTuners)
          for (final t in tuners)
            CheckboxListTile(
              value: _enabledTuners.contains(t['Id'].toString()),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(liveTvTunerName(t, l10n)),
              subtitle: _text(t, 'Url').isEmpty ? null : Text(_text(t, 'Url')),
              onChanged: (v) => setState(() {
                final id = t['Id'].toString();
                v == true ? _enabledTuners.add(id) : _enabledTuners.remove(id);
              }),
            ),
      ];
}

/// Adds or edits a tuner host. Pops true once the server saved it.
class LiveTvTunerDialog extends StatefulWidget {
  const LiveTvTunerDialog({
    super.key,
    required this.api,
    required this.types,
    this.seed = const {},
    this.emby = false,
  });

  final AdminLiveTvApi api;

  /// (Id, Name) pairs from GET /LiveTv/TunerHosts/Types.
  final List<(String, String)> types;

  /// The stored tuner, a detected device, or empty for a new one.
  final Map<String, dynamic> seed;

  /// Emby only has the favorites and hardware transcoding switches, for every
  /// tuner type.
  final bool emby;

  @override
  State<LiveTvTunerDialog> createState() => _LiveTvTunerDialogState();
}

class _LiveTvTunerDialogState extends State<LiveTvTunerDialog> {
  late final String _id = _text(widget.seed, 'Id');
  late String _type =
      widget.seed['Type']?.toString() ?? widget.types.first.$1;
  late final _url = TextEditingController(text: _text(widget.seed, 'Url'));
  late final _name =
      TextEditingController(text: _text(widget.seed, 'FriendlyName'));
  late final _userAgent =
      TextEditingController(text: _text(widget.seed, 'UserAgent'));
  late final _count = TextEditingController(
    text: '${(widget.seed['TunerCount'] as num?)?.toInt() ?? 0}',
  );
  late final _bitrate = TextEditingController(
    text: _mbps(widget.seed['FallbackMaxStreamingBitrate']),
  );
  late final _flags = <String, bool>{
    'ImportFavoritesOnly': widget.seed['ImportFavoritesOnly'] as bool? ?? false,
    'AllowHWTranscoding': widget.seed['AllowHWTranscoding'] as bool? ?? false,
    'AllowFmp4TranscodingContainer':
        widget.seed['AllowFmp4TranscodingContainer'] as bool? ?? false,
    'AllowStreamSharing': widget.seed['AllowStreamSharing'] as bool? ?? true,
    'EnableStreamLooping': widget.seed['EnableStreamLooping'] as bool? ?? false,
    'IgnoreDts': widget.seed['IgnoreDts'] as bool? ?? true,
    'ReadAtNativeFramerate':
        widget.seed['ReadAtNativeFramerate'] as bool? ?? true,
  };
  bool _saving = false;
  String? _error;

  static String _mbps(Object? bps) {
    final value = (bps as num?)?.toInt() ?? 0;
    if (value <= 0) return '30';
    return value % 1000000 == 0 ? '${value ~/ 1000000}' : '${value / 1000000}';
  }

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    _userAgent.dispose();
    _count.dispose();
    _bitrate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final deviceId = _text(widget.seed, 'DeviceId');
    try {
      await widget.api.addTunerHost({
        if (_id.isNotEmpty) 'Id': _id,
        'Type': _type,
        'Url': _orNull(_url),
        'UserAgent': _orNull(_userAgent),
        'FriendlyName': _orNull(_name),
        'DeviceId': deviceId.isEmpty ? null : deviceId,
        'TunerCount': int.tryParse(_count.text.trim()) ?? 0,
        // A plain int on the server, 30 Mbps when blank.
        'FallbackMaxStreamingBitrate':
            ((double.tryParse(_bitrate.text.trim()) ?? 30) * 1000000).round(),
        ..._flags,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = describeError(e, AppLocalizations.of(context));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isHd = _type == 'hdhomerun';
    final isM3u = _type == 'm3u';
    final emby = widget.emby;
    Widget flag(String key, String title) => adminSwitchRow(
          title: title,
          value: _flags[key]!,
          onChanged: (v) => setState(() => _flags[key] = v),
        );
    return _FormFrame(
      title: _id.isEmpty ? l10n.adminLiveTvAddTuner : l10n.adminLiveTvEditTuner,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _saving || (isM3u && _url.text.trim().isEmpty)
              ? null
              : _save,
          child: Text(l10n.save),
        ),
      ],
      children: [
        DropdownButtonFormField<String>(
          initialValue: _type,
          isExpanded: true,
          decoration: adminInputDecoration(label: l10n.adminLiveTvTunerType),
          items: [
            for (final t in widget.types)
              DropdownMenuItem(value: t.$1, child: Text(t.$2)),
            if (!widget.types.any((t) => t.$1 == _type))
              DropdownMenuItem(value: _type, child: Text(_type)),
          ],
          // A saved tuner's type can't change.
          onChanged: _id.isNotEmpty
              ? null
              : (v) {
                  if (v != null) setState(() => _type = v);
                },
        ),
        if (isM3u) ...[
          _gap,
          _fileField(
            context,
            controller: _url,
            label: l10n.adminTunerFileOrUrl,
            onChanged: () => setState(() {}),
          ),
        ],
        if (isHd) ...[
          _gap,
          TextField(
            controller: _url,
            decoration: adminInputDecoration(label: l10n.adminTunerIpAddress),
          ),
        ],
        _gap,
        TextField(
          controller: _name,
          decoration: adminInputDecoration(label: l10n.adminTunerFriendlyName),
        ),
        if (isM3u) ...[
          _gap,
          TextField(
            controller: _userAgent,
            decoration: adminInputDecoration(label: l10n.adminTunerUserAgent),
          ),
          _gap,
          TextField(
            controller: _count,
            keyboardType: TextInputType.number,
            decoration: adminInputDecoration(
              label: l10n.adminTunerCount,
              helper: l10n.adminTunerCountHelp,
            ),
          ),
        ],
        if ((isM3u || isHd) && !emby) ...[
          _gap,
          TextField(
            controller: _bitrate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: adminInputDecoration(
              label: l10n.adminTunerFallbackBitrate,
              suffixText: 'Mbps',
            ),
          ),
        ],
        const SizedBox(height: 4),
        if (isHd || emby) ...[
          flag('ImportFavoritesOnly', l10n.adminTunerImportFavoritesOnly),
          flag('AllowHWTranscoding', l10n.adminTunerAllowHwTranscoding),
        ],
        if (isHd)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              l10n.adminLiveTvDrmNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (isM3u && !emby) ...[
          flag('AllowFmp4TranscodingContainer', l10n.adminTunerAllowFmp4),
          flag('AllowStreamSharing', l10n.adminTunerAllowStreamSharing),
          flag('EnableStreamLooping', l10n.adminTunerEnableStreamLooping),
          flag('IgnoreDts', l10n.adminTunerIgnoreDts),
          flag('ReadAtNativeFramerate', l10n.adminTunerReadAtNativeFramerate),
        ],
        _errorText(context, _error),
      ],
    );
  }
}

/// Adds or edits an XMLTV provider. Pops true once the server saved it.
class LiveTvXmltvDialog extends StatefulWidget {
  const LiveTvXmltvDialog({
    super.key,
    required this.api,
    required this.seed,
    required this.tuners,
  });

  final AdminLiveTvApi api;

  /// The stored provider, or GET /LiveTv/ListingProviders/Default for a new
  /// one.
  final Map<String, dynamic> seed;
  final List<Map<String, dynamic>> tuners;

  @override
  State<LiveTvXmltvDialog> createState() => _LiveTvXmltvDialogState();
}

class _LiveTvXmltvDialogState extends State<LiveTvXmltvDialog>
    with _EnabledTuners {
  late final String _id = _text(widget.seed, 'Id');
  late final _path = TextEditingController(text: _text(widget.seed, 'Path'));
  late final _moviePrefix =
      TextEditingController(text: _text(widget.seed, 'MoviePrefix'));
  late final _userAgent =
      TextEditingController(text: _text(widget.seed, 'UserAgent'));
  late final _categories = {
    for (final key in const [
      'MovieCategories',
      'KidsCategories',
      'NewsCategories',
      'SportsCategories',
    ])
      key: TextEditingController(
        text: (widget.seed[key] as List? ?? const []).join('|'),
      ),
  };
  bool _saving = false;
  String? _error;

  @override
  List<Map<String, dynamic>> get tuners => widget.tuners;

  @override
  void initState() {
    super.initState();
    _initTuners(widget.seed);
  }

  @override
  void dispose() {
    _path.dispose();
    _moviePrefix.dispose();
    _userAgent.dispose();
    for (final c in _categories.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final info = await _storedProvider(widget.api, _id, widget.seed)
        ..['Type'] = 'xmltv'
        ..['Path'] = _path.text.trim()
        ..['MoviePrefix'] = _orNull(_moviePrefix)
        ..['UserAgent'] = _orNull(_userAgent);
      _categories.forEach((key, c) {
        info[key] = [
          for (final value in c.text.split('|'))
            if (value.trim().isNotEmpty) value.trim(),
        ];
      });
      _applyTuners(info);
      await widget.api.addListingProvider(info, validateListings: true);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = describeError(e, AppLocalizations.of(context));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget category(String key, String label, {String? helper}) => TextField(
          controller: _categories[key],
          decoration: adminInputDecoration(label: label, helper: helper),
        );
    return _FormFrame(
      title: l10n.adminProviderXmltv,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _saving || _path.text.trim().isEmpty ? null : _save,
          child: Text(l10n.save),
        ),
      ],
      children: [
        _fileField(
          context,
          controller: _path,
          label: l10n.adminXmltvPath,
          helper: l10n.adminLiveTvXmltvPathHelp,
          onChanged: () => setState(() {}),
        ),
        _gap,
        category(
          'MovieCategories',
          l10n.adminXmltvMovieCategories,
          helper: l10n.adminXmltvCategoriesHelp,
        ),
        _gap,
        TextField(
          controller: _moviePrefix,
          decoration: adminInputDecoration(label: l10n.adminXmltvMoviePrefix),
        ),
        _gap,
        category('KidsCategories', l10n.adminXmltvKidsCategories),
        _gap,
        category('NewsCategories', l10n.adminXmltvNewsCategories),
        _gap,
        category('SportsCategories', l10n.adminXmltvSportsCategories),
        _gap,
        TextField(
          controller: _userAgent,
          decoration: adminInputDecoration(label: l10n.adminTunerUserAgent),
        ),
        const SizedBox(height: 4),
        ..._tunerRows(l10n),
        _errorText(context, _error),
      ],
    );
  }
}

/// Adds or edits a Schedules Direct provider in two steps, sign in and then
/// pick the lineup. Pops true when anything was saved.
class LiveTvSchedulesDirectDialog extends StatefulWidget {
  const LiveTvSchedulesDirectDialog({
    super.key,
    required this.api,
    required this.seed,
    required this.tuners,
    this.embyGuide = false,
  });

  final AdminLiveTvApi api;

  /// The stored provider, or empty for a new one.
  final Map<String, dynamic> seed;
  final List<Map<String, dynamic>> tuners;

  /// Emby Guide Data instead: the same country, postal code and lineup with
  /// no sign in, and three letter country codes.
  final bool embyGuide;

  @override
  State<LiveTvSchedulesDirectDialog> createState() =>
      _LiveTvSchedulesDirectDialogState();
}

class _LiveTvSchedulesDirectDialogState
    extends State<LiveTvSchedulesDirectDialog> with _EnabledTuners {
  late String _id = _text(widget.seed, 'Id');
  late final _username =
      TextEditingController(text: _text(widget.seed, 'Username'));
  final _password = TextEditingController();
  late final _zip = TextEditingController(text: _text(widget.seed, 'ZipCode'));
  late String _country = _text(widget.seed, 'Country');
  late String _listingsId = _text(widget.seed, 'ListingsId');
  // A stored login lists lineups without a new sign in.
  late bool _signedIn = widget.embyGuide ||
      _text(widget.seed, 'Username').isNotEmpty &&
          _text(widget.seed, 'Password').isNotEmpty;
  List<Map<String, dynamic>> _countries = const [];
  List<Map<String, dynamic>> _lineups = const [];
  String? _lineupQuery;
  bool _loadingLineups = false;
  bool _busy = false;
  bool _saved = false;
  String? _error;

  @override
  List<Map<String, dynamic>> get tuners => widget.tuners;

  @override
  void initState() {
    super.initState();
    _initTuners(widget.seed);
    _loadCountries();
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _zip.dispose();
    super.dispose();
  }

  Future<void> _loadCountries() async {
    try {
      final countries = widget.embyGuide
          ? [
              for (final c in await GetIt.instance<MediaServerClient>()
                  .adminSystemApi
                  .getCountries())
                {
                  'shortName': c['ThreeLetterISORegionName'],
                  'fullName': c['DisplayName'],
                },
            ]
          : await widget.api.getSchedulesDirectCountries();
      if (!mounted) return;
      setState(() => _countries = countries);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = describeError(e, AppLocalizations.of(context)));
    }
    await _loadLineups();
  }

  Future<void> _loadLineups() async {
    final zip = _zip.text.trim();
    final query = '$_id|$_country|$zip';
    if (!mounted || !_signedIn || query == _lineupQuery) return;
    _lineupQuery = query;
    if (zip.isEmpty) {
      setState(() => _lineups = const []);
      return;
    }
    setState(() {
      _loadingLineups = true;
      _error = null;
    });
    try {
      final found = await widget.api.getListingProviderLineups(
        providerId: _id,
        location: zip,
        country: _country,
      );
      if (!mounted) return;
      setState(() {
        _lineups = found;
        _loadingLineups = false;
        if (!found.any((l) => l['Id']?.toString() == _listingsId)) {
          _listingsId = '';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lineups = const [];
        _loadingLineups = false;
        _lineupQuery = null;
        _error = describeError(e, AppLocalizations.of(context));
      });
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final info = await _storedProvider(
        widget.api,
        _id,
        const {'EnableAllTuners': true},
      )
        ..['Type'] = 'SchedulesDirect'
        ..['Username'] = _username.text.trim()
        // Plaintext on purpose: the server hashes it when it asks for a token.
        ..['Password'] = _password.text;
      if (_id.isNotEmpty) info['Id'] = _id;
      final result =
          await widget.api.addListingProvider(info, validateLogin: true);
      if (!mounted) return;
      _password.clear();
      setState(() {
        _id = _text(result, 'Id').isEmpty ? _id : _text(result, 'Id');
        _signedIn = true;
        _saved = true;
        _busy = false;
      });
      await _loadLineups();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeError(e, AppLocalizations.of(context));
      });
    }
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (_listingsId.isEmpty) {
      setState(() => _error = widget.embyGuide
          ? l10n.adminLiveTvEmbyGuideSelectLineup
          : l10n.adminLiveTvSdSelectLineup);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final info = await _storedProvider(widget.api, _id, widget.seed)
        ..['Type'] = widget.embyGuide ? 'embygn' : 'SchedulesDirect'
        ..['ZipCode'] = _zip.text.trim()
        ..['Country'] = _country
        ..['ListingsId'] = _listingsId;
      if (_id.isNotEmpty) info['Id'] = _id;
      if (_password.text.isNotEmpty) {
        info
          ..['Username'] = _username.text.trim()
          ..['Password'] = _password.text;
      }
      _applyTuners(info);
      await widget.api.addListingProvider(info, validateListings: true);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeError(e, l10n);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canSignIn = !_busy &&
        _username.text.trim().isNotEmpty &&
        _password.text.isNotEmpty;
    final countryKnown =
        _country.isEmpty || _countries.any((c) => c['shortName'] == _country);
    return _FormFrame(
      title: widget.embyGuide
          ? l10n.adminProviderEmbyGuide
          : l10n.adminProviderSchedulesDirect,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _saved),
          child: Text(l10n.cancel),
        ),
        if (_signedIn)
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(l10n.save),
          ),
      ],
      children: [
        if (!widget.embyGuide) ...[
          Text(
            l10n.adminLiveTvSdCreateAccount('https://www.schedulesdirect.org'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          _gap,
          TextField(
            controller: _username,
            onChanged: (_) => setState(() {}),
            decoration: adminInputDecoration(label: l10n.adminSdUsername),
          ),
          _gap,
          TextField(
            controller: _password,
            obscureText: true,
            onChanged: (_) => setState(() {}),
            decoration: adminInputDecoration(label: l10n.adminSdPassword),
          ),
          _gap,
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: canSignIn ? _signIn : null,
              icon: _busy ? liveTvSpinner() : const Icon(Icons.login),
              label: Text(l10n.adminLiveTvSdSignIn),
            ),
          ),
        ],
        if (_signedIn) ...[
          if (!widget.embyGuide) const Divider(height: 32),
          DropdownButtonFormField<String>(
            key: ValueKey(_countries.length),
            initialValue: _country,
            isExpanded: true,
            decoration: adminInputDecoration(label: l10n.adminSdCountry),
            items: [
              DropdownMenuItem(value: '', child: Text(l10n.adminSdCountrySelect)),
              for (final c in _countries)
                if (c['shortName']?.toString().isNotEmpty ?? false)
                  DropdownMenuItem(
                    value: c['shortName'].toString(),
                    child: Text(c['fullName']?.toString() ?? ''),
                  ),
              if (!countryKnown)
                DropdownMenuItem(value: _country, child: Text(_country)),
            ],
            onChanged: (v) {
              setState(() => _country = v ?? '');
              _loadLineups();
            },
          ),
          _gap,
          Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onFocusChange: (focused) {
              if (!focused) _loadLineups();
            },
            child: TextField(
              controller: _zip,
              onSubmitted: (_) => _loadLineups(),
              decoration: adminInputDecoration(label: l10n.adminSdPostalCode),
            ),
          ),
          _gap,
          if (_loadingLineups)
            const LinearProgressIndicator()
          else
            DropdownButtonFormField<String>(
              key: ValueKey(_lineups),
              initialValue: _listingsId.isEmpty ? null : _listingsId,
              isExpanded: true,
              decoration: adminInputDecoration(label: l10n.adminLiveTvSdLineup),
              items: [
                for (final l in _lineups)
                  DropdownMenuItem(
                    value: l['Id']?.toString() ?? '',
                    child: Text(l['Name']?.toString() ?? ''),
                  ),
              ],
              onChanged: (v) => setState(() => _listingsId = v ?? ''),
            ),
          const SizedBox(height: 4),
          ..._tunerRows(l10n),
        ],
        _errorText(context, _error),
      ],
    );
  }
}

/// Lists a provider's tuner channels and maps each to a guide channel, one
/// POST per pick.
class LiveTvChannelMapperDialog extends StatefulWidget {
  const LiveTvChannelMapperDialog({
    super.key,
    required this.api,
    required this.providerId,
    this.emby,
  });

  final AdminLiveTvApi api;
  final String providerId;

  /// On Emby, where the options only list the guide's channels and the tuner
  /// side comes from the managed channels.
  final EmbyAdminApi? emby;

  @override
  State<LiveTvChannelMapperDialog> createState() =>
      _LiveTvChannelMapperDialogState();
}

class _LiveTvChannelMapperDialogState
    extends State<LiveTvChannelMapperDialog> {
  bool _loading = true;
  List<Map<String, dynamic>> _channels = const [];
  List<Map<String, dynamic>> _providerChannels = const [];
  String _providerName = '';
  String? _busyId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final options = await widget.api.getChannelMappingOptions(
        widget.providerId,
      );
      final emby = widget.emby;
      final channels = emby == null
          ? liveTvMaps(options['TunerChannels'])
          : await _embyChannels(emby);
      if (!mounted) return;
      setState(() {
        _channels = channels;
        _providerChannels = liveTvMaps(options['ProviderChannels'])
          ..sort((a, b) => _text(a, 'Name').compareTo(_text(b, 'Name')));
        _providerName = _text(options, 'ProviderName');
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = describeError(e, AppLocalizations.of(context));
      });
    }
  }

  /// Every managed channel in the Jellyfin shape, keyed by its ManagementId,
  /// which is what a mapping names on Emby.
  Future<List<Map<String, dynamic>>> _embyChannels(EmbyAdminApi emby) async {
    final all = <Map<String, dynamic>>[];
    while (true) {
      final page = await emby.getManagedChannels(startIndex: all.length);
      final items = liveTvMaps(page['Items']);
      all.addAll(items);
      final total = (page['TotalRecordCount'] as num?)?.toInt() ?? 0;
      if (items.isEmpty || all.length >= total) break;
    }
    return [
      for (final c in all)
        {
          'Id': c['ManagementId'],
          'Name': [_text(c, 'ChannelNumber'), _text(c, 'Name')]
              .where((t) => t.isNotEmpty)
              .join(' '),
          if (c['ListingsProviderId'] == widget.providerId) ...{
            'ProviderChannelId': c['ListingsChannelId'],
            'ProviderChannelName': c['ListingsChannelName'],
          },
        },
    ];
  }

  Future<void> _pick(Map<String, dynamic> channel) async {
    final l10n = AppLocalizations.of(context);
    final current = _text(channel, 'ProviderChannelId').toLowerCase();
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_text(channel, 'Name')),
        content: SizedBox(
          width: 400,
          height: 480,
          child: ListView.builder(
            itemCount: _providerChannels.length,
            itemBuilder: (_, i) {
              final option = _providerChannels[i];
              final selected = _text(option, 'Id').toLowerCase() == current;
              return ListTile(
                title: Text(_text(option, 'Name')),
                selected: selected,
                trailing: selected ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, _text(option, 'Id')),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _busyId = _text(channel, 'Id');
      _error = null;
    });
    try {
      final mapping = await widget.api.setChannelMapping(
        widget.providerId,
        _text(channel, 'Id'),
        picked,
      );
      if (!mounted) return;
      // Emby's answer leaves out the guide channel.
      final option = _providerChannels
          .where((o) => _text(o, 'Id') == picked)
          .firstOrNull;
      setState(() {
        channel['ProviderChannelName'] =
            mapping['ProviderChannelName'] ?? option?['Name'];
        channel['ProviderChannelId'] = mapping['ProviderChannelId'] ?? picked;
        _busyId = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busyId = null;
        _error = l10n.adminChannelMappingsUpdateFailed(describeError(e, l10n));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _FormFrame(
      title: l10n.adminLiveTvMapChannels,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.close),
        ),
      ],
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (!_loading && _error == null && _channels.isEmpty)
          Text(l10n.adminLiveTvNoTunerChannels),
        for (final channel in _channels)
          ListTile(
            leading: const Icon(Icons.dvr),
            title: Text(_text(channel, 'Name')),
            subtitle: _text(channel, 'ProviderChannelName').isEmpty
                ? null
                : Text(
                    [_text(channel, 'ProviderChannelName'), _providerName]
                        .where((t) => t.isNotEmpty)
                        .join(' - '),
                  ),
            trailing: _busyId == _text(channel, 'Id')
                ? liveTvSpinner()
                : const Icon(Icons.edit_outlined),
            onTap: _busyId == null ? () => _pick(channel) : null,
          ),
        _errorText(context, _error),
      ],
    );
  }
}
