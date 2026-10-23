import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../util/error_message.dart';
import '../../../../util/image_mime.dart';
import '../admin_draft.dart';
import '../admin_nav.dart';
import '../widgets/admin_form_styles.dart';

class AdminBrandingScreen extends StatefulWidget {
  const AdminBrandingScreen({super.key});

  @override
  State<AdminBrandingScreen> createState() => _AdminBrandingScreenState();
}

class _AdminBrandingScreenState extends State<AdminBrandingScreen>
    with AdminDraftHost {
  late final MediaServerClient _client;
  AdminSystemApi get _api => _client.adminSystemApi;
  Map<String, dynamic>? _config;
  bool _loading = true;
  bool _uploadingSplash = false;
  int _splashVersion = 0;
  String? _error;

  /// SplashscreenEnabled as saved on the server. The switch saves the moment
  /// it changes, so it stays out of the draft. The working map keeps the
  /// loaded value, and a draft save re-reads the server's.
  bool _splashEnabled = false;
  bool _savingSplash = false;

  @override
  void initState() {
    super.initState();
    _client = GetIt.instance<MediaServerClient>();
    _load();
  }

  Future<void> _uploadSplashscreen() async {
    final l10n = AppLocalizations.of(context);
    final result = await FilePicker.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'],
      withData: true,
    );
    if (!mounted || result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final contentType = imageContentTypeForFileName(file.name);
    final bytes = file.bytes ??
        (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (contentType == null || bytes == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.adminBrandingSplashUploadFailed)),
      );
      return;
    }
    setState(() => _uploadingSplash = true);
    try {
      await _api.uploadSplashscreen(bytes, contentType);
      if (!mounted) return;
      setState(() => _splashVersion++);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.adminBrandingSplashUploaded)),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.adminBrandingSplashUploadFailed)),
      );
    } finally {
      if (mounted) setState(() => _uploadingSplash = false);
    }
  }

  Future<void> _deleteSplashscreen() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _uploadingSplash = true);
    try {
      await _api.deleteSplashscreen();
      if (!mounted) return;
      setState(() => _splashVersion++);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.adminBrandingSplashDeleted)),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.adminSettingsSaveFailed(describeError(e, l10n)))),
      );
    } finally {
      if (mounted) setState(() => _uploadingSplash = false);
    }
  }

  Future<void> _setSplashEnabled(bool value) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _splashEnabled = value;
      _savingSplash = true;
    });
    try {
      final fresh = await _api.getNamedConfiguration('branding');
      fresh['SplashscreenEnabled'] = value;
      await _api.updateNamedConfiguration('branding', fresh);
    } catch (e) {
      if (!mounted) return;
      setState(() => _splashEnabled = !value);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.adminSettingsSaveFailed(describeError(e, l10n)))),
      );
    } finally {
      if (mounted) setState(() => _savingSplash = false);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = await _api.getNamedConfiguration('branding');
      if (!mounted) return;
      setState(() {
        _config = config;
        _splashEnabled = config['SplashscreenEnabled'] as bool? ?? false;
        _loading = false;
      });
      hostDraft(
        AdminDraft.single(
          working: config,
          reload: () => _api.getNamedConfiguration('branding'),
          post: (value) => _api.updateNamedConfiguration('branding', value),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeError(e, AppLocalizations.of(context));
        _loading = false;
      });
    }
  }

  Widget _buildSplashPreview(AppLocalizations l10n) {
    final base = _client.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final url = '$base/Branding/Splashscreen?t=$_splashVersion';
    final muted = AppColorScheme.onSurface.withValues(alpha: 0.5);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.spaceLg,
        vertical: AppSpacing.spaceMd,
      ),
      child: ClipRRect(
        borderRadius: AppRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColorScheme.onSurface.withValues(alpha: 0.05),
            ),
            child: Image.network(
              url,
              key: ValueKey(_splashVersion),
              headers: serverImageHeaders,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.image_not_supported_outlined, color: muted),
                    const SizedBox(height: 8),
                    Text(
                      l10n.adminBrandingNoSplash,
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSplashButtons(AppLocalizations l10n) {
    final enabled = _splashEnabled && !_uploadingSplash;
    return adminFieldRow(
      label: l10n.adminBrandingSplashUpload,
      helper: l10n.adminBrandingSplashSizeHint,
      child: Row(
        children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: enabled ? _uploadSplashscreen : null,
              icon: _uploadingSplash
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_outlined),
              label: Text(l10n.adminBrandingSplashUpload),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: enabled ? _deleteSplashscreen : null,
            icon: const Icon(Icons.delete_outline),
            label: Text(l10n.delete),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _config == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.adminBrandingLoadFailed,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_error ?? l10n.adminUnknownError,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: _load, child: Text(l10n.retry)),
          ],
        ),
      );
    }

    final bottomSafe = MediaQuery.of(context).padding.bottom;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 20, 16, bottomSafe + 40),
      children: [
        adminScreenHeader(
          context,
          title: l10n.adminBrandingTitle,
          icon: Icons.brush_outlined,
        ),
        // Emby has no splash screen.
        if (!AdminServerScope.isEmby(context))
          adminSection(
            context,
            title: l10n.adminBrandingSplashSection,
            icon: Icons.image_outlined,
            children: [
              adminSwitchRow(
                title: l10n.adminBrandingEnableSplash,
                anchor: 'branding.SplashscreenEnabled',
                value: _splashEnabled,
                onChanged: _savingSplash ? (_) {} : _setSplashEnabled,
              ),
              _buildSplashButtons(l10n),
              if (_splashEnabled) _buildSplashPreview(l10n),
            ],
          ),
        draftKeyed(
          adminSection(
            context,
            title: l10n.adminBrandingSectionWebClient,
            icon: Icons.web_outlined,
            children: [
              adminFieldRow(
                label: l10n.adminBrandingLoginDisclaimer,
                helper: l10n.adminBrandingLoginDisclaimerHint,
                anchor: 'branding.LoginDisclaimer',
                child: TextFormField(
                  initialValue: _config!['LoginDisclaimer']?.toString() ?? '',
                  decoration: adminInputDecoration(),
                  minLines: 5,
                  maxLines: 5,
                  onChanged: (v) {
                    _config!['LoginDisclaimer'] = v;
                    edited();
                  },
                ),
              ),
              adminFieldRow(
                label: l10n.adminBrandingCustomCss,
                helper: l10n.adminBrandingCustomCssHint,
                anchor: 'branding.CustomCss',
                child: TextFormField(
                  initialValue: _config!['CustomCss']?.toString() ?? '',
                  decoration: adminInputDecoration(),
                  minLines: 5,
                  maxLines: 20,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  onChanged: (v) {
                    _config!['CustomCss'] = v;
                    edited();
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
